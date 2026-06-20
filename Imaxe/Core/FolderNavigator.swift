//
//  FolderNavigator.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/20.
//

import Foundation

struct FolderNavigator {
  var currentImageURL: URL {
    didSet {
      if !imageURLs.contains(currentImageURL) {
        reload()
      }
    }
  }

  private(set) var imageURLs: [URL]

  var rootURL: URL {
    currentImageURL.deletingLastPathComponent()
  }

  var currentIndex: Int? {
    imageURLs.firstIndex(of: currentImageURL)
  }

  var positionDescription: String {
    if let currentIndex {
      "\(currentIndex + 1)/\(imageURLs.count)"
    } else {
      "1/1"
    }
  }

  var canNavigateToPrevious: Bool {
    if let currentIndex {
      return currentIndex > 0
    }
    return false
  }

  var canNavigateToNext: Bool {
    if let currentIndex {
      return currentIndex < imageURLs.count - 1
    }
    return false
  }

  init(for url: URL) {
    currentImageURL = url
    imageURLs = []
    reload()
  }

  static func isRegularFile(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
  }

  mutating func reload() {
    guard let contents = try? FileManager.default.contentsOfDirectory(
      at: rootURL,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles],
    ) else {
      imageURLs = [currentImageURL]
      return
    }

    imageURLs = contents
      .filter { Self.isRegularFile($0) && ImageFile.isSupportedImage($0) }
      .sorted { first, second in
        let fn1 = first.lastPathComponent
        let fn2 = second.lastPathComponent
        return fn1.localizedStandardCompare(fn2) == .orderedAscending
      }
  }

  mutating func moveToPrevious() -> Bool {
    guard let currentIndex, currentIndex > 0 else { return false }
    currentImageURL = imageURLs[currentIndex - 1]
    return true
  }

  mutating func moveToNext() -> Bool {
    guard let currentIndex, currentIndex < imageURLs.count - 1 else { return false }
    currentImageURL = imageURLs[currentIndex + 1]
    return true
  }
}
