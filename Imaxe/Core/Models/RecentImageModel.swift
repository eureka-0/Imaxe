//
//  RecentImageModel.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/3.
//

import Foundation
import Observation
import SwiftData

@Model
final class RecentImage {
  @Attribute(.unique) var path: String
  var lastOpenedAt: Date
  var thumbnailCacheKey: String?

  init(url: URL, lastOpenedAt: Date = .now) {
    path = url.filePath
    self.lastOpenedAt = lastOpenedAt
    thumbnailCacheKey = ImageThumbnailCache.ensureThumbnail(for: url)
  }

  func update(from url: URL, lastOpenedAt: Date = .now, thumbnailCacheKey: String? = nil) {
    path = url.filePath
    self.lastOpenedAt = lastOpenedAt
    self.thumbnailCacheKey = thumbnailCacheKey ?? ImageThumbnailCache.ensureThumbnail(for: url)
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
    url.deletingLastPathComponent().path
  }

  var fileSizeDescription: String {
    ByteCountFormatter.string(fromByteCount: Int64(url.fileSize), countStyle: .file)
  }
}

enum RecentImagesStore {
  static func recordOpened(
    _ url: URL,
    in modelContext: ModelContext,
    openedAt: Date = .now,
    limit: Int = Constants.maximumRecentImagesCount,
  ) throws {
    let path = url.filePath
    let thumbnailCacheKey = ImageThumbnailCache.ensureThumbnail(for: url)
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
      )
    } else {
      let recentImage = RecentImage(url: url, lastOpenedAt: openedAt)
      recentImage.thumbnailCacheKey = thumbnailCacheKey
      modelContext.insert(recentImage)
    }

    try thumbnailKeysToCleanup.formUnion(trim(to: limit, in: modelContext))
    try modelContext.save()
    try LibraryThumbnailReferences.removeThumbnailsIfUnused(
      thumbnailKeysToCleanup,
      in: modelContext,
    )
  }

  static func clear(in modelContext: ModelContext) throws {
    let thumbnailKeys = try thumbnailKeys(in: modelContext)
    try modelContext.delete(model: RecentImage.self)
    try modelContext.save()
    try LibraryThumbnailReferences.removeThumbnailsIfUnused(thumbnailKeys, in: modelContext)
  }

  static func remove(path: String, in modelContext: ModelContext) throws {
    var descriptor = FetchDescriptor<RecentImage>(
      predicate: #Predicate<RecentImage> { recentImage in
        recentImage.path == path
      },
    )
    descriptor.fetchLimit = 1
    guard let recentImage = try modelContext.fetch(descriptor).first else { return }

    let thumbnailKey = recentImage.thumbnailCacheKey
    modelContext.delete(recentImage)
    try modelContext.save()

    if let thumbnailKey {
      try LibraryThumbnailReferences.removeThumbnailIfUnused(thumbnailKey, in: modelContext)
    }
  }

  static func updateLocation(
    from oldPath: String,
    to url: URL,
    in modelContext: ModelContext,
  ) throws {
    var descriptor = FetchDescriptor<RecentImage>(
      predicate: #Predicate<RecentImage> { recentImage in
        recentImage.path == oldPath
      },
    )
    descriptor.fetchLimit = 1
    guard let recentImage = try modelContext.fetch(descriptor).first else { return }

    let thumbnailCacheKey = ImageThumbnailCache.ensureThumbnail(for: url)
    let oldThumbnailKey = recentImage.thumbnailCacheKey
    recentImage.update(
      from: url,
      lastOpenedAt: recentImage.lastOpenedAt,
      thumbnailCacheKey: thumbnailCacheKey,
    )
    try modelContext.save()

    if let oldThumbnailKey,
       oldThumbnailKey != thumbnailCacheKey
    {
      try LibraryThumbnailReferences.removeThumbnailIfUnused(oldThumbnailKey, in: modelContext)
    }
  }

  private static func trim(to limit: Int, in modelContext: ModelContext) throws -> Set<String> {
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
