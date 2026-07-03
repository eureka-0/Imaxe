//
//  RecentImage.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/3.
//

import Foundation
import Observation
import SwiftData

@Model
final class RecentImage {
  @Attribute(.unique) var location: String
  var isFileURL: Bool
  var displayName: String
  var lastOpenedAt: Date
  var contentModificationDate: Date?
  var fileSize: Int = 0
  var thumbnailCacheKey: String?

  init(url: URL, lastOpenedAt: Date = .now) {
    let snapshot = LibraryFileSnapshot(url: url)
    location = snapshot.location
    isFileURL = snapshot.isFileURL
    displayName = snapshot.displayName
    self.lastOpenedAt = lastOpenedAt
    contentModificationDate = snapshot.contentModificationDate
    fileSize = snapshot.fileSize
    thumbnailCacheKey = ImageThumbnailCache.ensureThumbnail(for: snapshot)
  }

  var url: URL? {
    if isFileURL {
      return URL(fileURLWithPath: location)
    }

    return URL(string: location)
  }

  func update(from url: URL, lastOpenedAt: Date = .now) {
    let snapshot = LibraryFileSnapshot(url: url)
    update(from: snapshot, lastOpenedAt: lastOpenedAt)
  }

  func update(
    from snapshot: LibraryFileSnapshot,
    lastOpenedAt: Date = .now,
    thumbnailCacheKey: String? = nil,
  ) {
    location = snapshot.location
    isFileURL = snapshot.isFileURL
    displayName = snapshot.displayName
    self.lastOpenedAt = lastOpenedAt
    contentModificationDate = snapshot.contentModificationDate
    fileSize = snapshot.fileSize
    self.thumbnailCacheKey = thumbnailCacheKey ?? ImageThumbnailCache.ensureThumbnail(for: snapshot)
  }

  static func location(for url: URL) -> String {
    LibraryFileSnapshot.location(for: url)
  }
}

struct RecentImageItem: Identifiable, Hashable {
  let id: String
  let location: String
  let isFileURL: Bool
  let displayName: String
  let lastOpenedAt: Date
  let contentModificationDate: Date?
  let fileSize: Int
  let thumbnailCacheKey: String?

  init(recentImage: RecentImage) {
    id = recentImage.location
    location = recentImage.location
    isFileURL = recentImage.isFileURL
    displayName = recentImage.displayName
    lastOpenedAt = recentImage.lastOpenedAt
    contentModificationDate = recentImage.contentModificationDate
    fileSize = recentImage.fileSize
    thumbnailCacheKey = recentImage.thumbnailCacheKey
  }

  var url: URL? {
    if isFileURL {
      return URL(fileURLWithPath: location)
    }

    return URL(string: location)
  }
}

@Observable
final class RecentImagesSnapshot {
  var items: [RecentImageItem]

  init(items: [RecentImageItem] = []) {
    self.items = items
  }
}

enum RecentImagesStore {
  static let defaultLimit = 100

  static func recordOpened(
    _ url: URL,
    in modelContext: ModelContext,
    openedAt: Date = .now,
    limit: Int = defaultLimit,
  ) throws {
    let location = RecentImage.location(for: url)
    let snapshot = LibraryFileSnapshot(url: url)
    let thumbnailCacheKey = ImageThumbnailCache.ensureThumbnail(for: snapshot)
    var thumbnailKeysToCleanup = Set<String>()
    var descriptor = FetchDescriptor<RecentImage>(
      predicate: #Predicate<RecentImage> { recentImage in
        recentImage.location == location
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
        from: snapshot,
        lastOpenedAt: openedAt,
        thumbnailCacheKey: thumbnailCacheKey,
      )
    } else {
      let recentImage = RecentImage(url: url, lastOpenedAt: openedAt)
      recentImage.thumbnailCacheKey = thumbnailCacheKey
      modelContext.insert(recentImage)
    }

    thumbnailKeysToCleanup.formUnion(try trim(to: limit, in: modelContext))
    try modelContext.save()
    try LibraryThumbnailReferences.removeThumbnailsIfUnused(thumbnailKeysToCleanup, in: modelContext)
  }

  static func clear(in modelContext: ModelContext) throws {
    let thumbnailKeys = try thumbnailKeys(in: modelContext)
    try modelContext.delete(model: RecentImage.self)
    try modelContext.save()
    try LibraryThumbnailReferences.removeThumbnailsIfUnused(thumbnailKeys, in: modelContext)
  }

  static func remove(location: String, in modelContext: ModelContext) throws {
    var descriptor = FetchDescriptor<RecentImage>(
      predicate: #Predicate<RecentImage> { recentImage in
        recentImage.location == location
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
    from oldLocation: String,
    to url: URL,
    in modelContext: ModelContext,
  ) throws {
    var descriptor = FetchDescriptor<RecentImage>(
      predicate: #Predicate<RecentImage> { recentImage in
        recentImage.location == oldLocation
      },
    )
    descriptor.fetchLimit = 1
    guard let recentImage = try modelContext.fetch(descriptor).first else { return }

    let snapshot = LibraryFileSnapshot(url: url)
    let thumbnailCacheKey = ImageThumbnailCache.ensureThumbnail(for: snapshot)
    let oldThumbnailKey = recentImage.thumbnailCacheKey
    recentImage.update(
      from: snapshot,
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
    return Set(try modelContext.fetch(descriptor).compactMap(\.thumbnailCacheKey))
  }
}
