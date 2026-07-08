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
  case fileNotFound(URL)
  case failedToLoad(URL)

  var errorDescription: String? {
    switch self {
    case let .unsupportedImageType(url):
      """
      Unsupported image type for: \(url.fileSystemPath).
      Supported types: \(ImageLoader.supportedImageExtensionsDescription).
      """
    case let .fileNotFound(url):
      "The file no longer exists: \(url.fileSystemPath)"
    case let .failedToLoad(url):
      "Failed to load image from URL: \(url.fileSystemPath)"
    }
  }
}

actor ImageLoader {
  private final nonisolated class ImageInfoBox {
    let info: ImageInfo
    let fileSnapshot: FileSnapshot

    init(info: ImageInfo, fileSnapshot: FileSnapshot) {
      self.info = info
      self.fileSnapshot = fileSnapshot
    }
  }

  private final nonisolated class ImageContainerBox {
    let imageContainer: ImageContainer
    let fileSnapshot: FileSnapshot

    init(imageContainer: ImageContainer, fileSnapshot: FileSnapshot) {
      self.imageContainer = imageContainer
      self.fileSnapshot = fileSnapshot
    }
  }

  private struct ImageInfoLoadTask {
    let id: UUID
    let fileSnapshot: FileSnapshot
    let task: Task<ImageInfo, Error>
    var requestIDs: Set<LoadRequestID>
    var uncancellableWaiterCount: Int

    var hasWaiters: Bool {
      !requestIDs.isEmpty || uncancellableWaiterCount > 0
    }
  }

  private struct ImageContainerLoadTask {
    let id: UUID
    let fileSnapshot: FileSnapshot
    let task: Task<ImageContainer, Error>
    var requestIDs: Set<LoadRequestID>
    var uncancellableWaiterCount: Int

    var hasWaiters: Bool {
      !requestIDs.isEmpty || uncancellableWaiterCount > 0
    }
  }

  nonisolated struct LoadRequestID: Hashable {
    private let value = UUID()
  }

  static let shared = ImageLoader()

  private var infoCache = NSCache<NSURL, ImageInfoBox>()
  private var imageCache = NSCache<NSURL, ImageContainerBox>()
  private var infoLoadTasks: [URL: ImageInfoLoadTask] = [:]
  private var imageLoadTasks: [URL: ImageContainerLoadTask] = [:]

  private init() {
    infoCache.name = "com.imaxe.Imaxe.infoCache"
    infoCache.countLimit = 500

    imageCache.name = "com.imaxe.Imaxe.imageCache"
    imageCache.countLimit = 50
    imageCache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
  }

  nonisolated static var supportedImageTypes: [UTType] {
    let supportedTypes: [UTType] = [
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

    #if DEBUG
      debugPrint(
        "Supported image types: \(supportedTypes.map(\.identifier).joined(separator: ", "))",
      )
    #endif

    return supportedTypes
  }

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

  func loadInfo(from url: URL, requestID: LoadRequestID? = nil) async throws -> ImageInfo {
    try validateFileExists(at: url)

    guard Self.isSupportedImage(url) else {
      throw ImageLoadingError.unsupportedImageType(url)
    }

    guard let fileSnapshot = FileSnapshot(url: url) else {
      throw ImageLoadingError.failedToLoad(url)
    }

    let cacheKey = url as NSURL
    if let cachedInfo = infoCache.object(forKey: cacheKey) {
      if cachedInfo.fileSnapshot == fileSnapshot {
        return cachedInfo.info
      }

      infoCache.removeObject(forKey: cacheKey)
    }

    if let existingTask = infoLoadTasks[url] {
      if existingTask.fileSnapshot == fileSnapshot {
        registerInfoWaiter(requestID, for: url)
        let info = try await value(of: existingTask.task, requestID: requestID)
        try Task.checkCancellation()
        cacheInfo(info, for: url, cacheKey: cacheKey, fileSnapshot: fileSnapshot)
        return info
      }

      existingTask.task.cancel()
      infoLoadTasks[url] = nil
    }

    let loadTaskID = UUID()
    let task = Task.detached(priority: .userInitiated) { () throws -> ImageInfo in
      try Task.checkCancellation()
      let info = ImageInfo(url: url)
      try Task.checkCancellation()
      return info
    }
    infoLoadTasks[url] = ImageInfoLoadTask(
      id: loadTaskID,
      fileSnapshot: fileSnapshot,
      task: task,
      requestIDs: requestID.map { [$0] } ?? [],
      uncancellableWaiterCount: requestID == nil ? 1 : 0,
    )

    do {
      let info = try await value(of: task, requestID: requestID)
      if infoLoadTasks[url]?.id == loadTaskID {
        infoLoadTasks[url] = nil
      }
      try Task.checkCancellation()
      cacheInfo(info, for: url, cacheKey: cacheKey, fileSnapshot: fileSnapshot)
      return info
    } catch {
      if shouldRemoveInfoTask(at: url, id: loadTaskID, after: error) {
        infoLoadTasks[url] = nil
      }
      throw error
    }
  }

  func loadImage(from url: URL, requestID: LoadRequestID? = nil) async throws -> ImageContainer {
    try validateFileExists(at: url)

    guard Self.isSupportedImage(url) else {
      throw ImageLoadingError.unsupportedImageType(url)
    }

    guard let fileSnapshot = FileSnapshot(url: url) else {
      throw ImageLoadingError.failedToLoad(url)
    }

    let cacheKey = url as NSURL
    if let cachedImage = imageCache.object(forKey: cacheKey) {
      if cachedImage.fileSnapshot == fileSnapshot {
        return cachedImage.imageContainer
      }

      imageCache.removeObject(forKey: cacheKey)
    }

    if let existingTask = imageLoadTasks[url] {
      if existingTask.fileSnapshot == fileSnapshot {
        registerImageWaiter(requestID, for: url)
        let imageContainer = try await value(of: existingTask.task, requestID: requestID)
        try Task.checkCancellation()
        cacheImage(imageContainer, for: url, cacheKey: cacheKey, fileSnapshot: fileSnapshot)
        return imageContainer
      }

      existingTask.task.cancel()
      imageLoadTasks[url] = nil
    }

    let loadTaskID = UUID()
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
    imageLoadTasks[url] = ImageContainerLoadTask(
      id: loadTaskID,
      fileSnapshot: fileSnapshot,
      task: task,
      requestIDs: requestID.map { [$0] } ?? [],
      uncancellableWaiterCount: requestID == nil ? 1 : 0,
    )

    do {
      let imageContainer = try await value(of: task, requestID: requestID)
      if imageLoadTasks[url]?.id == loadTaskID {
        imageLoadTasks[url] = nil
      }
      try Task.checkCancellation()
      cacheImage(imageContainer, for: url, cacheKey: cacheKey, fileSnapshot: fileSnapshot)
      return imageContainer
    } catch {
      if shouldRemoveImageTask(at: url, id: loadTaskID, after: error) {
        imageLoadTasks[url] = nil
      }
      throw error
    }
  }

  func cancelLoads(for requestID: LoadRequestID) {
    for (url, var loadTask) in infoLoadTasks where loadTask.requestIDs.contains(requestID) {
      loadTask.requestIDs.remove(requestID)
      if loadTask.requestIDs.isEmpty, loadTask.uncancellableWaiterCount == 0 {
        loadTask.task.cancel()
        infoLoadTasks[url] = nil
      } else {
        infoLoadTasks[url] = loadTask
      }
    }

    for (url, var loadTask) in imageLoadTasks where loadTask.requestIDs.contains(requestID) {
      loadTask.requestIDs.remove(requestID)
      if loadTask.requestIDs.isEmpty, loadTask.uncancellableWaiterCount == 0 {
        loadTask.task.cancel()
        imageLoadTasks[url] = nil
      } else {
        imageLoadTasks[url] = loadTask
      }
    }
  }

  private func registerInfoWaiter(_ requestID: LoadRequestID?, for url: URL) {
    guard var loadTask = infoLoadTasks[url] else { return }

    if let requestID {
      loadTask.requestIDs.insert(requestID)
    } else {
      loadTask.uncancellableWaiterCount += 1
    }
    infoLoadTasks[url] = loadTask
  }

  private func registerImageWaiter(_ requestID: LoadRequestID?, for url: URL) {
    guard var loadTask = imageLoadTasks[url] else { return }

    if let requestID {
      loadTask.requestIDs.insert(requestID)
    } else {
      loadTask.uncancellableWaiterCount += 1
    }
    imageLoadTasks[url] = loadTask
  }

  private func cacheInfo(
    _ info: ImageInfo,
    for url: URL,
    cacheKey: NSURL,
    fileSnapshot: FileSnapshot,
  ) {
    if FileSnapshot(url: url) == fileSnapshot {
      infoCache.setObject(
        ImageInfoBox(info: info, fileSnapshot: fileSnapshot),
        forKey: cacheKey,
      )
    }
  }

  private func cacheImage(
    _ imageContainer: ImageContainer,
    for url: URL,
    cacheKey: NSURL,
    fileSnapshot: FileSnapshot,
  ) {
    if FileSnapshot(url: url) == fileSnapshot {
      imageCache.setObject(
        ImageContainerBox(imageContainer: imageContainer, fileSnapshot: fileSnapshot),
        forKey: cacheKey,
        cost: imageContainer.cacheCost,
      )
    }
  }

  private func validateFileExists(at url: URL) throws {
    guard url.fileExists else {
      removeCachedValues(for: url)
      throw ImageLoadingError.fileNotFound(url)
    }
  }

  private func removeCachedValues(for url: URL) {
    let cacheKey = url as NSURL
    infoCache.removeObject(forKey: cacheKey)
    imageCache.removeObject(forKey: cacheKey)
    infoLoadTasks[url]?.task.cancel()
    infoLoadTasks[url] = nil
    imageLoadTasks[url]?.task.cancel()
    imageLoadTasks[url] = nil
  }

  private func shouldRemoveInfoTask(at url: URL, id: UUID, after error: Error) -> Bool {
    guard let loadTask = infoLoadTasks[url], loadTask.id == id else {
      return false
    }

    return !isCurrentTaskCancellation(error) || !loadTask.hasWaiters
  }

  private func shouldRemoveImageTask(at url: URL, id: UUID, after error: Error) -> Bool {
    guard let loadTask = imageLoadTasks[url], loadTask.id == id else {
      return false
    }

    return !isCurrentTaskCancellation(error) || !loadTask.hasWaiters
  }

  private func isCurrentTaskCancellation(_ error: Error) -> Bool {
    Task.isCancelled && error is CancellationError
  }

  private func value<T>(of task: Task<T, Error>, requestID: LoadRequestID?) async throws -> T {
    try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      guard let requestID else { return }

      Task {
        await self.cancelLoads(for: requestID)
      }
    }
  }

  private nonisolated static func loadBitmap(from url: URL) -> ImageContainer? {
    guard let imageData = try? Data(contentsOf: url),
          let nsImage = NSImage(data: imageData)
    else { return nil }

    return ImageContainer(url: url, nsImage: nsImage)
  }

  private nonisolated static func loadSVG(from url: URL) -> ImageContainer? {
    guard let imageData = try? Data(contentsOf: url),
          let sourceImage = NSImage(data: imageData)
    else { return nil }

    let documentSize = String(data: imageData, encoding: .utf8)
      .map(SVGDocumentSize.init(svgString:))
    let pixelSize = documentSize?.bestSize ?? sourceImage.size.validSize

    guard let nsImage = rasterizedSVGImage(from: sourceImage, pixelSize: pixelSize) else {
      return nil
    }

    return ImageContainer(url: url, nsImage: nsImage, pixelSize: pixelSize)
  }

  private nonisolated static func rasterizedSVGImage(
    from sourceImage: NSImage,
    pixelSize: NSSize,
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
