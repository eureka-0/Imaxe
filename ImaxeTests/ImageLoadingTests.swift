//
//  ImageLoadingTests.swift
//  ImaxeTests
//
//  Created by lxlong on 2026/6/14.
//

import AppKit
@testable import Imaxe
import SwiftUI
import Testing

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

  @Test func `image loader recognizes ImageIO content without a file extension`() throws {
    let url = URL.temporaryDirectory.appending(path: "imaxe-image-(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    try TestSupport.pngData(width: 10, height: 20).write(to: url)

    #expect(ImageLoader.isSupportedImage(url))
  }

  @Test func `image loader reports corrupt supported content`() async throws {
    let url = URL.temporaryDirectory
      .appending(path: "imaxe-corrupt-image-(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("not an image".utf8).write(to: url)

    do {
      _ = try await ImageLoader.shared.loadImage(from: url)
      Issue.record("Expected corrupt image content to throw.")
    } catch let error as ImageLoadingError {
      if case let .corruptImage(corruptURL) = error {
        #expect(corruptURL == url)
      } else {
        Issue.record("Expected corruptImage, got (error).")
      }
    }
  }

  @Test func `image loader enforces pixel dimension and count limits`() {
    #expect(ImageLoader.exceedsImageSizeLimit(NSSize(width: 32769, height: 1)))
    #expect(ImageLoader.exceedsImageSizeLimit(NSSize(width: 10001, height: 10001)))
    #expect(!ImageLoader.exceedsImageSizeLimit(NSSize(width: 10000, height: 10000)))
  }

  @Test func `svg loader rejects invalid and oversized dimensions`() async throws {
    let invalidURL = URL.temporaryDirectory
      .appending(path: "imaxe-invalid-dimensions-\(UUID().uuidString).svg")
    let oversizedURL = URL.temporaryDirectory
      .appending(path: "imaxe-oversized-dimensions-\(UUID().uuidString).svg")
    defer {
      try? FileManager.default.removeItem(at: invalidURL)
      try? FileManager.default.removeItem(at: oversizedURL)
    }
    try "<svg viewBox=\"0 0 -1 20\" xmlns=\"http://www.w3.org/2000/svg\"/>"
      .write(to: invalidURL, atomically: true, encoding: .utf8)
    try "<svg viewBox=\"0 0 50000 50000\" xmlns=\"http://www.w3.org/2000/svg\"/>"
      .write(to: oversizedURL, atomically: true, encoding: .utf8)

    await #expect(throws: ImageLoadingError.self) {
      _ = try await ImageLoader.shared.loadImage(from: invalidURL)
    }
    await #expect(throws: ImageLoadingError.self) {
      _ = try await ImageLoader.shared.loadImage(from: oversizedURL)
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

  @Test func `thumbnail cache generates svg thumbnail`() async throws {
    let url = TestSupport.sampleImageURL("sample_1280×853.svg")

    let thumbnailKey = try #require(await ImageThumbnailCache.ensureThumbnail(for: url))
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

  @Test func `thumbnail cache replaces corrupt cache entry`() async throws {
    let url = TestSupport.sampleImageURL("sample_1280×853.png")
    let key = try #require(ImageThumbnailCache.cacheKey(for: url))
    let cacheURL = ImageThumbnailCache.thumbnailURL(for: key)
    try FileManager.default.ensureExists(for: cacheURL.deletingLastPathComponent())
    try Data("corrupt".utf8).write(to: cacheURL, options: .atomic)

    let regeneratedKey = await ImageThumbnailCache.ensureThumbnail(for: url)

    #expect(regeneratedKey == key)
    #expect(ImageThumbnailCache.isValidThumbnail(for: key))
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
