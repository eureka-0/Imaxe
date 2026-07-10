//
//  ImaxeTests.swift
//  ImaxeTests
//
//  Created by lxlong on 2026/6/14.
//

import AppKit
@testable import Imaxe
import SwiftData
import SwiftUI
import Testing

// MARK: - Image View

@MainActor
@Suite("Image View")
struct ImageViewTests {
  @Test func `bitmap image container uses pixel size`() {
    let image = TestSupport.bitmapImage()
    let url = URL(fileURLWithPath: "/tmp/example.png")

    let imageContainer = ImageContainer(url: url, nsImage: image)

    #expect(imageContainer.pixelSize == NSSize(width: 10, height: 20))
    #expect(imageContainer.nsImage.size == NSSize(width: 10, height: 20))
  }

  @Test func `canvas occupies image pixel size in backing pixels`() {
    let image = TestSupport.bitmapImage()
    let url = URL(fileURLWithPath: "/tmp/example.png")
    let imageContainer = ImageContainer(url: url, nsImage: image)
    let imageInfo = ImageInfo(url: url)

    let canvas = ImageCanvasView(
      imageContainer: imageContainer,
      imageInfo: imageInfo,
    )
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: NSSize(width: 200, height: 200)),
      styleMask: [.titled],
      backing: .buffered,
      defer: false,
    )
    window.contentView?.addSubview(canvas)

    let backingSize = canvas.convertToBacking(canvas.bounds.size)
    #expect(backingSize.isApproximatelyEqual(to: imageContainer.pixelSize))
  }

  @Test func `always fit to window still applies after viewport preserving image change`() {
    var reportedZoomScale: CGFloat?
    let coordinator = ImageScrollView.Coordinator(
      onZoomScaleChange: { reportedZoomScale = $0 },
      onAlwaysFitToWindowChange: { _ in },
    )
    let scrollView = NSScrollView(
      frame: NSRect(origin: .zero, size: NSSize(width: 100, height: 100)),
    )
    let imageView = NSView(frame: NSRect(origin: .zero, size: NSSize(width: 200, height: 100)))
    let imageContainer = ImageContainer(
      url: URL(fileURLWithPath: "/tmp/example.png"),
      nsImage: TestSupport.bitmapImage(width: 200, height: 100),
    )
    scrollView.allowsMagnification = true
    scrollView.minMagnification = Constants.imageZoomScaleRange.lowerBound
    scrollView.maxMagnification = Constants.imageZoomScaleRange.upperBound
    scrollView.documentView = imageView
    coordinator.updateAlwaysFitToWindowFromBinding(true)
    coordinator.prepareForImage(
      imageContainer,
      shouldApplyLoadedImageWindowSize: false,
    )

    coordinator.scrollViewDidLayout(scrollView)

    #expect(!coordinator.hasPendingCommands)
    #expect(scrollView.magnification.isApproximatelyEqual(to: 0.5))
    #expect(reportedZoomScale?.isApproximatelyEqual(to: 0.5) == true)
  }

  @Test func `double click triggers fit to screen`() throws {
    let scrollView = ImageScrollView.ImageNSScrollView()
    var didTriggerDoubleClick = false
    scrollView.onDoubleClick = {
      didTriggerDoubleClick = true
    }
    let event = try #require(NSEvent.mouseEvent(
      with: .leftMouseDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      eventNumber: 0,
      clickCount: 2,
      pressure: 1,
    ))

    scrollView.mouseDown(with: event)

    #expect(didTriggerDoubleClick)
  }

  @Test func `fit to screen command is queued`() {
    let coordinator = ImageScrollView.Coordinator(
      onZoomScaleChange: { _ in },
      onAlwaysFitToWindowChange: { _ in },
    )
    let viewportController = ImageViewportController()
    let scrollView = NSScrollView(
      frame: NSRect(origin: .zero, size: NSSize(width: 100, height: 100)),
    )
    scrollView.documentView = NSView(
      frame: NSRect(origin: .zero, size: NSSize(width: 200, height: 100)),
    )
    coordinator.observe(scrollView)
    coordinator.bind(to: viewportController)

    viewportController.fitToScreen()

    #expect(coordinator.hasPendingCommands)
  }

  @Test func `fit to screen double click restores previous viewport`() async throws {
    let originalZoomScale = CGFloat(0.25)
    var alwaysFitChanges: [Bool] = []
    let coordinator = ImageScrollView.Coordinator(
      onZoomScaleChange: { _ in },
      onAlwaysFitToWindowChange: { alwaysFitChanges.append($0) },
    )
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: NSSize(width: 320, height: 240)),
      styleMask: [.titled, .resizable],
      backing: .buffered,
      defer: false,
    )
    let originalWindowFrame = window.frame
    let scrollView = ImageScrollView.ImageNSScrollView(frame: window.contentView?.bounds ?? .zero)
    let imageView = NSView(frame: NSRect(origin: .zero, size: NSSize(width: 1000, height: 500)))
    scrollView.allowsMagnification = true
    scrollView.minMagnification = Constants.imageZoomScaleRange.lowerBound
    scrollView.maxMagnification = Constants.imageZoomScaleRange.upperBound
    scrollView.documentView = imageView
    scrollView.magnification = originalZoomScale
    window.contentView = scrollView
    coordinator.observe(scrollView)
    coordinator.updateAlwaysFitToWindowFromBinding(true)

    coordinator.handle(.fitToScreen)
    try await TestSupport.waitUntil {
      coordinator.isFitToScreenToggleActive
        && !window.frame.isApproximatelyEqual(to: originalWindowFrame)
        && scrollView.magnification > originalZoomScale
    }

    #expect(coordinator.alwaysFitToWindow == false)
    #expect(alwaysFitChanges.last == false)

    coordinator.handle(.fitToScreen)
    try await TestSupport.waitUntil {
      !coordinator.isFitToScreenToggleActive
        && window.frame.isApproximatelyEqual(to: originalWindowFrame)
        && scrollView.magnification.isApproximatelyEqual(to: originalZoomScale)
    }
  }

  @Test func `stale fit to screen animation does not override restore`() async throws {
    let originalZoomScale = CGFloat(0.25)
    let coordinator = ImageScrollView.Coordinator(
      onZoomScaleChange: { _ in },
      onAlwaysFitToWindowChange: { _ in },
    )
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: NSSize(width: 320, height: 240)),
      styleMask: [.titled, .resizable],
      backing: .buffered,
      defer: false,
    )
    let originalWindowFrame = window.frame
    let scrollView = ImageScrollView.ImageNSScrollView(frame: window.contentView?.bounds ?? .zero)
    scrollView.allowsMagnification = true
    scrollView.minMagnification = Constants.imageZoomScaleRange.lowerBound
    scrollView.maxMagnification = Constants.imageZoomScaleRange.upperBound
    scrollView.documentView = NSView(
      frame: NSRect(origin: .zero, size: NSSize(width: 1000, height: 500)),
    )
    scrollView.magnification = originalZoomScale
    window.contentView = scrollView
    coordinator.observe(scrollView)

    coordinator.handle(.fitToScreen)
    coordinator.handle(.fitToScreen)

    try await TestSupport.waitUntil {
      !coordinator.isFitToScreenToggleActive
        && window.frame.isApproximatelyEqual(to: originalWindowFrame)
        && scrollView.magnification.isApproximatelyEqual(to: originalZoomScale)
    }
  }
}

