//
//  ImageThumbnail.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/3.
//

import AppKit
import CryptoKit
import Foundation
import ImageIO
@preconcurrency import QuickLookThumbnailing
import SwiftData
import UniformTypeIdentifiers

enum LibraryThumbnailReferences {
  static func removeThumbnailsIfUnused(
    _ keys: Set<String>,
    in modelContext: ModelContext,
    thumbnailDirectoryURL: URL = .thumbnailCachesDirectory,
  ) throws {
    for key in keys {
      try removeThumbnailIfUnused(
        key,
        in: modelContext,
        thumbnailDirectoryURL: thumbnailDirectoryURL,
      )
    }
  }

  static func removeThumbnailIfUnused(
    _ key: String,
    in modelContext: ModelContext,
    thumbnailDirectoryURL: URL = .thumbnailCachesDirectory,
  ) throws {
    guard try !isThumbnailReferenced(key, in: modelContext) else { return }
    try ImageThumbnailCache.removeThumbnail(for: key, directoryURL: thumbnailDirectoryURL)
  }

  private static func isThumbnailReferenced(
    _ key: String,
    in modelContext: ModelContext,
  ) throws -> Bool {
    var descriptor = FetchDescriptor<RecentImage>(
      predicate: #Predicate<RecentImage> { $0.thumbnailCacheKey == key },
    )
    descriptor.fetchLimit = 1
    return try !modelContext.fetch(descriptor).isEmpty
  }
}

actor ImageThumbnailService {
  static let shared = ImageThumbnailService()

  private struct PendingKey: Hashable {
    let cacheKey: String
    let directoryURL: URL
  }

  private struct PendingThumbnail {
    let task: Task<Void, Never>
    var waiters: [UUID: CheckedContinuation<String?, Never>]
  }

  private var pendingThumbnails: [PendingKey: PendingThumbnail] = [:]

  func thumbnailKey(
    for url: URL,
    preferredKey: String? = nil,
    directoryURL: URL = .thumbnailCachesDirectory,
  ) async -> String? {
    if let preferredKey,
       ImageThumbnailCache.isValidThumbnail(for: preferredKey, directoryURL: directoryURL)
    {
      return preferredKey
    }

    guard let key = ImageThumbnailCache.cacheKey(for: url) else { return nil }
    if ImageThumbnailCache.isValidThumbnail(for: key, directoryURL: directoryURL) {
      return key
    }

    let pendingKey = PendingKey(cacheKey: key, directoryURL: directoryURL)
    let waiterID = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard !Task.isCancelled else {
          continuation.resume(returning: nil)
          return
        }
        addWaiter(continuation, id: waiterID, pendingKey: pendingKey, url: url)
      }
    } onCancel: {
      Task {
        await self.cancelWaiter(id: waiterID, pendingKey: pendingKey)
      }
    }
  }

  private func addWaiter(
    _ continuation: CheckedContinuation<String?, Never>,
    id: UUID,
    pendingKey: PendingKey,
    url: URL,
  ) {
    if var pending = pendingThumbnails[pendingKey] {
      pending.waiters[id] = continuation
      pendingThumbnails[pendingKey] = pending
      return
    }

    let task = Task.detached(priority: .utility) {
      let result = await ImageThumbnailCache.generateThumbnail(
        for: url,
        key: pendingKey.cacheKey,
        directoryURL: pendingKey.directoryURL,
      ) ? pendingKey.cacheKey : nil
      await self.finish(pendingKey: pendingKey, result: result)
    }
    pendingThumbnails[pendingKey] = PendingThumbnail(task: task, waiters: [id: continuation])
  }

  private func cancelWaiter(id: UUID, pendingKey: PendingKey) {
    guard var pending = pendingThumbnails[pendingKey],
          let continuation = pending.waiters.removeValue(forKey: id)
    else { return }

    continuation.resume(returning: nil)
    if pending.waiters.isEmpty {
      pending.task.cancel()
      pendingThumbnails[pendingKey] = nil
    } else {
      pendingThumbnails[pendingKey] = pending
    }
  }

  private func finish(pendingKey: PendingKey, result: String?) {
    guard let pending = pendingThumbnails.removeValue(forKey: pendingKey) else { return }
    for continuation in pending.waiters.values {
      continuation.resume(returning: result)
    }
  }
}

