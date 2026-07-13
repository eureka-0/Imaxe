//
//  SessionAndNavigationTests.swift
//  ImaxeTests
//
//  Created by lxlong on 2026/6/14.
//

import AppKit
@testable import Imaxe
import SwiftUI
import Testing

@MainActor
@Suite("Session And Navigation")
struct SessionAndNavigationTests {
  @Test func `file change reload keeps current image while loading`() throws {
    let url = URL.temporaryDirectory
      .appending(path: "imaxe-session-reload-\(UUID().uuidString).png")
    try TestSupport.pngData(width: 10, height: 20).write(to: url)
    let initialImage = ImageContainer(url: url, nsImage: TestSupport.bitmapImage())
    let session = ImageSession(imageContainer: initialImage)

    session.loadImage(from: url, preservingViewportOnReload: true)

    #expect(session.currentImage === initialImage)
    #expect(!session.shouldApplyLoadedImageWindowSize)
  }

  @Test func `restoring standard window buttons shows hidden titlebar controls`() {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: NSSize(width: 200, height: 200)),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false,
    )
    let session = ImageSession()

    session.bindWindow(window)

    #expect(window.standardWindowButton(.closeButton)?.isHidden == true)
    #expect(window.standardWindowButton(.miniaturizeButton)?.isHidden == true)
    #expect(window.standardWindowButton(.zoomButton)?.isHidden == true)

    session.restoreStandardWindowButtons()

    #expect(window.standardWindowButton(.closeButton)?.isHidden == false)
    #expect(window.standardWindowButton(.miniaturizeButton)?.isHidden == false)
    #expect(window.standardWindowButton(.zoomButton)?.isHidden == false)
  }

  @Test func `folder navigator starts with current image and loads asynchronously`() async throws {
    let directory = URL.temporaryDirectory
      .appending(path: "imaxe-folder-navigation-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let firstURL = directory.appending(path: "b.png")
    let secondURL = directory.appending(path: "a.png")
    try TestSupport.pngData(width: 10, height: 20).write(to: firstURL)
    try TestSupport.pngData(width: 12, height: 24).write(to: secondURL)

    let navigator = FolderNavigator(for: firstURL, enableLoopBrowsing: false)
    let imageURLs = try #require(await FolderNavigator.imageURLs(for: firstURL))

    #expect(navigator.imageURLs == [firstURL])
    #expect(imageURLs.map(\.lastPathComponent) == ["a.png", "b.png"])
  }

  @Test func `image file watcher reports stable file change`() async throws {
    let url = URL.temporaryDirectory
      .appending(path: "imaxe-watched-image-\(UUID().uuidString).png")
    try TestSupport.pngData(width: 10, height: 20).write(to: url)
    let changedImageData = try TestSupport.pngData(width: 12, height: 24)

    var watcher: ImageFileWatcher?
    let didChange = await withCheckedContinuation { continuation in
      watcher = ImageFileWatcher(url: url) {
        continuation.resume(returning: true)
      }

      DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(100)) {
        try? changedImageData.write(to: url)
        try? FileManager.default.setAttributes(
          [.modificationDate: Date(timeIntervalSinceNow: 2)],
          ofItemAtPath: url.filePath,
        )
      }
    }

    #expect(didChange)
    _ = watcher
  }

  @Test func `rapid image switching commits only latest request`() async throws {
    let directory = URL.temporaryDirectory
      .appending(path: "imaxe-rapid-switch-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let a = directory.appending(path: "a.png")
    let b = directory.appending(path: "b.png")
    let c = directory.appending(path: "c.png")
    try TestSupport.pngData(width: 10, height: 10).write(to: a)
    try TestSupport.pngData(width: 20, height: 20).write(to: b)
    try TestSupport.pngData(width: 30, height: 30).write(to: c)

    let session = ImageSession()
    session.loadImageInfo = { url, requestID in
      if url == a {
        try? await Task.sleep(for: .milliseconds(150))
      } else if url == b {
        try? await Task.sleep(for: .milliseconds(75))
      }
      return try await ImageLoader.shared.loadInfo(from: url, requestID: requestID)
    }
    session.loadImageContainer = { url, requestID in
      if url == a {
        try? await Task.sleep(for: .milliseconds(150))
      } else if url == b {
        try? await Task.sleep(for: .milliseconds(75))
      }
      return try await ImageLoader.shared.loadImage(from: url, requestID: requestID)
    }

    session.loadImage(from: a, addToRecent: false)
    session.loadImage(from: b, addToRecent: false)
    session.loadImage(from: c, addToRecent: false)
    try await TestSupport.waitUntil { !session.isLoading }
    try await Task.sleep(for: .milliseconds(200))

    #expect(session.displayedURL == c)
    #expect(session.pendingURL == nil)
    #expect(session.currentImageInfo?.pixelSize == IntSize(width: 30, height: 30))
    #expect(session.folderNavigator?.currentImageURL == c)
  }

  @Test func `image loading timer stops after a replaced request`() async throws {
    let directory = URL.temporaryDirectory
      .appending(path: "imaxe-loading-timer-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let firstURL = directory.appending(path: "first.png")
    let secondURL = directory.appending(path: "second.png")
    try TestSupport.pngData(width: 10, height: 10).write(to: firstURL)
    try TestSupport.pngData(width: 20, height: 20).write(to: secondURL)

    let session = ImageSession()
    session.loadImageInfo = { url, requestID in
      try await Task.sleep(for: .milliseconds(150))
      return try await ImageLoader.shared.loadInfo(from: url, requestID: requestID)
    }
    session.loadImageContainer = { url, requestID in
      try await Task.sleep(for: .milliseconds(150))
      return try await ImageLoader.shared.loadImage(from: url, requestID: requestID)
    }

    session.loadImage(from: firstURL, addToRecent: false)
    try await TestSupport.waitUntil { session.loadingElapsedTime > 0 }

    session.loadImage(from: secondURL, addToRecent: false)
    try await TestSupport.waitUntil { !session.isLoading }
    try await Task.sleep(for: .milliseconds(100))

    #expect(session.loadingElapsedTime == 0)
  }

  @Test func `delayed metadata prevents partial image commit`() async throws {
    let url = TestSupport.sampleImageURL("sample_1280×853.png")
    let session = ImageSession()
    session.loadImageInfo = { url, requestID in
      try await Task.sleep(for: .milliseconds(100))
      return try await ImageLoader.shared.loadInfo(from: url, requestID: requestID)
    }

    session.loadImage(from: url, addToRecent: false)
    try await Task.sleep(for: .milliseconds(25))

    #expect(session.currentImage == nil)
    #expect(session.currentImageInfo == nil)
    #expect(session.pendingURL == url)

    try await TestSupport.waitUntil { !session.isLoading }
    #expect(session.currentImage != nil)
    #expect(session.currentImageInfo?.url == url)
  }

  @Test func `temporary image is removed after switching images`() async throws {
    let temporaryURL = URL.temporaryDirectory
      .appending(path: "imaxe-temporary-image-\(UUID().uuidString).png")
    let replacementURL = URL.temporaryDirectory
      .appending(path: "imaxe-replacement-image-\(UUID().uuidString).png")
    try TestSupport.pngData(width: 10, height: 20).write(to: temporaryURL)
    try TestSupport.pngData(width: 20, height: 10).write(to: replacementURL)
    defer {
      try? FileManager.default.removeItem(at: temporaryURL)
      try? FileManager.default.removeItem(at: replacementURL)
    }

    let session = ImageSession()
    session.loadImage(from: temporaryURL, addToRecent: false, temporaryURL: temporaryURL)
    try await TestSupport.waitUntil { !session.isLoading }

    #expect(FileManager.default.fileExists(atPath: temporaryURL.path))

    session.loadImage(from: replacementURL, addToRecent: false)
    try await TestSupport.waitUntil { !session.isLoading }

    #expect(!FileManager.default.fileExists(atPath: temporaryURL.path))
  }

  @Test func `temporary image is removed when image window closes`() async throws {
    let temporaryURL = URL.temporaryDirectory
      .appending(path: "imaxe-closed-temporary-image-\(UUID().uuidString).png")
    try TestSupport.pngData(width: 10, height: 20).write(to: temporaryURL)
    defer { try? FileManager.default.removeItem(at: temporaryURL) }

    let session = ImageSession()
    session.loadImage(from: temporaryURL, addToRecent: false, temporaryURL: temporaryURL)
    try await TestSupport.waitUntil { !session.isLoading }

    session.close()

    #expect(!FileManager.default.fileExists(atPath: temporaryURL.path))
  }

  @Test func `failed initial recent image load removes record and reports failure`() async throws {
    let missingURL = URL.temporaryDirectory
      .appending(path: "imaxe-missing-recent-\(UUID().uuidString).png")
    let session = ImageSession()
    var removedPath: String?
    var didFail = false
    session.removeRecentImage = { removedPath = $0 }

    session.loadImage(
      from: missingURL,
      recentImagePathToRemoveOnFileNotFound: missingURL.filePath,
      onFailure: { didFail = true },
    )
    try await TestSupport.waitUntil { !session.isLoading }

    #expect(removedPath == missingURL.filePath)
    #expect(didFail)
    #expect(session.alert?.title == "Recent Image Removed")
  }

  @Test func `failed navigation preserves displayed image and position`() async throws {
    let goodURL = TestSupport.sampleImageURL("sample_1280×853.png")
    let initialImage = ImageContainer(url: goodURL, nsImage: TestSupport.bitmapImage())
    let session = ImageSession(imageContainer: initialImage)
    let corruptURL = URL.temporaryDirectory
      .appending(path: "imaxe-corrupt-navigation-\(UUID().uuidString).png")
    try Data("not an image".utf8).write(to: corruptURL)
    defer { try? FileManager.default.removeItem(at: corruptURL) }

    session.loadImage(from: corruptURL, addToRecent: false)
    try await TestSupport.waitUntil { !session.isLoading }

    #expect(session.currentImage === initialImage)
    #expect(session.displayedURL == goodURL)
    #expect(session.folderNavigator?.currentImageURL == goodURL)
    #expect(session.pendingURL == nil)
    #expect(session.alert?.title == "Failed to Load Image")
  }
}