// MARK: - Image Loading

@MainActor
@Suite("Image Loading")
struct ImageLoadingTests {
  @Test func `image info loads sample metadata without image decode`() async throws {
    let url = TestSupport.sampleImageURL("sample_1280×853.png")

    let info = try await ImageLoader.shared.loadInfo(from: url)

    #expect(info.url == url)
    #expect(info.fileName == "sample_1280×853.png")
    #expect(info.pixelSize == IntSize(width: 1280, height: 853))
    #expect(info.DPI == IntSize(width: 72, height: 72))
    #expect(info.fileSize > 0)
  }

  @Test func `svg loaded image rasterizes to bitmap and uses view box size`() async throws {
    let url = TestSupport.sampleImageURL("sample_1280×853.svg")

    let imageInfo = try await ImageLoader.shared.loadInfo(from: url)
    let imageContainer = try await ImageLoader.shared.loadImage(from: url)
    let bitmapRep = try #require(imageContainer.nsImage.representations.first as? NSBitmapImageRep)

    #expect(imageInfo.pixelSize == IntSize(width: 1280, height: 853))
    #expect(imageContainer.pixelSize == NSSize(width: 1280, height: 853))
    #expect(imageContainer.nsImage.representations.count == 1)
    #expect(bitmapRep.pixelsWide == 1280)
    #expect(bitmapRep.pixelsHigh == 853)
  }

