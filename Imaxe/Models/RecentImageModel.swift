// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import Foundation
import Observation
import SwiftData

// MARK: - RecentImage

@Model
final class RecentImage {
  @Attribute(.unique) var path: String
  var lastOpenedAt: Date
  var thumbnailCacheKey: String?
  var sourceFileSize: Int?
  var sourceContentModificationDate: Date?

  init(url: URL, lastOpenedAt: Date = .now, fileSnapshot: FileSnapshot? = nil) {
    path = url.filePath
    self.lastOpenedAt = lastOpenedAt
    thumbnailCacheKey = nil
    sourceFileSize = fileSnapshot?.fileSize
    sourceContentModificationDate = fileSnapshot?.contentModificationDate
  }

  func update(
    from url: URL,
    lastOpenedAt: Date = .now,
    thumbnailCacheKey: String? = nil,
    fileSnapshot: FileSnapshot? = nil,
  ) {
    path = url.filePath
    self.lastOpenedAt = lastOpenedAt
    self.thumbnailCacheKey = thumbnailCacheKey
    sourceFileSize = fileSnapshot?.fileSize
    sourceContentModificationDate = fileSnapshot?.contentModificationDate
  }

  @discardableResult
  func updatePrefetchedValues(
    fileSnapshot: FileSnapshot?,
    thumbnailCacheKey: String?,
  ) -> Bool {
    var changed = false

    if let fileSnapshot,
       sourceFileSize != fileSnapshot.fileSize
       || sourceContentModificationDate != fileSnapshot.contentModificationDate
    {
      sourceFileSize = fileSnapshot.fileSize
      sourceContentModificationDate = fileSnapshot.contentModificationDate
      changed = true
    }

    if let thumbnailCacheKey, self.thumbnailCacheKey != thumbnailCacheKey {
      self.thumbnailCacheKey = thumbnailCacheKey
      changed = true
    }

    return changed
  }

  var url: URL {
    if path.hasPrefix("/") {
      return URL(fileURLWithPath: path)
    }
    return URL(string: path) ?? URL(fileURLWithPath: path)
  }

  var fileName: String {
    url.lastPathComponent
  }

  var location: String {
    url.deletingLastPathComponent().filePath
  }
}

// MARK: - RecentImagesStore

enum RecentImagesStore {
  static var recentImagesCountLimit: Int {
    let key = AppSettings.Keys.recentImagesCountLimit.rawValue
    guard UserDefaults.standard.object(forKey: key) != nil else {
      return AppSettings.Defaults.recentImagesCountLimit
    }

    let value = UserDefaults.standard.integer(forKey: key)
    return value > 0 ? value : AppSettings.Defaults.recentImagesCountLimit
  }

  static func recordOpened(
    _ url: URL,
    in modelContext: ModelContext,
    openedAt: Date = .now,
    limit: Int = recentImagesCountLimit,
    thumbnailDirectoryURL: URL = .thumbnailCachesDirectory,
  ) async throws {
    let path = url.filePath
    let fileSnapshot = FileSnapshot(url: url)
    let thumbnailCacheKey = await ImageThumbnailCache.ensureThumbnail(
      for: url,
      directoryURL: thumbnailDirectoryURL,
    )
    var thumbnailKeysToCleanup = Set<String>()
    var descriptor = FetchDescriptor<RecentImage>(
      predicate: #Predicate<RecentImage> { recentImage in
        recentImage.path == path
      },
    )
    descriptor.fetchLimit = 1

    if let recentImage = try modelContext.fetch(descriptor).first {
      if let oldKey = recentImage.thumbnailCacheKey,
         oldKey != thumbnailCacheKey
      {
        thumbnailKeysToCleanup.insert(oldKey)
      }
      recentImage.update(
        from: url,
        lastOpenedAt: openedAt,
        thumbnailCacheKey: thumbnailCacheKey,
        fileSnapshot: fileSnapshot,
      )
    } else {
      let recentImage = RecentImage(
        url: url,
        lastOpenedAt: openedAt,
        fileSnapshot: fileSnapshot,
      )
      recentImage.thumbnailCacheKey = thumbnailCacheKey
      modelContext.insert(recentImage)
    }

