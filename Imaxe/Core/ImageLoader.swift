//
//  ImageLoader.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/19.
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

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
  private final nonisolated class ImageInfoBox {
    let info: ImageInfo

    init(info: ImageInfo) {
      self.info = info
    }
  }

  static let shared = ImageLoader()

  private var infoCache = NSCache<NSURL, ImageInfoBox>()
  private var imageCache = NSCache<NSURL, ImageContainer>()
  private var infoLoadTasks: [URL: Task<ImageInfo, Error>] = [:]
  private var imageLoadTasks: [URL: Task<ImageContainer, Error>] = [:]

  private init() {
    infoCache.name = "com.imaxe.Imaxe.infoCache"
    infoCache.countLimit = 500

    imageCache.name = "com.imaxe.Imaxe.imageCache"
    imageCache.countLimit = 50
    imageCache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
  }

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

  func loadInfo(from url: URL) async throws -> ImageInfo {
    guard Self.isSupportedImage(url) else {
      throw ImageLoadingError.unsupportedImageType(url)
    }

    if let cachedInfo = infoCache.object(forKey: url as NSURL)?.info {
      return cachedInfo
    }

    if let existingTask = infoLoadTasks[url] {
      return try await existingTask.value
    }

    let task = Task.detached(priority: .userInitiated) { () throws -> ImageInfo in
      try Task.checkCancellation()
      let info = ImageInfo(url: url)
      try Task.checkCancellation()
      return info
    }
    infoLoadTasks[url] = task

    do {
      let info = try await task.value
      infoLoadTasks[url] = nil
      infoCache.setObject(ImageInfoBox(info: info), forKey: url as NSURL)
      return info
    } catch {
      infoLoadTasks[url] = nil
      throw error
    }
  }

  func loadImage(from url: URL) async throws -> ImageContainer {
    guard Self.isSupportedImage(url) else {
      throw ImageLoadingError.unsupportedImageType(url)
    }

    if let cachedImage = imageCache.object(forKey: url as NSURL) {
      return cachedImage
    }

    if let existingTask = imageLoadTasks[url] {
      return try await existingTask.value
    }

    let task = Task.detached(priority: .userInitiated) { () throws -> ImageContainer in
      try Task.checkCancellation()
      let imageContainer: ImageContainer? = if Self.getUTType(for: url) == .svg {
        Self.loadSVG(from: url)
      } else {
        Self.loadBitmap(from: url)
      }

      guard let imageContainer else {
        throw ImageLoadingError.failedToLoad(url)
      }

      try Task.checkCancellation()
      return imageContainer
    }
    imageLoadTasks[url] = task

    do {
      let imageContainer = try await task.value
      imageLoadTasks[url] = nil
      imageCache.setObject(imageContainer, forKey: url as NSURL, cost: imageContainer.cacheCost)
      return imageContainer
    } catch {
      imageLoadTasks[url] = nil
      throw error
    }
  }

  private nonisolated static func loadBitmap(from url: URL) -> ImageContainer? {
    guard let nsImage = NSImage(contentsOf: url) else { return nil }
    return ImageContainer(url: url, nsImage: nsImage)
  }

  private nonisolated static func loadSVG(from url: URL) -> ImageContainer? {
    guard let sourceImage = NSImage(contentsOf: url) else { return nil }

    let documentSize = (try? String(contentsOf: url, encoding: .utf8))
      .map(SVGDocumentSize.init(svgString:))
    let pixelSize = documentSize?.bestSize ?? sourceImage.size.validSize

    guard let nsImage = rasterizedSVGImage(from: sourceImage, pixelSize: pixelSize) else {
      return nil
    }

    return ImageContainer(url: url, nsImage: nsImage, pixelSize: pixelSize)
  }

  private nonisolated static func rasterizedSVGImage(
    from sourceImage: NSImage, pixelSize: NSSize,
  ) -> NSImage? {
    let pixelsWide = max(1, Int(pixelSize.width.rounded(.up)))
    let pixelsHigh = max(1, Int(pixelSize.height.rounded(.up)))

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

    bitmapRep.size = pixelSize
    sourceImage.size = pixelSize

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let drawingRect = NSRect(origin: .zero, size: pixelSize)
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

    let image = NSImage(size: pixelSize)
    image.addRepresentation(bitmapRep)
    return image
  }

  func clearCache() {
    infoCache.removeAllObjects()
    imageCache.removeAllObjects()
  }
}
