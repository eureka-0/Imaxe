//
//  ImageLoader.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/19.
//

import AppKit
import OrderedCollections

struct LoadedImage {
  let image: NSImage
  let kind: ImageKind
  let fileName: String
  let sourceURL: URL
  let fileSize: Int
  let pixelWidth: Int
  let pixelHeight: Int

  var fileSizeDescription: String {
    ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
  }

  fileprivate init(image: NSImage, sourceURL: URL) {
    self.image = image
    kind = ImageKind(sourceURL: sourceURL, image: image)
    image.cacheMode = kind.cacheMode
    fileName = sourceURL.lastPathComponent
    self.sourceURL = sourceURL
    fileSize = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    pixelWidth = Int(image.pixelSize.width)
    pixelHeight = Int(image.pixelSize.height)
  }
}

enum ImageKind: Equatable {
  case bitmap
  case vector

  var cacheMode: NSImage.CacheMode {
    switch self {
    case .bitmap:
      .default
    case .vector:
      .never
    }
  }

  init(sourceURL: URL, image: NSImage) {
    if sourceURL.pathExtension.localizedCaseInsensitiveCompare("svg") == .orderedSame {
      self = .vector
    } else if Self.hasOnlyBitmapRepresentations(image) {
      self = .bitmap
    } else {
      self = .vector
    }
  }

  private static func hasOnlyBitmapRepresentations(_ image: NSImage) -> Bool {
    !image.representations.isEmpty && image.representations.allSatisfy { representation in
      representation is NSBitmapImageRep || (
        representation.pixelsWide > 0 && representation.pixelsHigh > 0
      )
    }
  }
}

final class ImageLoader {
  static let shared = ImageLoader()

  private var cache = OrderedDictionary<URL, LoadedImage>()

  private init() {}

  func loadImage(from url: URL) throws -> LoadedImage {
    if let cachedImage = cache[url] {
      // Move accessed image to the front to mark it as most recently used
      cache.move(keys: [url], to: 0)
      return cachedImage
    }

    guard let image = NSImage(contentsOf: url) else {
      throw NSError(
        domain: "ImageLoader",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to load image from URL: \(url)"],
      )
    }

    let loadedImage = LoadedImage(image: image, sourceURL: url)
    cache[url] = loadedImage
    if cache.count > 10 {
      cache.removeFirst()
    }
    return loadedImage
  }
}
