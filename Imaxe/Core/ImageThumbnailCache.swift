//
//  ImageThumbnailCache.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/3.
//

import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ImageThumbnailCache {
  static let maxPixelSize = 320

  private static let cacheVersion = "v1"

  static var cacheDirectory: URL {
    let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

    return baseURL
      .appendingPathComponent("com.imaxe.Imaxe", isDirectory: true)
      .appendingPathComponent("Thumbnails", isDirectory: true)
  }

  static func ensureThumbnail(for snapshot: LibraryFileSnapshot) -> String? {
    guard snapshot.isFileURL,
          !snapshot.isDirectory,
          ImageLoader.isSupportedImage(snapshot.url)
    else { return nil }

    let key = thumbnailCacheKey(for: snapshot)
    let outputURL = thumbnailURL(for: key)
    if FileManager.default.fileExists(atPath: outputURL.path) {
      return key
    }

    do {
      try FileManager.default.createDirectory(
        at: cacheDirectory,
        withIntermediateDirectories: true,
      )
      try writeThumbnail(from: snapshot.url, to: outputURL)
      return key
    } catch {
      try? FileManager.default.removeItem(at: outputURL)
      return nil
    }
  }

  static func thumbnailURL(for key: String) -> URL {
    cacheDirectory.appendingPathComponent("\(key).png", isDirectory: false)
  }

  static func removeThumbnail(for key: String) throws {
    let url = thumbnailURL(for: key)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  private static func thumbnailCacheKey(for snapshot: LibraryFileSnapshot) -> String {
    let modifiedAt = snapshot.contentModificationDate?.timeIntervalSince1970 ?? 0
    let source = [
      cacheVersion,
      snapshot.location,
      "\(snapshot.fileSize)",
      "\(modifiedAt)",
      "\(maxPixelSize)",
    ].joined(separator: "|")

    let digest = SHA256.hash(data: Data(source.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private static func writeThumbnail(from sourceURL: URL, to outputURL: URL) throws {
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
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions) else {
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

  private enum ThumbnailCacheError: Error {
    case failedToCreateImageSource
    case failedToCreateThumbnail
    case failedToCreateDestination
    case failedToWriteThumbnail
  }
}
