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
}
