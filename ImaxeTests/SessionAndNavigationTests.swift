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
  @Test func `renaming current image updates session without replacing decoded content`(
  ) async throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-rename-current-image")
    defer { try? FileManager.default.removeItem(at: directory) }
    let sourceURL = directory.appending(path: "before.png")
    let destinationURL = directory.appending(path: "after.png")
    try TestSupport.pngData(width: 10, height: 20).write(to: sourceURL)
    let document = try await ImageLoader.shared.loadDocument(from: sourceURL)
    let session = ImageSession(imageDocument: document)
    session.loadFolderImageURLs = { [$0] }
    var updatedLocation: (String, URL)?
    session.updateRecentImageLocation = { oldPath, newURL in
      updatedLocation = (oldPath, newURL)
    }

    let didRename = session.renameCurrentImage(to: "after.png")

    #expect(didRename)
    #expect(!sourceURL.fileExists)
    #expect(destinationURL.fileExists)
    #expect(session.displayedURL == destinationURL)
    #expect(session.currentMetadata?.fileName == "after.png")
    #expect(session.currentDocument?.url == destinationURL)
    #expect(session.currentDocument?.id == document.id)
    #expect(session.currentDocument?.nsImage === document.nsImage)
    #expect(session.folderNavigator?.currentImageURL == destinationURL)
    try await TestSupport.waitUntil { updatedLocation?.1 == destinationURL }
    #expect(updatedLocation?.0 == sourceURL.filePath)
  }

  @Test func `moving current image updates its location and navigator`() async throws {
    let sourceDirectory = try TestSupport.temporaryDirectory(prefix: "imaxe-move-source")
    let destinationDirectory = try TestSupport.temporaryDirectory(prefix: "imaxe-move-destination")
    defer {
      try? FileManager.default.removeItem(at: sourceDirectory)
      try? FileManager.default.removeItem(at: destinationDirectory)
    }
    let sourceURL = sourceDirectory.appending(path: "image.png")
    let destinationURL = destinationDirectory.appending(path: "image.png")
    try TestSupport.pngData(width: 10, height: 20).write(to: sourceURL)
    let document = try await ImageLoader.shared.loadDocument(from: sourceURL)
    let session = ImageSession(imageDocument: document)
    session.loadFolderImageURLs = { [$0] }

    let didMove = session.moveCurrentImage(to: destinationDirectory)

    #expect(didMove)
    #expect(!sourceURL.fileExists)
    #expect(destinationURL.fileExists)
    #expect(session.displayedURL == destinationURL)
    #expect(session.currentMetadata?.location == destinationDirectory.filePath)
    #expect(session.currentDocument?.id == document.id)
    #expect(session.folderNavigator?.rootURL == destinationDirectory)
  }

  @Test func `current image tags can be selected and cleared`() async throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-file-tags")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "tagged.png")
    try TestSupport.pngData(width: 10, height: 20).write(to: url)
    let document = try await ImageLoader.shared.loadDocument(from: url)
    let session = ImageSession(imageDocument: document)
    let tagNames: Set = ["Imaxe Test Tag"]

    #expect(session.setCurrentImageTagNames(tagNames))
    #expect(session.currentImageTagNames() == tagNames)
    #expect(session.setCurrentImageTagNames([]))
    #expect(session.currentImageTagNames().isEmpty)
  }

  @Test func `file change reload keeps current document while loading`() async throws {
    let url = URL.temporaryDirectory
      .appending(path: "imaxe-session-reload-\(UUID().uuidString).png")
    try TestSupport.pngData(width: 10, height: 20).write(to: url)
    let initialDocument = try await ImageLoader.shared.loadDocument(from: url)
    let session = ImageSession(imageDocument: initialDocument)

    session.loadImage(from: url, preservingViewportOnReload: true)

    #expect(session.currentDocument?.id == initialDocument.id)
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

  @Test func `folder navigator keeps current image positioned when scan omits it`() {
    let directory = URL(fileURLWithPath: "/tmp/imaxe-positioned-navigation")
    let firstURL = directory.appending(path: "a.png")
    let currentURL = directory.appending(path: "b.png")

    let navigator = FolderNavigator(
      for: currentURL,
      enableLoopBrowsing: false,
      imageURLs: [firstURL],
    )

    #expect(navigator.imageURLs == [firstURL, currentURL])
    #expect(navigator.currentIndex == 1)
    #expect(navigator.positionDescription == "2/2")
  }

  @Test func `setting current image across folders reloads the destination folder`() throws {
    let firstDirectory = try TestSupport.temporaryDirectory(prefix: "imaxe-first-folder")
    let secondDirectory = try TestSupport.temporaryDirectory(prefix: "imaxe-second-folder")
    defer {
      try? FileManager.default.removeItem(at: firstDirectory)
      try? FileManager.default.removeItem(at: secondDirectory)
    }

    let firstURL = firstDirectory.appending(path: "first.png")
    let secondURL = secondDirectory.appending(path: "b.png")
    let secondSiblingURL = secondDirectory.appending(path: "a.png")
    try TestSupport.pngData(width: 10, height: 10).write(to: firstURL)
    try TestSupport.pngData(width: 20, height: 20).write(to: secondURL)
    try TestSupport.pngData(width: 30, height: 30).write(to: secondSiblingURL)

    var navigator = FolderNavigator(
      for: firstURL,
      enableLoopBrowsing: false,
      imageURLs: [firstURL],
    )

    navigator.currentImageURL = secondURL

    #expect(navigator.rootURL == secondDirectory)
    #expect(navigator.imageURLs.map(\.lastPathComponent) == ["a.png", "b.png"])
    #expect(!navigator.imageURLs.contains(firstURL))
    #expect(navigator.currentIndex == 1)
  }

  @Test func `failed destination folder scan does not retain the old folder`() throws {
    let firstDirectory = try TestSupport.temporaryDirectory(prefix: "imaxe-readable-folder")
    defer { try? FileManager.default.removeItem(at: firstDirectory) }
    let firstURL = firstDirectory.appending(path: "first.png")
    try TestSupport.pngData(width: 10, height: 10).write(to: firstURL)
    let nonDirectoryURL = firstDirectory.appending(path: "not-a-directory")
    try Data().write(to: nonDirectoryURL)
    let destinationURL = nonDirectoryURL.appending(path: "destination.png")

    var navigator = FolderNavigator(
      for: firstURL,
      enableLoopBrowsing: false,
      imageURLs: [firstURL],
    )

    navigator.currentImageURL = destinationURL

    #expect(navigator.currentImageURL == destinationURL)
    #expect(navigator.imageURLs == [destinationURL])
    #expect(!navigator.imageURLs.contains(firstURL))
  }

  @Test func `folder scan propagates cancellation`() async {
    let url = TestSupport.sampleImageURL("sample_1280×853.png")
    let task = Task {
      await FolderNavigator.imageURLs(for: url)
    }
    task.cancel()

    #expect(await task.value == nil)
  }

  @Test func `image file watcher reports stable file change`() async throws {
    let url = URL.temporaryDirectory
      .appending(path: "imaxe-watched-image-\(UUID().uuidString).png")
    try TestSupport.pngData(width: 10, height: 20).write(to: url)
    let changedImageData = try TestSupport.pngData(width: 12, height: 24)

    var watcher: ImageFileWatcher?
    let event = await withCheckedContinuation { continuation in
      watcher = ImageFileWatcher(url: url) { event in
        continuation.resume(returning: event)
      }

      DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(100)) {
        try? changedImageData.write(to: url)
        try? FileManager.default.setAttributes(
          [.modificationDate: Date(timeIntervalSinceNow: 2)],
          ofItemAtPath: url.filePath,
        )
      }
    }

    #expect(event == .modified)
    _ = watcher
  }

  @Test func `image file watcher distinguishes replacement deletion and recreation`() async throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-file-watcher-events")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "watched.png")
    let replacementURL = directory.appending(path: "replacement.png")
    try TestSupport.pngData(width: 10, height: 20).write(to: url)

    var events: [ImageFileWatcher.Event] = []
    let watcher = ImageFileWatcher(url: url) { event in
      events.append(event)
    }

    try TestSupport.pngData(width: 12, height: 24).write(to: replacementURL)
    _ = try FileManager.default.replaceItemAt(url, withItemAt: replacementURL)
    try await TestSupport.waitUntil {
      events.contains(.replaced)
    }

    try FileManager.default.removeItem(at: url)
    try await TestSupport.waitUntil {
      events.contains(.deleted)
    }

    try TestSupport.pngData(width: 14, height: 28).write(to: url)
    try await TestSupport.waitUntil {
      events.contains(.recreated)
    }

    #expect(events.filter { $0 == .replaced }.count == 1)
    #expect(events.filter { $0 == .deleted }.count == 1)
    #expect(events.filter { $0 == .recreated }.count == 1)
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
    session.loadImageMetadata = { url, requestID in
      if url == a {
        try? await Task.sleep(for: .milliseconds(150))
      } else if url == b {
        try? await Task.sleep(for: .milliseconds(75))
      }
      return try await ImageLoader.shared.loadMetadata(from: url, requestID: requestID)
    }
    session.loadImageDocument = { url, requestID in
      if url == a {
        try? await Task.sleep(for: .milliseconds(150))
      } else if url == b {
        try? await Task.sleep(for: .milliseconds(75))
      }
      return try await ImageLoader.shared.loadDocument(from: url, requestID: requestID)
    }

    session.loadImage(from: a, addToRecent: false)
    session.loadImage(from: b, addToRecent: false)
    session.loadImage(from: c, addToRecent: false)
    try await TestSupport.waitUntil { !session.isLoading }
    try await Task.sleep(for: .milliseconds(200))

    #expect(session.displayedURL == c)
    #expect(session.pendingURL == nil)
    #expect(session.currentMetadata?.displayPixelSize == IntSize(width: 30, height: 30))
    #expect(session.folderNavigator?.currentImageURL == c)
  }

  @Test func `stale folder scan cannot replace a newer folder`() async throws {
    let firstDirectory = try TestSupport.temporaryDirectory(prefix: "imaxe-stale-folder")
    let secondDirectory = try TestSupport.temporaryDirectory(prefix: "imaxe-current-folder")
    defer {
      try? FileManager.default.removeItem(at: firstDirectory)
      try? FileManager.default.removeItem(at: secondDirectory)
    }
    let firstURL = firstDirectory.appending(path: "first.png")
    let firstSiblingURL = firstDirectory.appending(path: "first-sibling.png")
    let secondURL = secondDirectory.appending(path: "b.png")
    let secondSiblingURL = secondDirectory.appending(path: "a.png")
    for url in [firstURL, firstSiblingURL, secondURL, secondSiblingURL] {
      try TestSupport.pngData(width: 10, height: 10).write(to: url)
    }

    let (folderLoads, folderLoadContinuation) = AsyncStream<URL>.makeStream()
    let session = ImageSession()
    configureImmediateLoading(session)
    session.loadFolderImageURLs = { url in
      folderLoadContinuation.yield(url)
      if url == firstURL {
        await Task.detached {
          try? await Task.sleep(for: .milliseconds(150))
        }.value
        return [firstSiblingURL, firstURL]
      }
      return [secondSiblingURL, secondURL]
    }

    var folderLoadIterator = folderLoads.makeAsyncIterator()
    session.loadImage(from: firstURL, addToRecent: false)
    #expect(await folderLoadIterator.next() == firstURL)

    session.loadImage(from: secondURL, addToRecent: false)
    try await TestSupport.waitUntil { !session.isLoading }
    try await Task.sleep(for: .milliseconds(200))

    #expect(session.folderNavigator?.rootURL == secondDirectory)
    #expect(session.folderNavigator?.currentImageURL == secondURL)
    #expect(session.folderNavigator?.imageURLs == [secondSiblingURL, secondURL])
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
    let loader = ImageLoader.shared
    session.loadImageMetadata = { url, requestID in
      if url == firstURL {
        try await Task.sleep(for: .seconds(5))
      }
      return try await loader.loadMetadata(from: url, requestID: requestID)
    }
    session.loadImageDocument = { url, requestID in
      if url == firstURL {
        try await Task.sleep(for: .seconds(5))
      }
      return try await loader.loadDocument(from: url, requestID: requestID)
    }
    session.loadFolderImageURLs = { [$0] }

    session.loadImage(from: firstURL, addToRecent: false)
    try await TestSupport.waitUntil { session.hasActiveLoadingTimer }

    session.loadImage(from: secondURL, addToRecent: false)
    try await TestSupport.waitUntil { session.displayedURL == secondURL && !session.isLoading }

    #expect(session.loadingElapsedTime == 0)
  }

  @Test func `preloaded metadata is visible while document loads`() async throws {
    let url = TestSupport.sampleImageURL("sample_1280×853.png")
    let session = ImageSession()
    let (documentGate, documentGateContinuation) = AsyncStream<Void>.makeStream()
    defer { documentGateContinuation.finish() }
    session.loadImageDocument = { url, requestID in
      for await _ in documentGate {
        break
      }
      try Task.checkCancellation()
      return try await ImageLoader.shared.loadDocument(from: url, requestID: requestID)
    }

    session.loadImage(from: url, addToRecent: false)
    try await TestSupport.waitUntil { session.currentMetadata?.url == url }

    #expect(session.currentDocument == nil)
    #expect(session.pendingURL == url)

    documentGateContinuation.yield()
    documentGateContinuation.finish()
    try await TestSupport.waitUntil { !session.isLoading }
    #expect(session.currentDocument != nil)
    #expect(session.currentMetadata == session.currentDocument?.metadata)
  }

  @Test func `document commit does not wait for preloaded metadata`() async throws {
    let url = TestSupport.sampleImageURL("sample_1280×853.png")
    let session = ImageSession()
    session.loadImageMetadata = { _, _ in
      try await Task.sleep(for: .seconds(5))
      throw CancellationError()
    }

    session.loadImage(from: url, addToRecent: false)
    try await TestSupport.waitUntil { !session.isLoading }

    let document = try #require(session.currentDocument)
    #expect(session.currentMetadata == document.metadata)
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
    configureImmediateLoading(session)
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
    configureImmediateLoading(session)
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
    session.loadImageMetadata = { _, _ in
      throw ImageLoadingError.fileNotFound(missingURL)
    }
    session.loadImageDocument = { _, _ in
      throw ImageLoadingError.fileNotFound(missingURL)
    }
    session.loadFolderImageURLs = { [$0] }

    session.loadImage(
      from: missingURL,
      recentImagePathToRemoveOnFileNotFound: missingURL.filePath,
      onFailure: { didFail = true },
    )
    try await TestSupport.waitUntil { !session.isLoading }

    #expect(removedPath == missingURL.filePath)
    #expect(didFail)
    #expect(session.alertTitle == "Recent Image Removed")
  }

  @Test func `failed navigation preserves displayed image and position`() async throws {
    let goodURL = TestSupport.sampleImageURL("sample_1280×853.png")
    let initialDocument = try await ImageLoader.shared.loadDocument(from: goodURL)
    let session = ImageSession(imageDocument: initialDocument)
    let corruptURL = URL.temporaryDirectory
      .appending(path: "imaxe-corrupt-navigation-\(UUID().uuidString).png")
    try Data("not an image".utf8).write(to: corruptURL)
    defer { try? FileManager.default.removeItem(at: corruptURL) }

    session.loadImage(from: corruptURL, addToRecent: false)
    try await TestSupport.waitUntil { !session.isLoading }

    #expect(session.currentDocument?.id == initialDocument.id)
    #expect(session.displayedURL == goodURL)
    #expect(session.folderNavigator?.currentImageURL == goodURL)
    #expect(session.pendingURL == nil)
    #expect(session.alertTitle == "Failed to Load Image")
  }

  @Test func `dismissing an alert clears its presentation state`() {
    let session = ImageSession()

    session.alertTitle = "Test Alert"
    session.alertMessage = "Test Message"

    #expect(session.isAlertPresented)
    #expect(session.alertTitle == "Test Alert")
    #expect(session.alertMessage == "Test Message")

    session.isAlertPresented = false

    #expect(!session.isAlertPresented)
    #expect(session.alertTitle == "")
    #expect(session.alertMessage == nil)
  }

  private func configureImmediateLoading(_ session: ImageSession) {
    session.loadImageMetadata = { url, requestID in
      try await ImageLoader.shared.loadMetadata(from: url, requestID: requestID)
    }
    session.loadImageDocument = { url, requestID in
      try await ImageLoader.shared.loadDocument(from: url, requestID: requestID)
    }
    session.loadFolderImageURLs = { [$0] }
  }
}