  @Test func `complex svg rasterizes to bitmap`() async throws {
    let url = URL.temporaryDirectory.appending(path: "imaxe-svg-with-paint-server.svg")
    let svg = """
    <svg width="100%" height="100%" viewBox="0 0 4267 4267" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="gradient"><stop offset="0" style="stop-color:#fff"/></linearGradient>
        <clipPath id="clip"><path d="M0 0h4267v4267h-4267z"/></clipPath>
      </defs>
      <g clip-path="url(#clip)">
        <path d="M0 0h4267v4267h-4267z" style="fill:url(#gradient);"/>
        <circle cx="2133.5" cy="2133.5" r="1200" style="fill:#3478f6;"/>
      </g>
    </svg>
    """
    try svg.write(to: url, atomically: true, encoding: .utf8)

    let imageInfo = try await ImageLoader.shared.loadInfo(from: url)
    let imageContainer = try await ImageLoader.shared.loadImage(from: url)
    let bitmapRep = try #require(imageContainer.nsImage.representations.first as? NSBitmapImageRep)

    #expect(imageInfo.pixelSize == IntSize(width: 4267, height: 4267))
    #expect(imageContainer.pixelSize == NSSize(width: 4267, height: 4267))
    #expect(imageContainer.nsImage.representations.count == 1)
    #expect(bitmapRep.pixelsWide == 4267)
    #expect(bitmapRep.pixelsHigh == 4267)
  }

  @Test func `image loader returns cached image container for same url`() async throws {
    let url = TestSupport.sampleImageURL("sample_1280×853.png")

    let firstImage = try await ImageLoader.shared.loadImage(from: url)
    let secondImage = try await ImageLoader.shared.loadImage(from: url)

    #expect(firstImage === secondImage)
  }

  @Test func `image loader reports missing files as file not found`() async throws {
    let url = URL.temporaryDirectory.appending(path: "imaxe-missing-image-\(UUID().uuidString).png")

    do {
      _ = try await ImageLoader.shared.loadImage(from: url)
      Issue.record("Expected loading a missing image to throw.")
    } catch let error as ImageLoadingError {
      if case let .fileNotFound(missingURL) = error {
        #expect(missingURL == url)
      } else {
        Issue.record("Expected fileNotFound, got \(error).")
      }
    }
  }

  @Test func `image loader cancellation does not poison later loads`() async throws {
    let url = TestSupport.sampleImageURL("sample_1280×853.png")
    let requestID = ImageLoader.LoadRequestID()
    let loadTask = Task {
      try await ImageLoader.shared.loadImage(from: url, requestID: requestID)
    }

    loadTask.cancel()
    await ImageLoader.shared.cancelLoads(for: requestID)
    _ = try? await loadTask.value

    let image = try await ImageLoader.shared.loadImage(from: url)

    #expect(image.pixelSize == NSSize(width: 1280, height: 853))
  }

