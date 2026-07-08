//
//  ImageThumbnail.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/3.
//

import CryptoKit
import Foundation
import ImageIO
import QuickLookThumbnailing
import SwiftData
import Synchronization
import UniformTypeIdentifiers

enum LibraryThumbnailReferences {
  static func removeThumbnailsIfUnused(
    _ keys: Set<String>,
    in modelContext: ModelContext,
  ) throws {
    for key in keys {
      try removeThumbnailIfUnused(key, in: modelContext)
    }
  }

  static func removeThumbnailIfUnused(
    _ key: String,
    in modelContext: ModelContext,
  ) throws {
    guard try !isThumbnailReferenced(key, in: modelContext) else { return }

    try ImageThumbnailCache.removeThumbnail(for: key)
  }

  private static func isThumbnailReferenced(
    _ key: String,
    in modelContext: ModelContext,
  ) throws -> Bool {
    var recentDescriptor = FetchDescriptor<RecentImage>(
      predicate: #Predicate<RecentImage> { recentImage in
        recentImage.thumbnailCacheKey == key
      },
    )
    recentDescriptor.fetchLimit = 1
    if try !modelContext.fetch(recentDescriptor).isEmpty {
      return true
    }

    return false
  }
}

nonisolated enum ImageThumbnailCache {
  static let maxPixelSize = 320

  private static let cacheVersion = "v1"

  /// Ensures that a thumbnail exists for the given image URL. If a thumbnail already exists in the
  /// cache, it returns the cache key. If not, it generates a new thumbnail, saves it to the cache,
  /// and returns the new cache key. Returns `nil` if the thumbnail cannot be created.
  static func ensureThumbnail(for url: URL) -> String? {
    let sourceURL = url.freshFileURL
    guard sourceURL.isFileURL, !sourceURL.isDirectory,
          ImageLoader.isSupportedImage(sourceURL)
    else {
      return nil
    }

    let key = thumbnailCacheKey(for: sourceURL)
    let outputURL = thumbnailURL(for: key)
    if outputURL.fileExists {
      return key
    }

    do {
      try writeThumbnail(from: sourceURL, to: outputURL)
      return key
    } catch {
      try? FileManager.default.removeItem(at: outputURL)
      return nil
    }
  }

  static func thumbnailURL(for key: String) -> URL {
    URL.thumbnailCachesDirectory.appendingPathComponent("\(key).png", isDirectory: false)
  }

  static func removeThumbnail(for key: String) throws {
    let url = thumbnailURL(for: key)
    if url.fileExists {
      try FileManager.default.removeItem(at: url)
    }
  }

  static func totalCacheSizeInBytes() -> Int64 {
    guard let fileEnumerator = FileManager.default.enumerator(
      at: URL.thumbnailCachesDirectory,
      includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
    ) else {
      return 0
    }

    var totalSize = Int64(0)
    for case let fileURL as URL in fileEnumerator {
      guard let resourceValues = try? fileURL.resourceValues(forKeys: [
        .fileSizeKey,
        .isRegularFileKey,
      ]),
        resourceValues.isRegularFile == true
      else { continue }

      totalSize += Int64(resourceValues.fileSize ?? 0)
    }
    return totalSize
  }

  private static func thumbnailCacheKey(for url: URL) -> String {
    let resourceValues = try? url.freshResourceValues(forKeys: [
      .contentModificationDateKey,
      .fileSizeKey,
    ])
    let modifiedAt = resourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0
    let fileSize = resourceValues?.fileSize ?? 0
    let source = [
      cacheVersion,
      url.filePath,
      "\(fileSize)",
      "\(modifiedAt)",
      "\(maxPixelSize)",
    ].joined(separator: "|")

    let digest = SHA256.hash(data: Data(source.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private static func writeThumbnail(from sourceURL: URL, to outputURL: URL) throws {
    if sourceURL.utType == .svg {
      try writeQuickLookThumbnail(from: sourceURL, to: outputURL)
      return
    }

    try writeImageIOThumbnail(from: sourceURL, to: outputURL)
  }

  private static func writeImageIOThumbnail(from sourceURL: URL, to outputURL: URL) throws {
    let sourceOptions = [
      kCGImageSourceShouldCache: false,
    ] as CFDictionary
    guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, sourceOptions) else {
      throw ThumbnailCacheError.failedToCreateImageSource
    }

    let thumbnailOptions = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
      kCGImageSourceShouldCacheImmediately: false,
    ] as CFDictionary
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions)
    else {
      throw ThumbnailCacheError.failedToCreateThumbnail
    }

    guard let destination = CGImageDestinationCreateWithURL(
      outputURL as CFURL,
      UTType.png.identifier as CFString,
      1,
      nil,
    ) else {
      throw ThumbnailCacheError.failedToCreateDestination
    }

    CGImageDestinationAddImage(destination, thumbnail, nil)
    if !CGImageDestinationFinalize(destination) {
      throw ThumbnailCacheError.failedToWriteThumbnail
    }
  }

  private static func writeQuickLookThumbnail(from sourceURL: URL, to outputURL: URL) throws {
    let request = QLThumbnailGenerator.Request(
      fileAt: sourceURL,
      size: CGSize(width: maxPixelSize, height: maxPixelSize),
      scale: 1,
      representationTypes: .thumbnail,
    )
    request.iconMode = false
    request.contentType = .svg

    let generationError = Mutex<Error?>(nil)
    let semaphore = DispatchSemaphore(value: 0)
    QLThumbnailGenerator.shared.saveBestRepresentation(
      for: request,
      to: outputURL,
      as: .png,
    ) { error in
      generationError.withLock {
        $0 = error
      }
      semaphore.signal()
    }

    if semaphore.wait(timeout: .now() + .seconds(10)) == .timedOut {
      QLThumbnailGenerator.shared.cancel(request)
      throw ThumbnailCacheError.quickLookGenerationTimedOut
    }

    if let error = generationError.withLock({ $0 }) {
      throw error
    }

    guard outputURL.fileExists else {
      throw ThumbnailCacheError.failedToWriteThumbnail
    }
  }

  private enum ThumbnailCacheError: Error {
    case failedToCreateImageSource
    case failedToCreateThumbnail
    case failedToCreateDestination
    case failedToWriteThumbnail
    case quickLookGenerationTimedOut
  }
}
