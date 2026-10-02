// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - ImageMetadata

nonisolated struct ImageMetadata: Hashable, Sendable {
  private(set) var url: URL
  private(set) var fileName: String
  let fileSize: Int
  let containerType: UTType?
  let imageCount: Int
  let primaryImageIndex: Int
  let rawPixelSize: IntSize
  let displayPixelSize: IntSize
  let orientation: CGImagePropertyOrientation
  let DPI: IntSize
  let depth: Int?
  let colorModel: String?
  let colorProfileName: String?
  let hasAlpha: Bool
  let estimatedFullFrameBytes: Int
  let isAnimated: Bool
  let isMultiPage: Bool
  let isSVG: Bool

  var location: String {
    url.deletingLastPathComponent().filePath
  }

  var typeDescription: String {
    containerType?.preferredFilenameExtension?.uppercased() ?? "Unknown"
  }

  var DPIDescription: String {
    if DPI.width == DPI.height {
      "\(DPI.width) Pixels/Inch"
    } else {
      "\(DPI.width) x \(DPI.height) Pixels/Inch"
    }
  }

  var bitDepthDescription: String {
    if let depth {
      "\(depth) Bits/Channel"
    } else {
      "Unknown"
    }
  }

  var colorSpaceDescription: String {
    if let colorProfileName {
      colorProfileName
    } else if let colorModel {
      colorModel
    } else {
      "Unknown"
    }
  }

  var displayDPI: IntSize {
    orientation.swapsDimensions ? IntSize(width: DPI.height, height: DPI.width) : DPI
  }

  var pageDescription: String? {
    guard containerType?.conforms(to: .tiff) == true, imageCount > 1 else { return nil }
    return "1 / \(imageCount)"
  }

  var alphaDescription: String {
    hasAlpha ? "Yes" : "No"
  }

  func relocated(to url: URL) -> ImageMetadata {
    var metadata = self
    metadata.url = url
    metadata.fileName = url.lastPathComponent
    return metadata
  }

  init(url: URL) throws {
    let freshURL = url.freshFileURL

    if ImageLoader.isSVG(freshURL) {
      let data = try Data(contentsOf: freshURL, options: [.mappedIfSafe, .uncached])
      try self.init(svgURL: freshURL, data: data)
      return
    }

    guard let imageSource = CGImageSourceCreateWithURL(freshURL as CFURL, nil) else {
      throw ImageLoadingError.corruptImage(freshURL)
    }

    try self.init(bitmapURL: freshURL, imageSource: imageSource)
  }

  init(bitmapURL url: URL, imageSource: CGImageSource) throws {
    let imageCount = CGImageSourceGetCount(imageSource)
    guard imageCount > 0 else {
      throw ImageLoadingError.corruptImage(url)
    }

    let propertiesOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let properties = CGImageSourceCopyPropertiesAtIndex(
      imageSource,
      0,
      propertiesOptions,
    ) as? [CFString: Any]
    else { throw ImageLoadingError.corruptImage(url) }

    let rawPixelSize = Self.imagePixelSize(from: properties)
    guard rawPixelSize.isValid else {
      throw ImageLoadingError.invalidDimensions(url)
    }
    let orientation = Self.imageOrientation(from: properties)
    let displayPixelSize = orientation.swapsDimensions
      ? IntSize(width: rawPixelSize.height, height: rawPixelSize.width)
      : rawPixelSize
    let containerType = CGImageSourceGetType(imageSource)
      .flatMap { UTType($0 as String) }
      ?? ImageLoader.imageTypes(for: url).first { $0.conforms(to: .image) }
    let depth = Self.intValue(for: kCGImagePropertyDepth, in: properties)
    let hasAlpha = Self.boolValue(for: kCGImagePropertyHasAlpha, in: properties) ?? false

    self.url = url
    fileName = url.lastPathComponent
    fileSize = url.fileSize
    self.containerType = containerType
    self.imageCount = imageCount
    primaryImageIndex = 0
    self.rawPixelSize = rawPixelSize
    self.displayPixelSize = displayPixelSize
    self.orientation = orientation
    DPI = Self.imageDPI(from: properties)
    self.depth = depth
    colorModel = properties[kCGImagePropertyColorModel] as? String
    colorProfileName = properties[kCGImagePropertyProfileName] as? String
    self.hasAlpha = hasAlpha
    estimatedFullFrameBytes = Self.estimatedFrameBytes(
      pixelSize: displayPixelSize,
      depth: depth,
    )
    isAnimated = imageCount > 1 && containerType?.conforms(to: .gif) == true
    isMultiPage = imageCount > 1 && containerType?.conforms(to: .tiff) == true
    isSVG = false
  }

  init(svgURL url: URL, data: Data) throws {
    guard let svgString = String(data: data, encoding: .utf8) else {
      throw ImageLoadingError.corruptImage(url)
    }

    let documentSize = SVGDocumentSize(svgString: svgString)
    guard documentSize.hasRootElement else {
      throw ImageLoadingError.corruptImage(url)
    }
    if documentSize.hasExplicitDimensions, documentSize.bestSize == nil {
      throw ImageLoadingError.invalidDimensions(url)
    }

    let fallbackSize = NSImage(data: data)?.size.validSize
    let pixelSize = (documentSize.bestSize ?? fallbackSize)?.intSize ?? IntSize()
    guard pixelSize.isValid else {
      throw ImageLoadingError.invalidDimensions(url)
    }
    self.url = url
    fileName = url.lastPathComponent
    fileSize = url.fileSize
    containerType = .svg
    imageCount = 1
    primaryImageIndex = 0
    rawPixelSize = pixelSize
    displayPixelSize = pixelSize
    orientation = .up
    DPI = IntSize(width: 72, height: 72)
    depth = nil
    colorModel = nil
    colorProfileName = nil
    hasAlpha = true
    estimatedFullFrameBytes = Self.estimatedFrameBytes(pixelSize: pixelSize, depth: nil)
    isAnimated = false
    isMultiPage = false
    isSVG = true
  }

  private static func imagePixelSize(from properties: [CFString: Any]) -> IntSize {
    let pixelWidth = intValue(for: kCGImagePropertyPixelWidth, in: properties)
      ?? intValue(for: kCGImagePropertyWidth, in: properties)
    let pixelHeight = intValue(for: kCGImagePropertyPixelHeight, in: properties)
      ?? intValue(for: kCGImagePropertyHeight, in: properties)

    guard let pixelWidth, let pixelHeight else { return IntSize() }
    return IntSize(width: pixelWidth, height: pixelHeight)
  }

  private static func imageOrientation(
    from properties: [CFString: Any],
  ) -> CGImagePropertyOrientation {
    guard let rawValue = intValue(for: kCGImagePropertyOrientation, in: properties),
          (1 ... 8).contains(rawValue),
          let orientation = CGImagePropertyOrientation(rawValue: UInt32(rawValue))
    else { return .up }

    return orientation
  }

  private static func imageDPI(from properties: [CFString: Any]) -> IntSize {
    let dpiWidth = intValue(for: kCGImagePropertyDPIWidth, in: properties)
    let dpiHeight = intValue(for: kCGImagePropertyDPIHeight, in: properties)

    if let dpiWidth, let dpiHeight, dpiWidth > 0, dpiHeight > 0 {
      return IntSize(width: dpiWidth, height: dpiHeight)
    }
    if let dpiWidth, dpiWidth > 0 {
      return IntSize(width: dpiWidth, height: dpiWidth)
    }
    if let dpiHeight, dpiHeight > 0 {
      return IntSize(width: dpiHeight, height: dpiHeight)
    }

    return IntSize(width: 72, height: 72)
  }

  static func estimatedFrameBytes(pixelSize: IntSize, depth: Int?) -> Int {
    let bytesPerPixel = (depth ?? 8) > 8 ? 8 : 4
    let (pixelCount, pixelOverflow) = pixelSize.width.multipliedReportingOverflow(
      by: pixelSize.height,
    )
    guard !pixelOverflow else { return Int.max }
    let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: bytesPerPixel)
    return byteOverflow ? Int.max : byteCount
  }

  private static func intValue(
    for key: CFString,
    in properties: [CFString: Any],
  ) -> Int? {
    guard let value = properties[key] else { return nil }

    if let value = value as? Int {
      return value
    }
    if let value = value as? NSNumber {
      return value.intValue
    }
    if let value = value as? Double {
      return Int(value.rounded())
    }

    return nil
  }

  private static func boolValue(
    for key: CFString,
    in properties: [CFString: Any],
  ) -> Bool? {
    if let value = properties[key] as? Bool {
      return value
    }
    return (properties[key] as? NSNumber)?.boolValue
  }
}