  @Test func `image loader reloads changed file at same url`() async throws {
    let url = URL.temporaryDirectory
      .appending(path: "imaxe-changing-image-\(UUID().uuidString).png")

    try TestSupport.pngData(width: 10, height: 20).write(to: url)
    let firstImage = try await ImageLoader.shared.loadImage(from: url)
    let firstInfo = try await ImageLoader.shared.loadInfo(from: url)

    try TestSupport.pngData(width: 12, height: 24).write(to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: 2)],
      ofItemAtPath: url.filePath,
    )

    let secondImage = try await ImageLoader.shared.loadImage(from: url)
    let secondInfo = try await ImageLoader.shared.loadInfo(from: url)

    #expect(firstImage !== secondImage)
    #expect(firstImage.pixelSize == NSSize(width: 10, height: 20))
    #expect(firstInfo.pixelSize == IntSize(width: 10, height: 20))
    #expect(secondImage.pixelSize == NSSize(width: 12, height: 24))
    #expect(secondInfo.pixelSize == IntSize(width: 12, height: 24))
  }

  @Test func `thumbnail cache generates svg thumbnail`() throws {
    let url = TestSupport.sampleImageURL("sample_1280×853.svg")

    let thumbnailKey = try #require(ImageThumbnailCache.ensureThumbnail(for: url))
    let thumbnailURL = ImageThumbnailCache.thumbnailURL(for: thumbnailKey)
    let thumbnailImage = try #require(NSImage(contentsOf: thumbnailURL))
    let bitmapRep = try #require(thumbnailImage.representations.first as? NSBitmapImageRep)

    #expect(FileManager.default.fileExists(atPath: thumbnailURL.filePath))
    #expect(max(bitmapRep.pixelsWide, bitmapRep.pixelsHigh) <= ImageThumbnailCache.maxPixelSize)
    #expect(bitmapRep.pixelsWide > 0)
    #expect(bitmapRep.pixelsHigh > 0)
    let thumbnailAspectRatio = CGFloat(bitmapRep.pixelsWide) / CGFloat(bitmapRep.pixelsHigh)
    #expect(abs(thumbnailAspectRatio - 1280.0 / 853.0) < 0.02)
  }

  @Test func `thumbnail cache total size sums regular files`() throws {
    let testDirectory = URL.thumbnailCachesDirectory
      .appending(path: "test-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: testDirectory)
    }

    let initialSize = ImageThumbnailCache.totalCacheSizeInBytes()
    let firstFile = testDirectory.appending(path: "first.png")
    let nestedDirectory = testDirectory.appending(path: "nested", directoryHint: .isDirectory)
    let nestedFile = nestedDirectory.appending(path: "second.png")
    try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
    try Data(repeating: 1, count: 13).write(to: firstFile)
    try Data(repeating: 2, count: 29).write(to: nestedFile)

    #expect(ImageThumbnailCache.totalCacheSizeInBytes() == initialSize + 42)

    try FileManager.default.removeItem(at: testDirectory)
    #expect(ImageThumbnailCache.totalCacheSizeInBytes() == initialSize)
  }
}

// MARK: - Session and Navigation

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

// MARK: - Recent Images

