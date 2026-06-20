//
//  ImageLoader.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/19.
//

import AppKit
import OrderedCollections
import PocketSVG
import UniformTypeIdentifiers

enum ImageFile {
  nonisolated static let supportedImageTypes: [UTType] = [
    // Bitmap formats
    .png,
    .jpeg,
    .webP,
    // Vector formats
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

struct SVGVectorContent {
  let paths: [SVGBezierPath]
  let viewBox: NSRect

  var displaySize: NSSize {
    viewBox.size
  }
}

struct LoadedImage {
  let image: NSImage
  let kind: ImageKind
  let vectorContent: SVGVectorContent?
  let displaySize: NSSize
  let info: ImageInfo

  var svgPaths: [SVGBezierPath]? {
    vectorContent?.paths
  }

  init(
    image: NSImage,
    sourceURL: URL,
    kind: ImageKind? = nil,
    svgPaths: [SVGBezierPath]? = nil,
    displaySize: NSSize? = nil,
  ) {
    self.image = image
    self.kind = kind ?? ImageKind(sourceURL: sourceURL, image: image)
    vectorContent = Self.vectorContent(from: svgPaths, displaySize: displaySize)
    self.displaySize = Self.displaySize(
      for: image,
      preferredSize: displaySize,
      vectorContent: vectorContent,
    )
    image.cacheMode = self.kind.cacheMode
    info = ImageInfo(
      fileName: sourceURL.lastPathComponent,
      sourceURL: sourceURL,
      fileSize: (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0,
      pixelWidth: Int(self.displaySize.width),
      pixelHeight: Int(self.displaySize.height),
    )
  }

  private static func vectorContent(
    from svgPaths: [SVGBezierPath]?,
    displaySize: NSSize?,
  ) -> SVGVectorContent? {
    guard let paths = normalizedSVGPaths(svgPaths) else { return nil }

    let viewBox = paths.first?.viewBox.validRect
      ?? NSRect(origin: .zero, size: displaySize ?? .zero).validRect
      ?? SVGBoundingRectForPaths(paths).validRect
      ?? NSRect(x: 0, y: 0, width: 1, height: 1)

    return SVGVectorContent(paths: paths, viewBox: viewBox)
  }

  private static func normalizedSVGPaths(_ svgPaths: [SVGBezierPath]?) -> [SVGBezierPath]? {
    guard let svgPaths, !svgPaths.isEmpty else { return nil }

    let normalizedPaths = svgPaths.compactMap { path -> SVGBezierPath? in
      guard path.svgAttributes["display"] as? String != "none" else { return nil }
      guard let transform = path.svgAttributes["transform"] as? NSValue else { return path }

      path.apply(transform.svg_CGAffineTransform())
      return path
    }
    return normalizedPaths.isEmpty ? nil : normalizedPaths
  }

  private static func displaySize(
    for image: NSImage,
    preferredSize: NSSize?,
    vectorContent: SVGVectorContent?,
  ) -> NSSize {
    if let vectorContent {
      return vectorContent.displaySize
    }

    if let preferredSize,
       preferredSize.width > 0,
       preferredSize.height > 0
    {
      return preferredSize
    }

    let imageSize = image.pixelSize
    if imageSize.width > 0, imageSize.height > 0 {
      return imageSize
    }

    return image.size
  }
}

private struct SVGDocumentSize {
  let viewBox: NSRect?
  let size: NSSize?

  var bestSize: NSSize? {
    if let viewBox, viewBox.width > 0, viewBox.height > 0 {
      return viewBox.size
    }

    if let size, size.width > 0, size.height > 0 {
      return size
    }

    return nil
  }

  init(svgString: String) {
    let svgTag = Self.rootSVGTag(in: svgString) ?? ""
    let attributes = Self.attributes(in: svgTag)
    viewBox = Self.viewBox(from: attributes["viewBox"])

    if let width = Self.length(from: attributes["width"]),
       let height = Self.length(from: attributes["height"])
    {
      size = NSSize(width: width, height: height)
    } else {
      size = nil
    }
  }

  private static func rootSVGTag(in svgString: String) -> Substring? {
    guard let start = svgString.range(of: "<svg")?.lowerBound,
          let end = svgString[start...].firstIndex(of: ">")
    else { return nil }

    return svgString[start ... end]
  }

  private static func attributes(in tag: Substring) -> [String: String] {
    let pattern = #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(["'])(.*?)\2"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }

    let tagString = String(tag)
    let range = NSRange(tagString.startIndex ..< tagString.endIndex, in: tagString)
    var attributes: [String: String] = [:]

    regex.enumerateMatches(in: tagString, range: range) { match, _, _ in
      guard let match,
            let nameRange = Range(match.range(at: 1), in: tagString),
            let valueRange = Range(match.range(at: 3), in: tagString)
      else { return }

      attributes[String(tagString[nameRange])] = String(tagString[valueRange])
    }

    return attributes
  }

  private static func viewBox(from value: String?) -> NSRect? {
    guard let value else { return nil }

    let components = value
      .split { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" }
      .compactMap { Double($0) }

    guard components.count == 4,
          components[2] > 0,
          components[3] > 0
    else { return nil }

    return NSRect(
      x: components[0],
      y: components[1],
      width: components[2],
      height: components[3],
    )
  }

  private static func length(from value: String?) -> CGFloat? {
    guard let value else { return nil }

    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedValue.hasSuffix("%") else { return nil }

    let numberPrefix = trimmedValue.prefix { character in
      character.isNumber || character == "." || character == "-" || character == "+"
    }
    guard let number = Double(numberPrefix) else { return nil }

    return number > 0 ? CGFloat(number) : nil
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

    let loadedImage: LoadedImage? = if ImageFile.getUTType(for: url) == .svg {
      loadSVG(from: url)
    } else {
      loadBitmap(from: url)
    }

    guard let loadedImage else {
      throw ImageLoadingError.failedToLoad(url)
    }
    cache[url] = loadedImage
    evictLeastRecentlyUsed()

    return loadedImage
  }

  private func loadSVG(from url: URL) -> LoadedImage? {
    if let svgString = try? String(contentsOf: url, encoding: .utf8),
       svgString.isSupportedByPocketSVGNativeDrawing
    {
      let documentSize = SVGDocumentSize(svgString: svgString)
      let svgPaths = SVGBezierPath.paths(fromSVGString: svgString)

      if !svgPaths.isEmpty {
        let displaySize = documentSize.bestSize
          ?? svgPaths.first?.viewBox.validSize
          ?? SVGBoundingRectForPaths(svgPaths).validSize
          ?? NSSize(width: 1, height: 1)
        let image = NSImage(size: displaySize)
        return LoadedImage(
          image: image,
          sourceURL: url,
          kind: .vector,
          svgPaths: svgPaths,
          displaySize: displaySize,
        )
      }
    }

    guard let image = NSImage(contentsOf: url) else { return nil }
    return LoadedImage(image: image, sourceURL: url, kind: .vector)
  }

  private func loadBitmap(from url: URL) -> LoadedImage? {
    guard let image = NSImage(contentsOf: url) else { return nil }
    return LoadedImage(image: image, sourceURL: url)
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

private extension NSRect {
  var validRect: NSRect? {
    !isNull && width > 0 && height > 0 ? self : nil
  }

  var validSize: NSSize? {
    validRect?.size
  }
}

private extension String {
  var isSupportedByPocketSVGNativeDrawing: Bool {
    range(
      of: #"<\s*(?:clipPath|mask|filter|pattern|image|use|text|linearGradient|radialGradient)\b"#,
      options: [.regularExpression, .caseInsensitive],
    ) == nil
      && range(
        of: #"(?:fill|stroke)\s*(?:=|:)\s*["']?url\("#,
        options: [.regularExpression, .caseInsensitive],
      ) == nil
  }
}
