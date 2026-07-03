//
//  LibraryThumbnailReferences.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/3.
//

import Foundation
import SwiftData

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

    var favoriteDescriptor = FetchDescriptor<FavoriteItem>(
      predicate: #Predicate<FavoriteItem> { favoriteItem in
        favoriteItem.thumbnailCacheKey == key
      },
    )
    favoriteDescriptor.fetchLimit = 1
    return try !modelContext.fetch(favoriteDescriptor).isEmpty
  }
}