@MainActor
@Suite("Recent Images")
struct RecentImagesTests {
  @Test func `recent images are updated sorted and cleared`() throws {
    try TestSupport.withRecentImagesCountLimit(AppSettings.Defaults.recentImagesCountLimit) {
      let container = try ModelContainer(
        for: RecentImage.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true),
      )
      let context = ModelContext(container)
      let firstURL = URL(fileURLWithPath: "/tmp/first.png")
      let secondURL = URL(fileURLWithPath: "/tmp/second.png")

      try RecentImagesStore.recordOpened(
        firstURL,
        in: context,
        openedAt: Date(timeIntervalSince1970: 1),
      )
      try RecentImagesStore.recordOpened(
        secondURL,
        in: context,
        openedAt: Date(timeIntervalSince1970: 2),
      )
      try RecentImagesStore.recordOpened(
        firstURL,
        in: context,
        openedAt: Date(timeIntervalSince1970: 3),
      )

      let descriptor = FetchDescriptor<RecentImage>(
        sortBy: [SortDescriptor(\.lastOpenedAt, order: .reverse)],
      )
      let recentImages = try context.fetch(descriptor)

      #expect(recentImages.compactMap(\.url).map(\.lastPathComponent) == [
        "first.png",
        "second.png",
      ])
      #expect(recentImages.first?.lastOpenedAt == Date(timeIntervalSince1970: 3))

      try RecentImagesStore.clear(in: context)

      #expect(try context.fetch(descriptor).isEmpty)
    }
  }

  @Test func `recent images use default count limit when preference is unset`() throws {
    try TestSupport.withRecentImagesCountLimit(nil) {
      let container = try ModelContainer(
        for: RecentImage.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true),
      )
      let context = ModelContext(container)

      try RecentImagesStore.recordOpened(
        URL(fileURLWithPath: "/tmp/first.png"),
        in: context,
        openedAt: Date(timeIntervalSince1970: 1),
      )
      try RecentImagesStore.recordOpened(
        URL(fileURLWithPath: "/tmp/second.png"),
        in: context,
        openedAt: Date(timeIntervalSince1970: 2),
      )

      let recentImages = try RecentImagesStore.fetchRecentImages(in: context)

      #expect(recentImages.map(\.fileName) == ["second.png", "first.png"])
    }
  }

  @Test func `recent images are trimmed to configured count limit`() throws {
    try TestSupport.withRecentImagesCountLimit(3) {
      let container = try ModelContainer(
        for: RecentImage.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true),
      )
      let context = ModelContext(container)

      try RecentImagesStore.recordOpened(
        URL(fileURLWithPath: "/tmp/first.png"),
        in: context,
        openedAt: Date(timeIntervalSince1970: 1),
      )
      try RecentImagesStore.recordOpened(
        URL(fileURLWithPath: "/tmp/second.png"),
        in: context,
        openedAt: Date(timeIntervalSince1970: 2),
      )
      try RecentImagesStore.recordOpened(
        URL(fileURLWithPath: "/tmp/third.png"),
        in: context,
        openedAt: Date(timeIntervalSince1970: 3),
      )

      UserDefaults.standard.set(2, forKey: AppSettings.Keys.recentImagesCountLimit.rawValue)

      let recentImages = try RecentImagesStore.fetchRecentImages(in: context)

      #expect(recentImages.map(\.fileName) == ["third.png", "second.png"])
    }
  }

  @Test func `recent images store file metadata and cleanup thumbnail cache`() throws {
    try TestSupport.withRecentImagesCountLimit(AppSettings.Defaults.recentImagesCountLimit) {
      let container = try ModelContainer(
        for: RecentImage.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true),
      )
      let context = ModelContext(container)
      let url = URL.temporaryDirectory
        .appending(path: "imaxe-thumbnail-cache-\(UUID().uuidString).png")
      try TestSupport.pngData(width: 80, height: 40).write(to: url)

      try RecentImagesStore.recordOpened(url, in: context)

      let recentDescriptor = FetchDescriptor<RecentImage>()
      let recent = try #require(context.fetch(recentDescriptor).first)
      let thumbnailKey = try #require(recent.thumbnailCacheKey)
      let thumbnailURL = ImageThumbnailCache.thumbnailURL(for: thumbnailKey)

      let resourceValues = try recent.url.resourceValues(forKeys: [
        .contentModificationDateKey,
        .fileSizeKey,
      ])
      #expect((resourceValues.fileSize ?? 0) > 0)
      #expect(resourceValues.contentModificationDate != nil)
      #expect(FileManager.default.fileExists(atPath: thumbnailURL.filePath))

      try RecentImagesStore.remove(path: url.filePath, in: context)
      #expect(!FileManager.default.fileExists(atPath: thumbnailURL.filePath))
    }
  }

  @Test func `missing recent images are pruned with thumbnail cache`() throws {
    try TestSupport.withRecentImagesCountLimit(AppSettings.Defaults.recentImagesCountLimit) {
      let container = try ModelContainer(
        for: RecentImage.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true),
      )
      let context = ModelContext(container)
      let existingURL = URL.temporaryDirectory
        .appending(path: "imaxe-existing-recent-\(UUID().uuidString).png")
      let missingURL = URL.temporaryDirectory
        .appending(path: "imaxe-pruned-recent-\(UUID().uuidString).png")
      defer {
        try? FileManager.default.removeItem(at: existingURL)
        try? FileManager.default.removeItem(at: missingURL)
      }

      try TestSupport.pngData(width: 80, height: 40).write(to: existingURL)
      try TestSupport.pngData(width: 80, height: 40).write(to: missingURL)
      try RecentImagesStore.recordOpened(
        existingURL,
        in: context,
        openedAt: Date(timeIntervalSince1970: 1),
      )
      try RecentImagesStore.recordOpened(
        missingURL,
        in: context,
        openedAt: Date(timeIntervalSince1970: 2),
      )

      var missingDescriptor = FetchDescriptor<RecentImage>(
        predicate: #Predicate<RecentImage> { recentImage in
          recentImage.path == missingURL.filePath
        },
      )
      missingDescriptor.fetchLimit = 1
      let missingRecent = try #require(context.fetch(missingDescriptor).first)
      let missingThumbnailKey = try #require(missingRecent.thumbnailCacheKey)
      let missingThumbnailURL = ImageThumbnailCache.thumbnailURL(for: missingThumbnailKey)
      try FileManager.default.removeItem(at: missingURL)

      let removedCount = try RecentImagesStore.removeMissingFiles(in: context)

      let recentImages = try RecentImagesStore.fetchRecentImages(in: context)
      #expect(removedCount == 1)
      #expect(recentImages.map(\.path) == [existingURL.filePath])
      #expect(!FileManager.default.fileExists(atPath: missingThumbnailURL.filePath))

      try RecentImagesStore.clear(in: context)
    }
  }

  @Test func `opening missing recent image removes recent item and thumbnail cache`() async throws {
    try await TestSupport.withRecentImagesCountLimit(AppSettings.Defaults.recentImagesCountLimit) {
      let container = try ModelContainer(
        for: RecentImage.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true),
      )
      let context = ModelContext(container)
      let url = URL.temporaryDirectory
        .appending(path: "imaxe-missing-recent-\(UUID().uuidString).png")
      try TestSupport.pngData(width: 80, height: 40).write(to: url)
      try RecentImagesStore.recordOpened(url, in: context)

      let descriptor = FetchDescriptor<RecentImage>()
      let recent = try #require(context.fetch(descriptor).first)
      let thumbnailKey = try #require(recent.thumbnailCacheKey)
      let thumbnailURL = ImageThumbnailCache.thumbnailURL(for: thumbnailKey)
      try FileManager.default.removeItem(at: url)

      let session = ImageSession()
      session.removeRecentImage = { path in
        try RecentImagesStore.remove(path: path, in: context)
      }
      session.openRecentImage(recent)

      for _ in 0 ..< 20 {
        if try context.fetch(descriptor).isEmpty {
          break
        }
        await Task.yield()
      }

      #expect(try context.fetch(descriptor).isEmpty)
      #expect(!FileManager.default.fileExists(atPath: thumbnailURL.filePath))
      #expect(session.alert?.title == "Recent Image Removed")
    }
  }

  @Test func `lowered recent images count limit removes trimmed thumbnail cache`() throws {
    try TestSupport.withRecentImagesCountLimit(3) {
      let container = try ModelContainer(
        for: RecentImage.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true),
      )
      let context = ModelContext(container)
      let firstURL = URL.temporaryDirectory
        .appending(path: "imaxe-trimmed-first-\(UUID().uuidString).png")
      let secondURL = URL.temporaryDirectory
        .appending(path: "imaxe-trimmed-second-\(UUID().uuidString).png")
      let thirdURL = URL.temporaryDirectory
        .appending(path: "imaxe-trimmed-third-\(UUID().uuidString).png")
      defer {
        try? FileManager.default.removeItem(at: firstURL)
        try? FileManager.default.removeItem(at: secondURL)
        try? FileManager.default.removeItem(at: thirdURL)
        try? RecentImagesStore.clear(in: context)
      }

      try TestSupport.pngData(width: 80, height: 40).write(to: firstURL)
      try TestSupport.pngData(width: 80, height: 40).write(to: secondURL)
      try TestSupport.pngData(width: 80, height: 40).write(to: thirdURL)
      try RecentImagesStore.recordOpened(
        firstURL,
        in: context,
        openedAt: Date(timeIntervalSince1970: 1),
      )
      try RecentImagesStore.recordOpened(
        secondURL,
        in: context,
        openedAt: Date(timeIntervalSince1970: 2),
      )
      try RecentImagesStore.recordOpened(
        thirdURL,
        in: context,
        openedAt: Date(timeIntervalSince1970: 3),
      )

      var firstDescriptor = FetchDescriptor<RecentImage>(
        predicate: #Predicate<RecentImage> { recentImage in
          recentImage.path == firstURL.filePath
        },
      )
      firstDescriptor.fetchLimit = 1
      let firstRecent = try #require(context.fetch(firstDescriptor).first)
      let firstThumbnailKey = try #require(firstRecent.thumbnailCacheKey)
      let firstThumbnailURL = ImageThumbnailCache.thumbnailURL(for: firstThumbnailKey)
      #expect(FileManager.default.fileExists(atPath: firstThumbnailURL.filePath))

      UserDefaults.standard.set(2, forKey: AppSettings.Keys.recentImagesCountLimit.rawValue)

      let recentImages = try RecentImagesStore.fetchRecentImages(in: context)

      #expect(recentImages.map(\.path) == [thirdURL.filePath, secondURL.filePath])
      #expect(!FileManager.default.fileExists(atPath: firstThumbnailURL.filePath))
    }
  }
}