nonisolated enum ImageThumbnailCache {
  static let maxPixelSize = 512
  static let didChangeNotification = Notification.Name("ImageThumbnailCacheDidChange")

  private static let cacheVersion = "v2"

  static func ensureThumbnail(
    for url: URL,
    directoryURL: URL = .thumbnailCachesDirectory,
  ) async -> String? {
    await ImageThumbnailService.shared.thumbnailKey(for: url, directoryURL: directoryURL)
  }

  static func thumbnailKey(
    for url: URL,
    preferredKey: String?,
    directoryURL: URL = .thumbnailCachesDirectory,
  ) async -> String? {
    await ImageThumbnailService.shared.thumbnailKey(
      for: url,
      preferredKey: preferredKey,
      directoryURL: directoryURL,
    )
  }

  static func thumbnailURL(
    for key: String,
    directoryURL: URL = .thumbnailCachesDirectory,
  ) -> URL {
    directoryURL.appendingPathComponent("\(key).png", isDirectory: false)
  }

  static func removeThumbnail(
    for key: String,
    directoryURL: URL = .thumbnailCachesDirectory,
  ) throws {
    let url = thumbnailURL(for: key, directoryURL: directoryURL)
    if url.fileExists {
      try FileManager.default.removeItem(at: url)
      postDidChangeNotification()
    }
  }

  static func removeAllThumbnails(directoryURL: URL = .thumbnailCachesDirectory) throws {
    if directoryURL.fileExists {
      try FileManager.default.removeItem(at: directoryURL)
      postDidChangeNotification()
    }
  }

  static func totalCacheSizeInBytes(directoryURL: URL = .thumbnailCachesDirectory) -> Int {
    guard let enumerator = FileManager.default.enumerator(
      at: directoryURL,
      includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
    ) else { return 0 }

    return enumerator.reduce(into: 0) { total, item in
      guard let url = item as? URL,
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
            values.isRegularFile == true
      else { return }
      total += values.fileSize ?? 0
    }
  }

  static func cacheKey(for url: URL) -> String? {
    let sourceURL = url.freshFileURL
    guard sourceURL.isFileURL, !sourceURL.isDirectory,
          ImageLoader.isSupportedImage(sourceURL)
    else { return nil }

    let values = try? sourceURL.freshResourceValues(forKeys: [
      .contentModificationDateKey,
      .fileSizeKey,
    ])
    let source = [
      cacheVersion,
      sourceURL.filePath,
      "\(values?.fileSize ?? 0)",
      "\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)",
      "\(maxPixelSize)",
    ].joined(separator: "|")
    return SHA256.hash(data: Data(source.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  static func isValidThumbnail(
    for key: String,
    directoryURL: URL = .thumbnailCachesDirectory,
  ) -> Bool {
    let url = thumbnailURL(for: key, directoryURL: directoryURL)
    guard url.fileExists,
          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    else {
      try? FileManager.default.removeItem(at: url)
      return false
    }
    return true
  }

  static func generateThumbnail(
    for sourceURL: URL,
    key: String,
    directoryURL: URL = .thumbnailCachesDirectory,
  ) async -> Bool {
    let outputURL = thumbnailURL(for: key, directoryURL: directoryURL)
    do {
      try Task.checkCancellation()
      try FileManager.default.ensureExists(for: outputURL.deletingLastPathComponent())
      let temporaryURL = outputURL.deletingLastPathComponent()
        .appendingPathComponent(".\(key)-\(UUID().uuidString).tmp")
      defer { try? FileManager.default.removeItem(at: temporaryURL) }

      if sourceURL.utType == .svg {
        try await writeQuickLookThumbnail(from: sourceURL, to: temporaryURL)
      } else {
        try writeImageIOThumbnail(from: sourceURL, to: temporaryURL)
      }
      try Task.checkCancellation()
      guard canDecodeImage(at: temporaryURL) else {
        throw ThumbnailCacheError.invalidCachedImage
      }
      try Task.checkCancellation()
      try atomicallyInstall(temporaryURL, at: outputURL)
      postDidChangeNotification()
      return true
    } catch {
      return false
    }
  }

  private static func canDecodeImage(at url: URL) -> Bool {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
    return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
  }

  private static func atomicallyInstall(_ temporaryURL: URL, at outputURL: URL) throws {
    if outputURL.fileExists {
      _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: temporaryURL)
    } else {
      try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
    }
  }

  private static func writeImageIOThumbnail(from sourceURL: URL, to outputURL: URL) throws {
    guard let source = CGImageSourceCreateWithURL(
      sourceURL as CFURL,
      [kCGImageSourceShouldCache: false] as CFDictionary,
    ) else { throw ThumbnailCacheError.failedToCreateImageSource }

    let options = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
      kCGImageSourceShouldCacheImmediately: false,
    ] as CFDictionary
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
          let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil,
          )
    else { throw ThumbnailCacheError.failedToCreateThumbnail }

    CGImageDestinationAddImage(destination, thumbnail, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw ThumbnailCacheError.failedToWriteThumbnail
    }
  }

  private static func writeQuickLookThumbnail(from sourceURL: URL, to outputURL: URL) async throws {
    let request = QLThumbnailGenerator.Request(
      fileAt: sourceURL,
      size: CGSize(width: maxPixelSize, height: maxPixelSize),
      scale: 1,
      representationTypes: .thumbnail,
    )
    request.iconMode = false
    request.contentType = .svg

    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        QLThumbnailGenerator.shared.saveBestRepresentation(
          for: request,
          to: outputURL,
          as: .png,
        ) { error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume()
          }
        }
      }
    } onCancel: {
      QLThumbnailGenerator.shared.cancel(request)
    }
  }

  private static func postDidChangeNotification() {
    NotificationCenter.default.post(name: didChangeNotification, object: nil)
  }

  private enum ThumbnailCacheError: Error {
    case failedToCreateImageSource
    case failedToCreateThumbnail
    case failedToWriteThumbnail
    case invalidCachedImage
  }
}
