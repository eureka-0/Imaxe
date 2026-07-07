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

@MainActor
struct ImaxeTests {
  @Test func `bitmap image container uses pixel size`() {
    let image = bitmapImage()
    let url = URL(fileURLWithPath: "/tmp/example.png")

    let imageContainer = ImageContainer(url: url, nsImage: image)

    #expect(imageContainer.pixelSize == NSSize(width: 10, height: 20))
    #expect(imageContainer.nsImage.size == NSSize(width: 10, height: 20))
  }

  @Test func `canvas occupies image pixel size in backing pixels`() {
    let image = bitmapImage()
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

    // At 100% the canvas must occupy exactly the image's pixel size in backing pixels, regardless
    // of the screen's backing scale factor.
    let backingSize = canvas.convertToBacking(canvas.bounds.size)
    #expect(backingSize.isApproximatelyEqual(to: imageContainer.pixelSize))
  }

  @Test func `image info loads sample metadata without image decode`() async throws {
    let url = sampleImageURL("sample_1280×853.png")

    let info = try await ImageLoader.shared.loadInfo(from: url)

    #expect(info.url == url)
    #expect(info.fileName == "sample_1280×853.png")
    #expect(info.pixelSize == IntSize(width: 1280, height: 853))
    #expect(info.DPI == IntSize(width: 72, height: 72))
    #expect(info.fileSize > 0)
  }

  @Test func `svg loaded image rasterizes to bitmap and uses view box size`() async throws {
    let url = sampleImageURL("sample_1280×853.svg")

    let imageInfo = try await ImageLoader.shared.loadInfo(from: url)
    let imageContainer = try await ImageLoader.shared.loadImage(from: url)
    let bitmapRep = try #require(imageContainer.nsImage.representations.first as? NSBitmapImageRep)

    #expect(imageInfo.pixelSize == IntSize(width: 1280, height: 853))
    #expect(imageContainer.pixelSize == NSSize(width: 1280, height: 853))
    #expect(imageContainer.nsImage.representations.count == 1)
    #expect(bitmapRep.pixelsWide == 1280)
    #expect(bitmapRep.pixelsHigh == 853)
  }

  @Test func `complex SVG rasterizes to bitmap`() async throws {
    let url = URL.temporaryDirectory
      .appending(path: "imaxe-svg-with-paint-server.svg")
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
    let url = sampleImageURL("sample_1280×853.png")

    let firstImage = try await ImageLoader.shared.loadImage(from: url)
    let secondImage = try await ImageLoader.shared.loadImage(from: url)

    #expect(firstImage === secondImage)
  }