// MARK: - Shared UI

@MainActor
@Suite("Shared UI")
struct SharedUITests {
  @Test func `color hex serializes grayscale colors as rgba`() {
    let color = Color(.sRGB, white: 0.5, opacity: 0.25)

    #expect(color.hex == "#80808040")
  }

  @Test func `color hex preserves rgb and alpha components`() {
    let color = Color(hex: "#33669980")

    #expect(color.hex == "#33669980")
  }

  @Test func `image collection single mode initializers compile`() {
    let items = [CollectionInitializerTestItem(id: 1)]

    _ = ImageCollectionView(
      items,
      listRow: { item, _ in
        Text("Row \(item.id)")
      },
    )

    _ = ImageCollectionView(
      items,
      gridItem: { item, _ in
        Text("Grid \(item.id)")
      },
    )

    _ = ImageCollectionView(
      items,
      listRow: { item, _ in
        Text("Row \(item.id)")
      },
      contextMenu: { _ in
        Button("Inspect") {}
      },
    )

    _ = ImageCollectionView(
      items,
      gridItem: { item, _ in
        Text("Grid \(item.id)")
      },
      contextMenu: { _ in
        Button("Inspect") {}
      },
    )
  }

  private struct CollectionInitializerTestItem: Identifiable {
    let id: Int
  }
}

