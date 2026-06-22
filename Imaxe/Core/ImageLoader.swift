//
//  ImageLoader.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/19.
//

import AppKit
import OrderedCollections
import UniformTypeIdentifiers

nonisolated struct ImageInfo {
  let fileName: String
  let sourceURL: URL
  let type: UTType?
  let fileSize: Int
  let pixelWidth: Int
  let pixelHeight: Int

  var fileSizeDescription: String {
    ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
  }

  init(
    fileName: String,
    sourceURL: URL,
    type: UTType?,
    fileSize: Int,
    pixelWidth: Int,
    pixelHeight: Int,
  ) {
    self.fileName = fileName
    self.sourceURL = sourceURL
    self.type = type
    self.fileSize = fileSize
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
  }

  init(url: URL, pixelWidth: Int = 0, pixelHeight: Int = 0) {
    self.init(
      fileName: url.lastPathComponent,
      sourceURL: url,
      type: ImageLoader.getUTType(for: url),
      fileSize: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
    )
  }
}

nonisolated struct LoadedImage: @unchecked Sendable {
  let image: NSImage
  let displaySize: NSSize
  let info: ImageInfo

  init(
    image: NSImage,
    sourceURL: URL,
    displaySize: NSSize? = nil,
  ) {
    self.image = image
    self.displaySize = Self.displaySize(for: image, preferredSize: displaySize)
    image.cacheMode = .default
    info = ImageInfo(
      url: sourceURL,
      pixelWidth: Int(self.displaySize.width),
      pixelHeight: Int(self.displaySize.height),
    )
  }

  func revealInFinder() {
    NSWorkspace.shared.activateFileViewerSelecting([info.sourceURL])
  }

  private static func displaySize(for image: NSImage, preferredSize: NSSize?) -> NSSize {
    if let preferredSize, preferredSize.width > 0, preferredSize.height > 0 {
      return preferredSize
    }

    let imageSize = image.pixelSize
    if imageSize.width > 0, imageSize.height > 0 {
      return imageSize
    }

    return image.size
  }
}

private nonisolated struct SVGDocumentSize {
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
      Supported types: \(ImageLoader.supportedImageExtensionsDescription).
      """
    case let .failedToLoad(url):
      "Failed to load image from URL: \(url.path)"
    }
  }
}

actor ImageLoader {
  static let shared = ImageLoader()

  private init() {}

  private var cache = OrderedDictionary<URL, LoadedImage>()

  nonisolated static let supportedImageTypes: [UTType] = [
    // Bitmap formats
    .bmp,
    .gif,
    .heic,
    .heif,
    .ico,
    .jpeg,
    .png,
    .tiff,
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

  func load(from url: URL) async throws -> LoadedImage {
    guard Self.isSupportedImage(url) else {
      throw ImageLoadingError.unsupportedImageType(url)
    }

    if let cachedImage = cache[url] {
      // Move accessed image to the front to mark it as most recently used
      cache.move(keys: [url], to: 0)
      return cachedImage
    }

    let loadedImage = try await Self.decode(from: url)
    try Task.checkCancellation()

    cache[url] = loadedImage
    evictLeastRecentlyUsed()

    return loadedImage
  }

  private nonisolated static func decode(from url: URL) async throws -> LoadedImage {
    try Task.checkCancellation()

    let loadedImage: LoadedImage? = if Self.getUTType(for: url) == .svg {
      loadSVG(from: url)
    } else {
      loadBitmap(from: url)
    }

    guard let loadedImage else {
      throw ImageLoadingError.failedToLoad(url)
    }

    try Task.checkCancellation()

    return loadedImage
  }

  private nonisolated static func loadSVG(from url: URL) -> LoadedImage? {
    guard let sourceImage = NSImage(contentsOf: url) else { return nil }

    let documentSize = (try? String(contentsOf: url, encoding: .utf8))
      .map(SVGDocumentSize.init(svgString:))
    let displaySize = documentSize?.bestSize
      ?? sourceImage.pixelSize.validSize
      ?? sourceImage.size.validSize
      ?? NSSize(width: 1, height: 1)

    guard let image = rasterizedSVGImage(from: sourceImage, displaySize: displaySize) else {
      return nil
    }

    return LoadedImage(image: image, sourceURL: url, displaySize: displaySize)
  }

  private nonisolated static func loadBitmap(from url: URL) -> LoadedImage? {
    guard let image = NSImage(contentsOf: url) else { return nil }
    return LoadedImage(image: image, sourceURL: url)
  }

  private nonisolated static func rasterizedSVGImage(
    from sourceImage: NSImage,
    displaySize: NSSize,
  ) -> NSImage? {
    let pixelsWide = max(1, Int(displaySize.width.rounded(.up)))
    let pixelsHigh = max(1, Int(displaySize.height.rounded(.up)))

    guard let bitmapRep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: pixelsWide,
      pixelsHigh: pixelsHigh,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bitmapFormat: .alphaFirst,
      bytesPerRow: 0,
      bitsPerPixel: 0,
    ),
      let context = NSGraphicsContext(bitmapImageRep: bitmapRep)
    else { return nil }

    bitmapRep.size = displaySize
    sourceImage.size = displaySize

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let drawingRect = NSRect(origin: .zero, size: displaySize)
    NSColor.clear.setFill()
    drawingRect.fill()
    sourceImage.draw(
      in: drawingRect,
      from: drawingRect,
      operation: .copy,
      fraction: 1.0,
      respectFlipped: false,
      hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)],
    )
    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: displaySize)
    image.addRepresentation(bitmapRep)
    return image
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

private nonisolated extension NSRect {
  var validRect: NSRect? {
    !isNull && width > 0 && height > 0 ? self : nil
  }

  var validSize: NSSize? {
    validRect?.size
  }
}

private nonisolated extension NSSize {
  var validSize: NSSize? {
    if width > 0, height > 0 {
      self
    } else {
      nil
    }
  }
}