  @Test func `image loader cancellation does not poison later loads`() async throws {
    let url = sampleImageURL("sample_1280×853.png")
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

    try pngData(width: 10, height: 20).write(to: url)
    let firstImage = try await ImageLoader.shared.loadImage(from: url)
    let firstInfo = try await ImageLoader.shared.loadInfo(from: url)

    try pngData(width: 12, height: 24).write(to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: 2)],
      ofItemAtPath: url.path,
    )

    let secondImage = try await ImageLoader.shared.loadImage(from: url)
    let secondInfo = try await ImageLoader.shared.loadInfo(from: url)

    #expect(firstImage !== secondImage)
    #expect(firstImage.pixelSize == NSSize(width: 10, height: 20))
    #expect(firstInfo.pixelSize == IntSize(width: 10, height: 20))
    #expect(secondImage.pixelSize == NSSize(width: 12, height: 24))
    #expect(secondInfo.pixelSize == IntSize(width: 12, height: 24))
  }

  @Test func `file change reload keeps current image while loading`() throws {
    let url = URL.temporaryDirectory
      .appending(path: "imaxe-session-reload-\(UUID().uuidString).png")
    try pngData(width: 10, height: 20).write(to: url)
    let initialImage = ImageContainer(url: url, nsImage: bitmapImage())
    let session = ImageSession(imageContainer: initialImage)

    session.loadImage(from: url, preservingViewportOnReload: true)

    #expect(session.currentImage === initialImage)
    #expect(!session.shouldApplyLoadedImageWindowSize)
  }

  @Test func `always fit to window still applies after viewport-preserving image change`() {
    var reportedZoomScale: CGFloat?
    let coordinator = ImageScrollView.Coordinator(
      onZoomScaleChange: { reportedZoomScale = $0 },
      onAlwaysFitToWindowChange: { _ in },
    )
    let scrollView = NSScrollView(
      frame: NSRect(origin: .zero, size: NSSize(width: 100, height: 100)),
    )
    let imageView = NSView(frame: NSRect(
      origin: .zero,
      size: NSSize(width: 200, height: 100),
    ))
    let imageContainer = ImageContainer(
      url: URL(fileURLWithPath: "/tmp/example.png"),
      nsImage: bitmapImage(width: 200, height: 100),
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

  @Test func `folder navigator starts with current image and can load directory asynchronously`(
  ) async throws {
    let directory = URL.temporaryDirectory
      .appending(path: "imaxe-folder-navigation-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let firstURL = directory.appending(path: "b.png")
    let secondURL = directory.appending(path: "a.png")
    try pngData(width: 10, height: 20).write(to: firstURL)
    try pngData(width: 12, height: 24).write(to: secondURL)

    let navigator = FolderNavigator(for: firstURL, enableLoopBrowsing: false)
    let imageURLs = try #require(await FolderNavigator.imageURLs(for: firstURL))

    #expect(navigator.imageURLs == [firstURL])
    #expect(imageURLs.map(\.lastPathComponent) == ["a.png", "b.png"])
  }

  @Test func `image file watcher reports stable file change`() async throws {
    let url = URL.temporaryDirectory
      .appending(path: "imaxe-watched-image-\(UUID().uuidString).png")
    try pngData(width: 10, height: 20).write(to: url)
    let changedImageData = try pngData(width: 12, height: 24)

    var watcher: ImageFileWatcher?
    let didChange = await withCheckedContinuation { continuation in
      watcher = ImageFileWatcher(url: url) {
        continuation.resume(returning: true)
      }

      DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(100)) {
        try? changedImageData.write(to: url)
        try? FileManager.default.setAttributes(
          [.modificationDate: Date(timeIntervalSinceNow: 2)],
          ofItemAtPath: url.path,
        )
      }
    }

    #expect(didChange)
    _ = watcher
  }

  @Test func `recent images are updated sorted and cleared`() throws {
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

    #expect(recentImages.compactMap(\.url).map(\.lastPathComponent) == ["first.png", "second.png"])
    #expect(recentImages.first?.lastOpenedAt == Date(timeIntervalSince1970: 3))

    try RecentImagesStore.clear(in: context)

    #expect(try context.fetch(descriptor).isEmpty)
  }

  @Test func `recent images store file metadata and cleanup thumbnail cache`() throws {
    let container = try ModelContainer(
      for: RecentImage.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true),
    )
    let context = ModelContext(container)
    let url = URL.temporaryDirectory
      .appending(path: "imaxe-thumbnail-cache-\(UUID().uuidString).png")
    try pngData(width: 80, height: 40).write(to: url)

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
    #expect(FileManager.default.fileExists(atPath: thumbnailURL.path))

    try RecentImagesStore.remove(path: url.filePath, in: context)
    #expect(!FileManager.default.fileExists(atPath: thumbnailURL.path))
  }

  @Test func `thumbnail cache total size sums regular files`() throws {
    let testDirectory = ImageThumbnailCache.cacheDirectory
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

  @Test func `color hex serializes grayscale colors as rgba`() {
    let color = Color(.sRGB, white: 0.5, opacity: 0.25)

    #expect(color.hex == "#80808040")
  }

  @Test func `color hex preserves rgb and alpha components`() {
    let color = Color(hex: "#33669980")

    #expect(color.hex == "#33669980")
  }

  private func sampleImageURL(_ fileName: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "Images/\(fileName)")
  }

  private func bitmapImage(width: Int = 10, height: Int = 20) -> NSImage {
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

  private func pngData(width: Int, height: Int) throws -> Data {
    let representation = try #require(NSBitmapImageRep(
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
    ))

    let rect = NSRect(x: 0, y: 0, width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    NSColor.systemBlue.setFill()
    rect.fill()
    NSGraphicsContext.restoreGraphicsState()

    return try #require(representation.representation(using: .png, properties: [:]))
  }
}

private extension CGFloat {
  func isApproximatelyEqual(to other: CGFloat) -> Bool {
    abs(self - other) < Constants.zoomScaleUpdateTolerance
  }
}
