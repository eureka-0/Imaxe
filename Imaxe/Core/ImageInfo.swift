//
//  ImageInfo.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/27.
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

nonisolated struct ImageInfo: Hashable {
  let url: URL
  let fileName: String
  let fileSize: Int
  let type: UTType?
  let pixelSize: IntSize
  let DPI: IntSize

  var location: String {
    url.deletingLastPathComponent().path()
  }

  var fileSizeDescription: String {
    ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
  }

  var typeDescription: String {
    type?.preferredFilenameExtension?.uppercased() ?? "Unknown"
  }

  var DPIDescription: String {
    if DPI.width == DPI.height {
      "\(DPI.width) Pixels/Inch"
    } else {
      "\(DPI.width) x \(DPI.height) Pixels/Inch"
    }
  }

  init(url: URL) {
    self.url = url
    fileName = url.lastPathComponent
    fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    type = ImageLoader.getUTType(for: url)

    let properties = Self.getImageProperties(from: url)
    let imagePixelSize = Self.getImagePixelSize(from: properties)
    pixelSize = if imagePixelSize.isValid {
      imagePixelSize
    } else {
      Self.getSVGPixelSize(from: url) ?? imagePixelSize
    }
    DPI = Self.getImageDPI(from: properties)
  }

  private nonisolated static func getImageProperties(from url: URL) -> [CFString: Any]? {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

    let propertiesOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, propertiesOptions)
    return properties as? [CFString: Any]
  }

  private nonisolated static func getImagePixelSize(from properties: [CFString: Any]?) -> IntSize {
    let pixelWidth = intValue(for: kCGImagePropertyPixelWidth, in: properties)
      ?? intValue(for: kCGImagePropertyWidth, in: properties)
    let pixelHeight = intValue(for: kCGImagePropertyPixelHeight, in: properties)
      ?? intValue(for: kCGImagePropertyHeight, in: properties)

    if let pixelWidth, let pixelHeight {
      return IntSize(width: pixelWidth, height: pixelHeight)
    }

    return IntSize()
  }

  private nonisolated static func getImageDPI(from properties: [CFString: Any]?) -> IntSize {
    let dpiWidth = intValue(for: kCGImagePropertyDPIWidth, in: properties)
    let dpiHeight = intValue(for: kCGImagePropertyDPIHeight, in: properties)

    if let dpiWidth, let dpiHeight {
      return IntSize(width: dpiWidth, height: dpiHeight)
    }

    if let dpiWidth {
      return IntSize(width: dpiWidth, height: dpiWidth)
    }

    if let dpiHeight {
      return IntSize(width: dpiHeight, height: dpiHeight)
    }

    return IntSize(width: 72, height: 72)
  }

  private nonisolated static func getSVGPixelSize(from url: URL) -> IntSize? {
    guard ImageLoader.getUTType(for: url) == .svg,
          let svgString = try? String(contentsOf: url, encoding: .utf8),
          let documentSize = SVGDocumentSize(svgString: svgString).bestSize
    else { return nil }

    return documentSize.validSize.intSize
  }

  private nonisolated static func intValue(
    for key: CFString,
    in properties: [CFString: Any]?,
  ) -> Int? {
    guard let value = properties?[key] else { return nil }

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
}

nonisolated struct SVGDocumentSize {
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
