//
//  FolderNavigator.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/20.
//

import Foundation

nonisolated struct FolderNavigator {
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
      return currentIndex > 0 || (enableLoopBrowsing && imageURLs.count > 1)
    }
    return false
  }

  var canNavigateToNext: Bool {
    if let currentIndex {
      return currentIndex < imageURLs.count - 1 || (enableLoopBrowsing && imageURLs.count > 1)
    }
    return false
  }

  init(for url: URL, enableLoopBrowsing: Bool, imageURLs: [URL]? = nil) {
    currentImageURL = url
    self.enableLoopBrowsing = enableLoopBrowsing
    self.imageURLs = Self.positionedImageURLs(imageURLs ?? [url], currentURL: url)
  }

  static func isRegularFile(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
  }

  mutating func reload() {
    imageURLs = (try? Self.imageURLs(in: rootURL, fallbackURL: currentImageURL)) ??
      [currentImageURL]
  }

  mutating func replaceImageURLs(_ imageURLs: [URL]) {
    self.imageURLs = Self.positionedImageURLs(imageURLs, currentURL: currentImageURL)
  }

  static func imageURLs(for url: URL) async -> [URL]? {
    let rootURL = url.deletingLastPathComponent()

    let scanTask = Task.detached(priority: .userInitiated) {
      try Self.imageURLs(in: rootURL, fallbackURL: url)
    }

    return await withTaskCancellationHandler {
      try? await scanTask.value
    } onCancel: {
      scanTask.cancel()
    }
  }

  private static func imageURLs(in rootURL: URL, fallbackURL: URL) throws -> [URL] {
    let contents: [URL]
    do {
      contents = try FileManager.default.contentsOfDirectory(
        at: rootURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles],
      )
    } catch {
      return [fallbackURL]
    }

    var imageURLs: [URL] = []
    imageURLs.reserveCapacity(contents.count)
    for url in contents {
      try Task.checkCancellation()
      if Self.isRegularFile(url), ImageLoader.isSupportedImage(url) {
        imageURLs.append(url)
      }
    }

    try Task.checkCancellation()
    imageURLs.sort(by: compareImageURLs)
    try Task.checkCancellation()
    return positionedImageURLs(imageURLs, currentURL: fallbackURL)
  }

  private static func positionedImageURLs(_ imageURLs: [URL], currentURL: URL) -> [URL] {
    var positionedURLs = imageURLs.filter { !sameFile($0, currentURL) }
    positionedURLs.append(currentURL)
    positionedURLs.sort(by: compareImageURLs)
    return positionedURLs
  }

  private static func sameFile(_ first: URL, _ second: URL) -> Bool {
    if first == second {
      return true
    }

    if let firstSnapshot = FileSnapshot(url: first),
       let secondSnapshot = FileSnapshot(url: second),
       firstSnapshot.hasSameFileIdentity(as: secondSnapshot)
    {
      return true
    }

    return first.standardizedFileURL.resolvingSymlinksInPath().filePath
      == second.standardizedFileURL.resolvingSymlinksInPath().filePath
  }

  private static func compareImageURLs(_ first: URL, _ second: URL) -> Bool {
    first.lastPathComponent.localizedStandardCompare(second.lastPathComponent) == .orderedAscending
  }

  mutating func moveToPrevious() -> Bool {
    guard let currentIndex else { return false }

    if currentIndex == 0, enableLoopBrowsing, imageURLs.count > 1 {
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

    if currentIndex == imageURLs.count - 1, enableLoopBrowsing, imageURLs.count > 1 {
      currentImageURL = imageURLs.first ?? currentImageURL
      return true
    } else if currentIndex < imageURLs.count - 1 {
      currentImageURL = imageURLs[currentIndex + 1]
      return true
    }
    return false
  }
}
