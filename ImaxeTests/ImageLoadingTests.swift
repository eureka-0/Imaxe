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
  private let loader = ImageLoader.shared

  private nonisolated static let registeredFormatSamples = [
    "sample_1280×853.bmp",
    "sample_384×512.gif",
    "sample.heic",
    "sample.heif",
    "sample_1280×853.ico",
    "sample_1280×853.jpeg",
    "sample_1280×853.png",
    "sample_1280×853.tiff",
    "sample.webp",
    "sample_1280×853.svg",
  ]

  @Test func `image metadata loads sample properties without image decode`() async throws {
    let url = TestSupport.sampleImageURL("sample_1280×853.png")

    let metadata = try await loader.loadMetadata(from: url)

    #expect(metadata.url == url)
    #expect(metadata.fileName == "sample_1280×853.png")
    #expect(metadata.rawPixelSize == IntSize(width: 1280, height: 853))
    #expect(metadata.displayPixelSize == IntSize(width: 1280, height: 853))
    #expect(metadata.DPI == IntSize(width: 72, height: 72))
    #expect(metadata.fileSize > 0)
    #expect(metadata.imageCount == 1)
    #expect(metadata.primaryImageIndex == 0)
    #expect(metadata.orientation == .up)
    #expect(metadata.estimatedFullFrameBytes == 1280 * 853 * 4)
    #expect(!metadata.isAnimated)
    #expect(!metadata.isMultiPage)
    #expect(!metadata.isSVG)
  }

  @Test(arguments: registeredFormatSamples)
  func `registered formats load metadata and primary image`(_ sampleName: String) async throws {
    let url = TestSupport.sampleImageURL(sampleName)

    let metadata = try await loader.loadMetadata(from: url)
    let document = try await loader.loadDocument(from: url)

    #expect(metadata.url == url)
    #expect(metadata.displayPixelSize.width > 0)
    #expect(metadata.displayPixelSize.height > 0)
    #expect(document.pixelSize.width > 0)
    #expect(document.pixelSize.height > 0)
    #expect(document.metadata == metadata)
  }

  @Test(arguments: registeredFormatSamples)
  func `registered formats generate thumbnails`(_ sampleName: String) async throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-format-thumbnail")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = TestSupport.sampleImageURL(sampleName)

    let key = try #require(await ImageThumbnailCache.ensureThumbnail(
      for: url,
      directoryURL: directory,
    ))

    #expect(ImageThumbnailCache.isValidThumbnail(for: key, directoryURL: directory))
  }

  @Test(arguments: registeredFormatSamples)
  func `registered formats report corrupt content`(_ sampleName: String) async throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-format-corrupt")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: sampleName)
    try Data("not an image".utf8).write(to: url)

    await expectCorruptImage {
      _ = try await loader.loadMetadata(from: url)
    }
    await expectCorruptImage {
      _ = try await loader.loadDocument(from: url)
    }
  }

  @Test(arguments: registeredFormatSamples)
  func `registered formats report permission failures`(_ sampleName: String) async throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-format-permission")
    defer { try? FileManager.default.removeItem(at: directory) }
    let sourceURL = TestSupport.sampleImageURL(sampleName)
    let protectedURL = directory.appending(path: sampleName)
    try FileManager.default.copyItem(at: sourceURL, to: protectedURL)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: protectedURL.filePath,
      )
    }
    try FileManager.default.setAttributes(
      [.posixPermissions: 0],
      ofItemAtPath: protectedURL.filePath,
    )

    await expectPermissionDenied {
      _ = try await loader.loadMetadata(from: protectedURL)
    }
    await expectPermissionDenied {
      _ = try await loader.loadDocument(from: protectedURL)
    }
  }

  @Test func `svg loaded image rasterizes to bitmap and uses view box size`() async throws {
    let url = TestSupport.sampleImageURL("sample_1280×853.svg")

    let metadata = try await loader.loadMetadata(from: url)
    let document = try await loader.loadDocument(from: url)
    let bitmapRep = try #require(document.nsImage.representations.first as? NSBitmapImageRep)

    #expect(metadata.displayPixelSize == IntSize(width: 1280, height: 853))
    #expect(metadata.isSVG)
    #expect(document.pixelSize == NSSize(width: 1280, height: 853))
    #expect(document.nsImage.representations.count == 1)
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

    let metadata = try await loader.loadMetadata(from: url)
    let document = try await loader.loadDocument(from: url)
    let bitmapRep = try #require(document.nsImage.representations.first as? NSBitmapImageRep)

    #expect(metadata.displayPixelSize == IntSize(width: 4267, height: 4267))
    #expect(document.pixelSize == NSSize(width: 4267, height: 4267))
    #expect(document.nsImage.representations.count == 1)
    #expect(bitmapRep.pixelsWide == 4267)
    #expect(bitmapRep.pixelsHigh == 4267)
  }

  @Test func `svg without explicit dimensions uses the image fallback size`() async throws {
    let url = URL.temporaryDirectory
      .appending(path: "imaxe-dimensionless-\(UUID().uuidString).svg")
    defer { try? FileManager.default.removeItem(at: url) }
    try "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"10\" height=\"20\"/></svg>"
      .write(to: url, atomically: true, encoding: .utf8)

    let document = try await loader.loadDocument(from: url)

    #expect(document.metadata.isSVG)
    #expect(document.metadata.displayPixelSize.isValid)
    #expect(document.pixelSize.width > 0)
    #expect(document.pixelSize.height > 0)
  }

  @Test func `image loader returns cached document for same url`() async throws {
    let url = TestSupport.sampleImageURL("sample_1280×853.png")

    let firstDocument = try await loader.loadDocument(from: url)
    let secondDocument = try await loader.loadDocument(from: url)

    #expect(firstDocument.id == secondDocument.id)
  }

  @Test func `image loader reports missing files as file not found`() async throws {
    let url = URL.temporaryDirectory.appending(path: "imaxe-missing-image-\(UUID().uuidString).png")

    do {
      _ = try await loader.loadDocument(from: url)
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
      _ = try await loader.loadDocument(from: url)
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
    #expect(ImageLoader.exceedsImageSizeLimit(NSSize(width: 16385, height: 1)))
    #expect(ImageLoader.exceedsImageSizeLimit(NSSize(width: 16385, height: 16384)))
    #expect(!ImageLoader.exceedsImageSizeLimit(NSSize(width: 16384, height: 16384)))
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
      _ = try await loader.loadDocument(from: invalidURL)
    }
    await #expect(throws: ImageLoadingError.self) {
      _ = try await loader.loadDocument(from: oversizedURL)
    }
  }

  @Test func `image loader cancellation does not poison later loads`() async throws {
    let url = TestSupport.sampleImageURL("sample_1280×853.png")
    let requestID = ImageLoader.LoadRequestID()
    let loadTask = Task {
      try await loader.loadDocument(from: url, requestID: requestID)
    }

    loadTask.cancel()
    await loader.cancelLoads(for: requestID)
    _ = try? await loadTask.value

    let document = try await loader.loadDocument(from: url)

    #expect(document.pixelSize == NSSize(width: 1280, height: 853))
  }

  @Test func `image loader reloads changed file at same url`() async throws {
    let url = URL.temporaryDirectory
      .appending(path: "imaxe-changing-image-\(UUID().uuidString).png")

    try TestSupport.pngData(width: 10, height: 20).write(to: url)
    let firstDocument = try await loader.loadDocument(from: url)
    let firstMetadata = try await loader.loadMetadata(from: url)

    try TestSupport.pngData(width: 12, height: 24).write(to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: 2)],
      ofItemAtPath: url.filePath,
    )

    let secondDocument = try await loader.loadDocument(from: url)
    let secondMetadata = try await loader.loadMetadata(from: url)

    #expect(firstDocument.id != secondDocument.id)
    #expect(firstDocument.pixelSize == NSSize(width: 10, height: 20))
    #expect(firstMetadata.displayPixelSize == IntSize(width: 10, height: 20))
    #expect(secondDocument.pixelSize == NSSize(width: 12, height: 24))
    #expect(secondMetadata.displayPixelSize == IntSize(width: 12, height: 24))
  }

  @Test func `thumbnail cache generates svg thumbnail`() async throws {
    let url = TestSupport.sampleImageURL("sample_1280×853.svg")
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-svg-thumbnail")
    defer { try? FileManager.default.removeItem(at: directory) }

    let thumbnailKey = try #require(await ImageThumbnailCache.ensureThumbnail(
      for: url,
      directoryURL: directory,
    ))
    let thumbnailURL = ImageThumbnailCache.thumbnailURL(
      for: thumbnailKey,
      directoryURL: directory,
    )
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
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-corrupt-thumbnail")
    defer { try? FileManager.default.removeItem(at: directory) }
    let key = try #require(ImageThumbnailCache.cacheKey(for: url))
    let cacheURL = ImageThumbnailCache.thumbnailURL(for: key, directoryURL: directory)
    try FileManager.default.ensureExists(for: cacheURL.deletingLastPathComponent())
    try Data("corrupt".utf8).write(to: cacheURL, options: .atomic)

    let regeneratedKey = await ImageThumbnailCache.ensureThumbnail(
      for: url,
      directoryURL: directory,
    )

    #expect(regeneratedKey == key)
    #expect(ImageThumbnailCache.isValidThumbnail(for: key, directoryURL: directory))
  }

  @Test func `thumbnail cache total size sums regular files`() throws {
    let testDirectory = try TestSupport.temporaryDirectory(prefix: "imaxe-thumbnail-size")
    defer {
      try? FileManager.default.removeItem(at: testDirectory)
    }

    let initialSize = ImageThumbnailCache.totalCacheSizeInBytes(directoryURL: testDirectory)
    let firstFile = testDirectory.appending(path: "first.png")
    let nestedDirectory = testDirectory.appending(path: "nested", directoryHint: .isDirectory)
    let nestedFile = nestedDirectory.appending(path: "second.png")
    try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
    try Data(repeating: 1, count: 13).write(to: firstFile)
    try Data(repeating: 2, count: 29).write(to: nestedFile)

    #expect(
      ImageThumbnailCache.totalCacheSizeInBytes(directoryURL: testDirectory) == initialSize + 42,
    )

    try FileManager.default.removeItem(at: testDirectory)
    #expect(ImageThumbnailCache.totalCacheSizeInBytes(directoryURL: testDirectory) == 0)
  }

  private func expectPermissionDenied(_ operation: () async throws -> Void) async {
    do {
      try await operation()
      Issue.record("Expected a permission denied error.")
    } catch let error as ImageLoadingError {
      if case .permissionDenied = error {
        return
      }
      Issue.record("Expected permissionDenied, got \(error).")
    } catch {
      Issue.record("Expected ImageLoadingError, got \(error).")
    }
  }

  private func expectCorruptImage(_ operation: () async throws -> Void) async {
    do {
      try await operation()
      Issue.record("Expected a corrupt image error.")
    } catch let error as ImageLoadingError {
      if case .corruptImage = error {
        return
      }
      Issue.record("Expected corruptImage, got \(error).")
    } catch {
      Issue.record("Expected ImageLoadingError, got \(error).")
    }
  }
}
