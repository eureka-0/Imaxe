//
//  HomeCollectionModels.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/3.
//

import Foundation

enum HomeCollectionViewMode: String, CaseIterable, Identifiable {
  case list
  case grid

  var id: Self { self }

  var title: String {
    switch self {
    case .list: "List"
    case .grid: "Grid"
    }
  }

  var systemImage: String {
    switch self {
    case .list: "list.bullet"
    case .grid: "square.grid.2x2"
    }
  }
}

enum HomeCollectionSort: String, CaseIterable, Identifiable {
  case name
  case lastOpenedAt
  case modifiedAt
  case fileSize

  var id: Self { self }

  var title: String {
    switch self {
    case .name: "Name"
    case .lastOpenedAt: "Last Opened"
    case .modifiedAt: "Modified"
    case .fileSize: "Size"
    }
  }

  var systemImage: String {
    switch self {
    case .name: "textformat"
    case .lastOpenedAt: "clock"
    case .modifiedAt: "calendar"
    case .fileSize: "externaldrive"
    }
  }
}

enum HomeSortDirection {
  case ascending
  case descending

  mutating func toggle() {
    self = self == .ascending ? .descending : .ascending
  }

  var systemImage: String {
    switch self {
    case .ascending: "arrow.up"
    case .descending: "arrow.down"
    }
  }

  var title: String {
    switch self {
    case .ascending: "Ascending"
    case .descending: "Descending"
    }
  }
}

struct HomeCollectionItem: Identifiable, Hashable {
  enum Source: Hashable {
    case recent
    case favorite
    case favoriteFolderImage
  }

  let id: String
  let source: Source
  let location: String
  let isFileURL: Bool
  let displayName: String
  let kind: LibraryItemKind
  let lastOpenedAt: Date?
  let addedAt: Date?
  let contentModificationDate: Date?
  let fileSize: Int
  let thumbnailCacheKey: String?

  init(recentImage: RecentImageItem) {
    id = "recent:\(recentImage.location)"
    source = .recent
    location = recentImage.location
    isFileURL = recentImage.isFileURL
    displayName = recentImage.displayName
    kind = .image
    lastOpenedAt = recentImage.lastOpenedAt
    addedAt = nil
    contentModificationDate = recentImage.contentModificationDate
    fileSize = recentImage.fileSize
    thumbnailCacheKey = recentImage.thumbnailCacheKey
  }

  init(favoriteItem: FavoriteItemSnapshot) {
    id = "favorite:\(favoriteItem.location)"
    source = .favorite
    location = favoriteItem.location
    isFileURL = favoriteItem.isFileURL
    displayName = favoriteItem.displayName
    kind = favoriteItem.kind
    lastOpenedAt = nil
    addedAt = favoriteItem.addedAt
    contentModificationDate = favoriteItem.contentModificationDate
    fileSize = favoriteItem.fileSize
    thumbnailCacheKey = favoriteItem.thumbnailCacheKey
  }

  init(favoriteFolderImageURL url: URL) {
    let snapshot = LibraryFileSnapshot(url: url)
    id = "favorite-folder-image:\(snapshot.location)"
    source = .favoriteFolderImage
    location = snapshot.location
    isFileURL = snapshot.isFileURL
    displayName = snapshot.displayName
    kind = .image
    lastOpenedAt = nil
    addedAt = nil
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

  var sortDate: Date? {
    lastOpenedAt ?? addedAt
  }

  var fileSizeDescription: String {
    guard kind != .folder else { return "--" }

    return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
  }
}
