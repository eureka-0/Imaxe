//
//  ImageLoader.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/19.
//

import AppKit
import OrderedCollections
import SVGKit
import UniformTypeIdentifiers

enum ImageFile {
  nonisolated static let supportedImageTypes: [UTType] = [
    .png,
    .jpeg,
    .webP,
    .svg,
  ].compactMap(\.self)

  nonisolated static var supportedImageExtensions: [String] {
    supportedImageTypes.compactMap(\.preferredFilenameExtension)
  }

  nonisolated static var supportedImageExtensionsDescription: String {
    supportedImageExtensions.joined(separator: ", ")
  }

  nonisolated static func getUTType(for url: URL) -> UTType? {
    UTType(filenameExtension: url.pathExtension)
  }

  nonisolated static func isSupportedImage(_ url: URL) -> Bool {
    guard let fileType = getUTType(for: url) else {
      return false
    }

    return supportedImageTypes.contains { fileType.conforms(to: $0) }
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

  private nonisolated static func hasOnlyBitmapRepresentations(_ image: NSImage) -> Bool {
    !image.representations.isEmpty && image.representations.allSatisfy { representation in
      representation is NSBitmapImageRep || (
        representation.pixelsWide > 0 && representation.pixelsHigh > 0
      )
    }
  }

  nonisolated static func == (lhs: ImageKind, rhs: ImageKind) -> Bool {
    switch (lhs, rhs) {
    case (.bitmap, .bitmap), (.vector, .vector):
      true
    default:
      false
    }
  }
}

struct ImageInfo {
  let fileName: String
  let sourceURL: URL
  let fileSize: Int
  let pixelWidth: Int
  let pixelHeight: Int

  var fileSizeDescription: String {
    ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
  }
}

struct LoadedImage {
  let image: NSImage
  let kind: ImageKind
  let info: ImageInfo

  fileprivate init(image: NSImage, sourceURL: URL) {
    self.image = image
    kind = ImageKind(sourceURL: sourceURL, image: image)
    image.cacheMode = kind.cacheMode
    info = ImageInfo(
      fileName: sourceURL.lastPathComponent,
      sourceURL: sourceURL,
      fileSize: (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0,
      pixelWidth: Int(image.pixelSize.width),
      pixelHeight: Int(image.pixelSize.height),
    )
  }
}

enum ImageLoadingError: Error, LocalizedError {
  case unsupportedImageType(URL)
  case failedToLoad(URL)

  var errorDescription: String? {
    switch self {
    case let .unsupportedImageType(url):
      """
      Unsupported image type for: \(url.path).
      Supported types: \(ImageFile.supportedImageExtensionsDescription).
      """
    case let .failedToLoad(url):
      "Failed to load image from URL: \(url.path)"
    }
  }
}

final class ImageLoader {
  static let shared = ImageLoader()

  private var cache = OrderedDictionary<URL, LoadedImage>()

  private init() {}

  func load(from url: URL) throws(ImageLoadingError) -> LoadedImage {
    guard ImageFile.isSupportedImage(url) else {
      throw ImageLoadingError.unsupportedImageType(url)
    }

    if let cachedImage = cache[url] {
      // Move accessed image to the front to mark it as most recently used
      cache.move(keys: [url], to: 0)
      return cachedImage
    }

    var image: NSImage?
    if ImageFile.getUTType(for: url) == .svg {
      if let svgImageRep = SVGKImageRep(contentsOf: url) {
        image = NSImage(size: svgImageRep.size)
        image?.addRepresentation(svgImageRep)
      }
    } else {
      image = NSImage(contentsOf: url)
    }

    guard let image else {
      throw ImageLoadingError.failedToLoad(url)
    }

    let loadedImage = LoadedImage(image: image, sourceURL: url)
    cache[url] = loadedImage
    evictLeastRecentlyUsed()

    return loadedImage
  }

  private func evictLeastRecentlyUsed() {
    if cache.count > 10 {
      cache.removeFirst()
    }
  }

  private func clearCache() {
    cache.removeAll()
  }
}
