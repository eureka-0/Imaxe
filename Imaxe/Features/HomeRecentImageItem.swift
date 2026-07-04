//
//  HomeRecentImageItem.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/4.
//

import Foundation

struct HomeRecentImageItem: Identifiable, Hashable {
  let id: String
  let location: String
  let isFileURL: Bool
  let displayName: String
  let lastOpenedAt: Date
  let contentModificationDate: Date?
  let fileSize: Int
  let thumbnailCacheKey: String?

  init(recentImage: RecentImageItem) {
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

  var fileSizeDescription: String {
    ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
  }

  var searchableText: String {
    "\(displayName)\n\(location)"
  }
}