    try thumbnailKeysToCleanup.formUnion(trim(in: modelContext, limit: limit))
    try modelContext.save()
    try LibraryThumbnailReferences.removeThumbnailsIfUnused(
      thumbnailKeysToCleanup,
      in: modelContext,
      thumbnailDirectoryURL: thumbnailDirectoryURL,
    )
  }

  static func clear(
    in modelContext: ModelContext,
    thumbnailDirectoryURL: URL = .thumbnailCachesDirectory,
  ) throws {
    let thumbnailKeys = try thumbnailKeys(in: modelContext)
    try modelContext.delete(model: RecentImage.self)
    try modelContext.save()
    try LibraryThumbnailReferences.removeThumbnailsIfUnused(
      thumbnailKeys,
      in: modelContext,
      thumbnailDirectoryURL: thumbnailDirectoryURL,
    )
  }

  static func remove(
    path: String,
    in modelContext: ModelContext,
    limit: Int = recentImagesCountLimit,
    thumbnailDirectoryURL: URL = .thumbnailCachesDirectory,
  ) throws {
    var descriptor = FetchDescriptor<RecentImage>(
      predicate: #Predicate<RecentImage> { recentImage in
        recentImage.path == path
      },
    )
    descriptor.fetchLimit = 1
    guard let recentImage = try modelContext.fetch(descriptor).first else { return }

    var thumbnailKeysToCleanup = Set<String>()
    if let thumbnailKey = recentImage.thumbnailCacheKey {
      thumbnailKeysToCleanup.insert(thumbnailKey)
    }
    modelContext.delete(recentImage)
    try thumbnailKeysToCleanup.formUnion(trim(in: modelContext, limit: limit))
    try modelContext.save()

    try LibraryThumbnailReferences.removeThumbnailsIfUnused(
      thumbnailKeysToCleanup,
      in: modelContext,
      thumbnailDirectoryURL: thumbnailDirectoryURL,
    )
  }

  static func removeMissingFiles(
    in modelContext: ModelContext,
    thumbnailDirectoryURL: URL = .thumbnailCachesDirectory,
    scanAvailability: ([URL]) async throws -> [String: RecentImageAvailability] = { urls in
      await Task.detached(priority: .utility) {
        Dictionary(
          urls.map { ($0.filePath, RecentImageAvailability.check($0)) },
          uniquingKeysWith: { first, _ in first },
        )
      }.value
    },
  ) async throws -> MissingImagesCleanupResult {
    let descriptor = FetchDescriptor<RecentImage>()
    let imagesToScan = try modelContext.fetch(descriptor)
    let snapshots = Dictionary(uniqueKeysWithValues: imagesToScan.map {
      ($0.persistentModelID, (path: $0.path, lastOpenedAt: $0.lastOpenedAt))
    })
    let availability = try await scanAvailability(imagesToScan.map(\.url))
    let recentImages = try modelContext.fetch(descriptor)
    var thumbnailKeysToCleanup = Set<String>()
    var result = MissingImagesCleanupResult()

    for recentImage in recentImages {
      guard let snapshot = snapshots[recentImage.persistentModelID],
            recentImage.path == snapshot.path,
            recentImage.lastOpenedAt == snapshot.lastOpenedAt,
            let status = availability[snapshot.path]
      else { continue }
      if status == .unavailable {
        result.unavailableCount += 1
      }
      guard status == .missing else { continue }
      if let thumbnailCacheKey = recentImage.thumbnailCacheKey {
        thumbnailKeysToCleanup.insert(thumbnailCacheKey)
      }
      modelContext.delete(recentImage)
      result.removedCount += 1
    }

    guard result.removedCount > 0 else { return result }

    try modelContext.save()
    try LibraryThumbnailReferences.removeThumbnailsIfUnused(
      thumbnailKeysToCleanup,
      in: modelContext,
      thumbnailDirectoryURL: thumbnailDirectoryURL,
    )
    return result
  }

  static func fetchRecentImages(
    in modelContext: ModelContext,
    limit: Int = recentImagesCountLimit,
    thumbnailDirectoryURL: URL = .thumbnailCachesDirectory,
  ) throws -> [RecentImage] {
    let thumbnailKeysToCleanup = try trim(in: modelContext, limit: limit)
    try modelContext.save()
    try LibraryThumbnailReferences.removeThumbnailsIfUnused(
      thumbnailKeysToCleanup,
      in: modelContext,
      thumbnailDirectoryURL: thumbnailDirectoryURL,
    )
    let descriptor = FetchDescriptor<RecentImage>(
      sortBy: [SortDescriptor(\.lastOpenedAt, order: .reverse)],
    )
    return try modelContext.fetch(descriptor)
  }

  static func updateLocation(
    from oldPath: String,
    to url: URL,
    in modelContext: ModelContext,
    limit: Int = recentImagesCountLimit,
    thumbnailDirectoryURL: URL = .thumbnailCachesDirectory,
  ) async throws {
    var descriptor = FetchDescriptor<RecentImage>(
      predicate: #Predicate<RecentImage> { recentImage in
        recentImage.path == oldPath
      },
    )
    descriptor.fetchLimit = 1
    guard let recentImage = try modelContext.fetch(descriptor).first else { return }

    let fileSnapshot = FileSnapshot(url: url)
    let thumbnailCacheKey = await ImageThumbnailCache.ensureThumbnail(
      for: url,
      directoryURL: thumbnailDirectoryURL,
    )
    let oldThumbnailKey = recentImage.thumbnailCacheKey
    recentImage.update(
      from: url,
      lastOpenedAt: recentImage.lastOpenedAt,
      thumbnailCacheKey: thumbnailCacheKey,
      fileSnapshot: fileSnapshot,
    )
    var thumbnailKeysToCleanup = try trim(in: modelContext, limit: limit)
    if let oldThumbnailKey,
       oldThumbnailKey != thumbnailCacheKey
    {
      thumbnailKeysToCleanup.insert(oldThumbnailKey)
    }
    try modelContext.save()

    try LibraryThumbnailReferences.removeThumbnailsIfUnused(
      thumbnailKeysToCleanup,
      in: modelContext,
      thumbnailDirectoryURL: thumbnailDirectoryURL,
    )
  }

  @discardableResult
  private static func trim(in modelContext: ModelContext, limit: Int) throws -> Set<String> {
    guard limit > 0 else {
      let thumbnailKeys = try thumbnailKeys(in: modelContext)
      try modelContext.delete(model: RecentImage.self)
      return thumbnailKeys
    }

    let descriptor = FetchDescriptor<RecentImage>(
      sortBy: [SortDescriptor(\.lastOpenedAt, order: .reverse)],
    )
    let recentImages = try modelContext.fetch(descriptor)
    var thumbnailKeys = Set<String>()
    for recentImage in recentImages.dropFirst(limit) {
      if let thumbnailCacheKey = recentImage.thumbnailCacheKey {
        thumbnailKeys.insert(thumbnailCacheKey)
      }
      modelContext.delete(recentImage)
    }
    return thumbnailKeys
  }

  private static func thumbnailKeys(in modelContext: ModelContext) throws -> Set<String> {
    let descriptor = FetchDescriptor<RecentImage>()
    return try Set(modelContext.fetch(descriptor).compactMap(\.thumbnailCacheKey))
  }
}
