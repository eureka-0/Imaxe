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

  var enableLoopBrowsing: Bool

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
      return currentIndex > 0 || enableLoopBrowsing
    }
    return false
  }

  var canNavigateToNext: Bool {
    if let currentIndex {
      return currentIndex < imageURLs.count - 1 || enableLoopBrowsing
    }
    return false
  }

  init(for url: URL, enableLoopBrowsing: Bool) {
    currentImageURL = url
    self.enableLoopBrowsing = enableLoopBrowsing
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
      .filter { Self.isRegularFile($0) && ImageLoader.isSupportedImage($0) }
      .sorted { first, second in
        let fn1 = first.lastPathComponent
        let fn2 = second.lastPathComponent
        return fn1.localizedStandardCompare(fn2) == .orderedAscending
      }
  }

  mutating func moveToPrevious() -> Bool {
    guard let currentIndex else { return false }

    if currentIndex == 0, enableLoopBrowsing {
      currentImageURL = imageURLs.last ?? currentImageURL
      return true
    } else if currentIndex > 0 {
      currentImageURL = imageURLs[currentIndex - 1]
      return true
    }
    return false
  }

  mutating func moveToNext() -> Bool {
    guard let currentIndex else { return false }

    if currentIndex == imageURLs.count - 1, enableLoopBrowsing {
      currentImageURL = imageURLs.first ?? currentImageURL
      return true
    } else if currentIndex < imageURLs.count - 1 {
      currentImageURL = imageURLs[currentIndex + 1]
      return true
    }
    return false
  }
}
