//
//  ImageCollectionItem.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/6.
//

import SwiftUI

@Observable
final class ImageCollectionItem: Identifiable {
  let url: URL
  var lastOpenedAt: Date
  var thumbnailCacheKey: String?
  var isHovered: Bool = false

  var id: String {
    path
  }

  var path: String {
    url.filePath
  }

  var location: String {
    url.deletingLastPathComponent().path
  }

  var fileName: String {
    url.lastPathComponent
  }

  var searchableText: String {
    "\(fileName)\n\(location)"
  }

  var fileSizeDescription: String {
    ByteCountFormatter.string(fromByteCount: Int64(url.fileSize), countStyle: .file)
  }

  init(url: URL, lastOpenedAt: Date = .now, thumbnailCacheKey: String? = nil) {
    self.url = url
    self.lastOpenedAt = lastOpenedAt
    self.thumbnailCacheKey = thumbnailCacheKey
  }
}
