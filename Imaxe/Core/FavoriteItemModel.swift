//
//  FavoriteItemModel.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/3.
//

import Foundation
import SwiftData

@Model
final class FavoriteItem {
  @Attribute(.unique) var location: String
  var isFileURL: Bool
  var displayName: String
  var kindRawValue: String
  var addedAt: Date
  var contentModificationDate: Date?
  var fileSize: Int = 0
  var thumbnailCacheKey: String?

  init(url: URL, kind: LibraryItemKind, addedAt: Date = .now) {
    let snapshot = LibraryFileSnapshot(url: url)
    location = snapshot.location
    isFileURL = snapshot.isFileURL
    displayName = snapshot.displayName
    kindRawValue = kind.rawValue
    self.addedAt = addedAt
    contentModificationDate = snapshot.contentModificationDate
    fileSize = snapshot.fileSize
    thumbnailCacheKey = kind == .image ? ImageThumbnailCache.ensureThumbnail(for: snapshot) : nil
  }

  var kind: LibraryItemKind {
    get {
      LibraryItemKind(rawValue: kindRawValue) ?? .image
    }
    set {
      kindRawValue = newValue.rawValue
    }
  }

  var url: URL? {
    if isFileURL {
      return URL(fileURLWithPath: location)
    }

    return URL(string: location)
  }

  func update(
    from snapshot: LibraryFileSnapshot,
    kind: LibraryItemKind,
    thumbnailCacheKey: String? = nil,
  ) {
    location = snapshot.location
    isFileURL = snapshot.isFileURL
    displayName = snapshot.displayName
    self.kind = kind
    contentModificationDate = snapshot.contentModificationDate
    fileSize = snapshot.fileSize
    self.thumbnailCacheKey = kind == .image
      ? (thumbnailCacheKey ?? ImageThumbnailCache.ensureThumbnail(for: snapshot))
      : nil
  }
}

struct FavoriteItemSnapshot: Identifiable, Hashable {
  let id: String
  let location: String
  let isFileURL: Bool
  let displayName: String
  let kind: LibraryItemKind
  let addedAt: Date
  let contentModificationDate: Date?
  let fileSize: Int
  let thumbnailCacheKey: String?

  init(favoriteItem: FavoriteItem) {
    id = favoriteItem.location
    location = favoriteItem.location
    isFileURL = favoriteItem.isFileURL
    displayName = favoriteItem.displayName
    kind = favoriteItem.kind
    addedAt = favoriteItem.addedAt
    contentModificationDate = favoriteItem.contentModificationDate
    fileSize = favoriteItem.fileSize
    thumbnailCacheKey = favoriteItem.thumbnailCacheKey
  }

  var url: URL? {
    if isFileURL {
      return URL(fileURLWithPath: location)
    }

    return URL(string: location)
  }
}

enum FavoriteItemsStore {
  static func add(
    _ url: URL,
    kind: LibraryItemKind,
    in modelContext: ModelContext,
    addedAt: Date = .now,
  ) throws {
    let location = LibraryFileSnapshot.location(for: url)
    let snapshot = LibraryFileSnapshot(url: url)
    let thumbnailCacheKey = kind == .image ? ImageThumbnailCache
      .ensureThumbnail(for: snapshot) : nil
    var thumbnailKeysToCleanup = Set<String>()
    var descriptor = FetchDescriptor<FavoriteItem>(
      predicate: #Predicate<FavoriteItem> { item in
        item.location == location
      },
    )
    descriptor.fetchLimit = 1

    if let favoriteItem = try modelContext.fetch(descriptor).first {
      if let oldKey = favoriteItem.thumbnailCacheKey,
         oldKey != thumbnailCacheKey
      {
        thumbnailKeysToCleanup.insert(oldKey)
      }
      favoriteItem.update(
        from: snapshot,
        kind: kind,
        thumbnailCacheKey: thumbnailCacheKey,
      )
    } else {
      let favoriteItem = FavoriteItem(url: url, kind: kind, addedAt: addedAt)
      favoriteItem.thumbnailCacheKey = thumbnailCacheKey
      modelContext.insert(favoriteItem)
    }

    try modelContext.save()
    try LibraryThumbnailReferences.removeThumbnailsIfUnused(
      thumbnailKeysToCleanup,
      in: modelContext,
    )
  }

  static func clear(in modelContext: ModelContext) throws {
    let thumbnailKeys = try thumbnailKeys(in: modelContext)
    try modelContext.delete(model: FavoriteItem.self)
    try modelContext.save()
    try LibraryThumbnailReferences.removeThumbnailsIfUnused(thumbnailKeys, in: modelContext)
  }

  static func remove(location: String, in modelContext: ModelContext) throws {
    var descriptor = FetchDescriptor<FavoriteItem>(
      predicate: #Predicate<FavoriteItem> { item in
        item.location == location
      },
    )
    descriptor.fetchLimit = 1
    guard let favoriteItem = try modelContext.fetch(descriptor).first else { return }

    let thumbnailKey = favoriteItem.thumbnailCacheKey
    modelContext.delete(favoriteItem)
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
    var descriptor = FetchDescriptor<FavoriteItem>(
      predicate: #Predicate<FavoriteItem> { item in
        item.location == oldLocation
      },
    )
    descriptor.fetchLimit = 1
    guard let favoriteItem = try modelContext.fetch(descriptor).first else { return }

    let snapshot = LibraryFileSnapshot(url: url)
    let thumbnailCacheKey = favoriteItem.kind == .image
      ? ImageThumbnailCache.ensureThumbnail(for: snapshot)
      : nil
    let oldThumbnailKey = favoriteItem.thumbnailCacheKey
    favoriteItem.update(
      from: snapshot,
      kind: favoriteItem.kind,
      thumbnailCacheKey: thumbnailCacheKey,
    )
    try modelContext.save()

    if let oldThumbnailKey,
       oldThumbnailKey != thumbnailCacheKey
    {
      try LibraryThumbnailReferences.removeThumbnailIfUnused(oldThumbnailKey, in: modelContext)
    }
  }

  private static func thumbnailKeys(in modelContext: ModelContext) throws -> Set<String> {
    let descriptor = FetchDescriptor<FavoriteItem>()
    return try Set(modelContext.fetch(descriptor).compactMap(\.thumbnailCacheKey))
  }
}