// MARK: - ImageContent

nonisolated enum ImageContent: Sendable {
  case staticBitmap(NSImage)
  case animatedGIF(NSImage, data: Data)
  case svg(NSImage)

  var nsImage: NSImage {
    switch self {
    case let .staticBitmap(image), let .animatedGIF(image, _), let .svg(image):
      image
    }
  }

  func makeAnimatedBitmapRepresentation() -> NSBitmapImageRep? {
    guard case let .animatedGIF(_, data) = self,
          let bitmapRep = NSBitmapImageRep(data: data),
          (bitmapRep.gifFrameCount ?? 0) > 1
    else { return nil }

    return bitmapRep
  }
}

// MARK: - ImageDocument

nonisolated struct GIFPlaybackState {
  private(set) var frame = 0
  private(set) var completedLoops = 0
  private(set) var isFinished = false

  mutating func advance(frameCount: Int, loopCount: Int) -> Bool {
    guard frameCount > 1, !isFinished else { return false }
    if frame + 1 == frameCount {
      completedLoops += 1
      if loopCount > 0, completedLoops >= loopCount {
        isFinished = true
        return false
      }
    }
    frame = (frame + 1) % frameCount
    return true
  }
}

nonisolated struct ImageDocument: Sendable {
  let id: UUID
  let url: URL
  let fileSnapshot: FileSnapshot
  let metadata: ImageMetadata
  let content: ImageContent

  /// Pixel dimensions of the representation retained for rendering, which may be downsampled.
  let renderedPixelSize: IntSize

  /// Indicates whether the image has been downsampled for rendering.
  var isDownsampled: Bool {
    renderedPixelSize != metadata.displayPixelSize
  }

  var nsImage: NSImage {
    content.nsImage
  }

  var pixelSize: NSSize {
    // Canvas geometry stays in the oriented source image's coordinate space.
    metadata.displayPixelSize.nsSize
  }

  var cacheCost: Int {
    let frameBytes = ImageMetadata.estimatedFrameBytes(
      pixelSize: renderedPixelSize,
      depth: metadata.depth,
    )
    guard case let .animatedGIF(_, data) = content else { return frameBytes }
    let (frames, overflow) = frameBytes.multipliedReportingOverflow(by: metadata.imageCount)
    let (total, totalOverflow) = frames.addingReportingOverflow(data.count)
    return overflow || totalOverflow ? Int.max : total
  }

  init(
    id: UUID = UUID(),
    url: URL,
    fileSnapshot: FileSnapshot,
    metadata: ImageMetadata,
    content: ImageContent,
    renderedPixelSize: IntSize? = nil,
  ) {
    self.id = id
    self.url = url
    self.fileSnapshot = fileSnapshot
    self.metadata = metadata
    self.content = content
    self.renderedPixelSize = renderedPixelSize ?? metadata.displayPixelSize
    content.nsImage.cacheMode = isDownsampled ? .never : .default
  }

  func makeAnimatedBitmapRepresentation() -> NSBitmapImageRep? {
    content.makeAnimatedBitmapRepresentation()
  }

  func withNewID() -> ImageDocument {
    ImageDocument(
      url: url,
      fileSnapshot: fileSnapshot,
      metadata: metadata,
      content: content,
      renderedPixelSize: renderedPixelSize,
    )
  }

  func relocated(to url: URL) -> ImageDocument {
    ImageDocument(
      id: id,
      url: url,
      fileSnapshot: FileSnapshot(url: url) ?? fileSnapshot,
      metadata: metadata.relocated(to: url),
      content: content,
      renderedPixelSize: renderedPixelSize,
    )
  }
}

// MARK: - SVGDocumentSize

nonisolated struct SVGDocumentSize {
  let viewBox: NSRect?
  let size: NSSize?
  let hasExplicitDimensions: Bool
  let hasRootElement: Bool

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
    let rootSVGTag = Self.rootSVGTag(in: svgString)
    let svgTag = rootSVGTag ?? ""
    let attributes = Self.attributes(in: svgTag)
    hasRootElement = rootSVGTag != nil
    hasExplicitDimensions = attributes["viewBox"] != nil
      || attributes["width"] != nil
      || attributes["height"] != nil
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
    let unitSuffix = trimmedValue.dropFirst(numberPrefix.count)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard unitSuffix.isEmpty || unitSuffix == "px" else { return nil }
    guard let number = Double(numberPrefix) else { return nil }

    return number > 0 ? CGFloat(number) : nil
  }
}

private nonisolated extension CGImagePropertyOrientation {
  var swapsDimensions: Bool {
    switch self {
    case .left, .leftMirrored, .right, .rightMirrored:
      true
    default:
      false
    }
  }
}