// MARK: - Test Support

@MainActor
private enum TestSupport {
  static func sampleImageURL(_ fileName: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "Images/\(fileName)")
  }

  static func bitmapImage(width: Int = 10, height: Int = 20) -> NSImage {
    let representation = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: width,
      pixelsHigh: height,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0,
    )

    let image = NSImage(size: NSSize(width: width, height: height))
    if let representation {
      image.addRepresentation(representation)
    }
    return image
  }

  static func pngData(width: Int, height: Int) throws -> Data {
    let representation = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0,
      ),
    )

    let rect = NSRect(x: 0, y: 0, width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    NSColor.systemBlue.setFill()
    rect.fill()
    NSGraphicsContext.restoreGraphicsState()

    return try #require(representation.representation(using: .png, properties: [:]))
  }

  static func withRecentImagesCountLimit<T>(
    _ limit: Int?,
    operation: () throws -> T,
  ) throws -> T {
    let key = AppSettings.Keys.recentImagesCountLimit.rawValue
    let previousValue = UserDefaults.standard.object(forKey: key)
    defer {
      restoreUserDefault(previousValue, forKey: key)
    }

    setRecentImagesCountLimit(limit, forKey: key)
    return try operation()
  }

  static func withRecentImagesCountLimit<T>(
    _ limit: Int?,
    operation: () async throws -> T,
  ) async throws -> T {
    let key = AppSettings.Keys.recentImagesCountLimit.rawValue
    let previousValue = UserDefaults.standard.object(forKey: key)
    defer {
      restoreUserDefault(previousValue, forKey: key)
    }

    setRecentImagesCountLimit(limit, forKey: key)
    return try await operation()
  }

  static func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping () -> Bool,
  ) async throws {
    let start = ContinuousClock.now

    while !condition() {
      if start.duration(to: .now) > timeout {
        Issue.record("Timed out waiting for condition.")
        return
      }
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  private static func setRecentImagesCountLimit(_ limit: Int?, forKey key: String) {
    if let limit {
      UserDefaults.standard.set(limit, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  private static func restoreUserDefault(_ value: Any?, forKey key: String) {
    if let value {
      UserDefaults.standard.set(value, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }
}

private extension CGFloat {
  func isApproximatelyEqual(to other: CGFloat) -> Bool {
    abs(self - other) < Constants.zoomScaleUpdateTolerance
  }
}

private extension NSRect {
  func isApproximatelyEqual(to other: NSRect) -> Bool {
    origin.isApproximatelyEqual(to: other.origin)
      && size.isApproximatelyEqual(to: other.size)
  }
}

private extension NSPoint {
  func isApproximatelyEqual(to other: NSPoint) -> Bool {
    abs(x - other.x) < 1.0 && abs(y - other.y) < 1.0
  }
}
