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
  case permissionDenied(URL)
  case ioFailure(URL, String)
  case corruptImage(URL)
  case sizeLimitExceeded(URL)
  case invalidDimensions(URL)
  case cancelled

  var errorDescription: String? {
    switch self {
    case let .unsupportedImageType(url):
      """
      Unsupported image type for: \(url.filePath).
      Supported types: \(ImageLoader.supportedImageExtensionsDescription).
      """
    case let .fileNotFound(url):
      "The file no longer exists: \(url.filePath)"
    case let .permissionDenied(url):
      "Imaxe does not have permission to read: \(url.filePath)"
    case let .ioFailure(url, message):
      "Could not read \(url.filePath): \(message)"
    case let .corruptImage(url):
      "The image file is damaged or uses unsupported content: \(url.filePath)"
    case let .sizeLimitExceeded(url):
      "The image is too large to open safely: \(url.filePath)"
    case let .invalidDimensions(url):
      "The image has invalid or missing dimensions: \(url.filePath)"
    case .cancelled:
      "Image loading was cancelled."
    }
  }
}

actor ImageLoader {
  private final nonisolated class ImageMetadataBox {
    let metadata: ImageMetadata
    let fileSnapshot: FileSnapshot

    init(metadata: ImageMetadata, fileSnapshot: FileSnapshot) {
      self.metadata = metadata
      self.fileSnapshot = fileSnapshot
    }
  }

  private final nonisolated class ImageDocumentBox {
    let document: ImageDocument

    init(document: ImageDocument) {
      self.document = document
    }
  }

  private struct ImageMetadataLoadTask {
    let id: UUID
    let fileSnapshot: FileSnapshot
    let task: Task<ImageMetadata, Error>
    var requestIDs: Set<LoadRequestID>
    var uncancellableWaiterCount: Int

    var hasWaiters: Bool {
      !requestIDs.isEmpty || uncancellableWaiterCount > 0
    }
  }

  private struct ImageDocumentLoadTask {
    let id: UUID
    let fileSnapshot: FileSnapshot
    let task: Task<ImageDocument, Error>
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

  private var metadataCache = NSCache<NSURL, ImageMetadataBox>()
  private var documentCache = NSCache<NSURL, ImageDocumentBox>()
  private var metadataLoadTasks: [URL: ImageMetadataLoadTask] = [:]
  private var documentLoadTasks: [URL: ImageDocumentLoadTask] = [:]

  private init() {
    metadataCache.name = "com.imaxe.Imaxe.metadataCache"
    metadataCache.countLimit = 500

    documentCache.name = "com.imaxe.Imaxe.documentCache"
    documentCache.countLimit = 50
    documentCache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
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

  nonisolated static var supportedImageUTTypesDescription: String {
    supportedImageTypes.map(\.identifier).joined(separator: ", ")
  }

  nonisolated static func isSupportedImage(_ url: URL) -> Bool {
    imageTypes(for: url).contains { type in
      supportedImageTypes.contains { type.conforms(to: $0) }
    }
  }

  nonisolated static func isSVG(_ url: URL) -> Bool {
    actualImageType(for: url) == nil
      && imageTypes(for: url).contains { $0.conforms(to: .svg) }
  }

  /// Returns true if the image size exceeds the maximum allowed dimensions or pixel count.
  nonisolated static func exceedsImageSizeLimit(_ size: NSSize) -> Bool {
    guard size.width.isFinite, size.height.isFinite,
          size.width > 0, size.height > 0
    else { return false }

    return size.width > Constants.maximumImageDimension
      || size.height > Constants.maximumImageDimension
      || size.width * size.height > Constants.maximumImagePixelCount
  }

  nonisolated static func imageTypes(for url: URL) -> [UTType] {
    var imageTypes: [UTType] = []

    if let extensionType = url.utType {
      imageTypes.append(extensionType)
    }

    if let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
      imageTypes.append(resourceType)
    }

    if let actualType = actualImageType(for: url) {
      imageTypes.append(actualType)
    }

    return imageTypes
  }

  nonisolated static func actualImageType(for url: URL) -> UTType? {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let identifier = CGImageSourceGetType(imageSource) as String?
    else { return nil }

    return UTType(identifier)
  }

  func loadMetadata(
    from url: URL,
    requestID: LoadRequestID? = nil,
  ) async throws -> ImageMetadata {
    try validateFileExists(at: url)

    guard Self.isSupportedImage(url) else {
      throw ImageLoadingError.unsupportedImageType(url)
    }

    guard let fileSnapshot = FileSnapshot(url: url) else {
      throw ImageLoadingError.ioFailure(url, "Unable to read file attributes.")
    }

    let cacheKey = url as NSURL
    if let cachedMetadata = metadataCache.object(forKey: cacheKey) {
      if cachedMetadata.fileSnapshot == fileSnapshot {
        return cachedMetadata.metadata
      }

      metadataCache.removeObject(forKey: cacheKey)
    }

    if let existingTask = metadataLoadTasks[url] {
      if existingTask.fileSnapshot == fileSnapshot {
        registerMetadataWaiter(requestID, for: url)
        let metadata = try await value(of: existingTask.task, requestID: requestID)
        try Task.checkCancellation()
        cacheMetadata(metadata, for: url, cacheKey: cacheKey, fileSnapshot: fileSnapshot)
        return metadata
      }

      existingTask.task.cancel()
      metadataLoadTasks[url] = nil
    }

    let loadTaskID = UUID()
    let task = Task.detached(priority: .userInitiated) { () throws -> ImageMetadata in
      try Task.checkCancellation()
      let metadata = try ImageMetadata(url: url)
      try Task.checkCancellation()
      return metadata
    }
    metadataLoadTasks[url] = ImageMetadataLoadTask(
      id: loadTaskID,
      fileSnapshot: fileSnapshot,
      task: task,
      requestIDs: requestID.map { [$0] } ?? [],
      uncancellableWaiterCount: requestID == nil ? 1 : 0,
    )

    do {
      let metadata = try await value(of: task, requestID: requestID)
      if metadataLoadTasks[url]?.id == loadTaskID {
        metadataLoadTasks[url] = nil
      }
      try Task.checkCancellation()
      cacheMetadata(metadata, for: url, cacheKey: cacheKey, fileSnapshot: fileSnapshot)
      return metadata
    } catch {
      if shouldRemoveMetadataTask(at: url, id: loadTaskID, after: error) {
        metadataLoadTasks[url] = nil
      }
      throw Self.normalizedError(error, for: url)
    }
  }

  func loadDocument(
    from url: URL,
    requestID: LoadRequestID? = nil,
  ) async throws -> ImageDocument {
    try validateFileExists(at: url)

    guard Self.isSupportedImage(url) else {
      throw ImageLoadingError.unsupportedImageType(url)
    }

    guard let fileSnapshot = FileSnapshot(url: url) else {
      throw ImageLoadingError.ioFailure(url, "Unable to read file attributes.")
    }

    let cacheKey = url as NSURL
    if let cachedDocument = documentCache.object(forKey: cacheKey) {
      if cachedDocument.document.fileSnapshot == fileSnapshot {
        return cachedDocument.document
      }

      documentCache.removeObject(forKey: cacheKey)
    }

    if let existingTask = documentLoadTasks[url] {
      if existingTask.fileSnapshot == fileSnapshot {
        registerDocumentWaiter(requestID, for: url)
        let document = try await value(of: existingTask.task, requestID: requestID)
        try Task.checkCancellation()
        cacheDocument(document, for: url, cacheKey: cacheKey, fileSnapshot: fileSnapshot)
        return document
      }

      existingTask.task.cancel()
      documentLoadTasks[url] = nil
    }

    let loadTaskID = UUID()
    let task = Task.detached(priority: .userInitiated) { () throws -> ImageDocument in
      try Task.checkCancellation()
      let document: ImageDocument = if Self.isSVG(url) {
        try Self.loadSVG(from: url, fileSnapshot: fileSnapshot)
      } else {
        try Self.loadBitmap(from: url, fileSnapshot: fileSnapshot)
      }

      try Task.checkCancellation()
      return document
    }
    documentLoadTasks[url] = ImageDocumentLoadTask(
      id: loadTaskID,
      fileSnapshot: fileSnapshot,
      task: task,
      requestIDs: requestID.map { [$0] } ?? [],
      uncancellableWaiterCount: requestID == nil ? 1 : 0,
    )

    do {
      let document = try await value(of: task, requestID: requestID)
      if documentLoadTasks[url]?.id == loadTaskID {
        documentLoadTasks[url] = nil
      }
      try Task.checkCancellation()
      cacheDocument(document, for: url, cacheKey: cacheKey, fileSnapshot: fileSnapshot)
      return document
    } catch {
      if shouldRemoveDocumentTask(at: url, id: loadTaskID, after: error) {
        documentLoadTasks[url] = nil
      }
      throw Self.normalizedError(error, for: url)
    }
  }

  func cancelLoads(for requestID: LoadRequestID) {
    for (url, var loadTask) in metadataLoadTasks where loadTask.requestIDs.contains(requestID) {
      loadTask.requestIDs.remove(requestID)
      if loadTask.requestIDs.isEmpty, loadTask.uncancellableWaiterCount == 0 {
        loadTask.task.cancel()
        metadataLoadTasks[url] = nil
      } else {
        metadataLoadTasks[url] = loadTask
      }
    }

    for (url, var loadTask) in documentLoadTasks where loadTask.requestIDs.contains(requestID) {
      loadTask.requestIDs.remove(requestID)
      if loadTask.requestIDs.isEmpty, loadTask.uncancellableWaiterCount == 0 {
        loadTask.task.cancel()
        documentLoadTasks[url] = nil
      } else {
        documentLoadTasks[url] = loadTask
      }
    }
  }

  private func registerMetadataWaiter(_ requestID: LoadRequestID?, for url: URL) {
    guard var loadTask = metadataLoadTasks[url] else { return }

    if let requestID {
      loadTask.requestIDs.insert(requestID)
    } else {
      loadTask.uncancellableWaiterCount += 1
    }
    metadataLoadTasks[url] = loadTask
  }

  private func registerDocumentWaiter(_ requestID: LoadRequestID?, for url: URL) {
    guard var loadTask = documentLoadTasks[url] else { return }

    if let requestID {
      loadTask.requestIDs.insert(requestID)
    } else {
      loadTask.uncancellableWaiterCount += 1
    }
    documentLoadTasks[url] = loadTask
  }

  private func cacheMetadata(
    _ metadata: ImageMetadata,
    for url: URL,
    cacheKey: NSURL,
    fileSnapshot: FileSnapshot,
  ) {
    if FileSnapshot(url: url) == fileSnapshot {
      metadataCache.setObject(
        ImageMetadataBox(metadata: metadata, fileSnapshot: fileSnapshot),
        forKey: cacheKey,
      )
    }
  }

  private func cacheDocument(
    _ document: ImageDocument,
    for url: URL,
    cacheKey: NSURL,
    fileSnapshot: FileSnapshot,
  ) {
    if FileSnapshot(url: url) == fileSnapshot {
      documentCache.setObject(
        ImageDocumentBox(document: document),
        forKey: cacheKey,
        cost: document.cacheCost,
      )
    }
  }

  private func validateFileExists(at url: URL) throws {
    guard url.fileExists else {
      removeCachedValues(for: url)
      throw ImageLoadingError.fileNotFound(url)
    }

    guard FileManager.default.isReadableFile(atPath: url.filePath) else {
      removeCachedValues(for: url)
      throw ImageLoadingError.permissionDenied(url)
    }
  }

  private func removeCachedValues(for url: URL) {
    let cacheKey = url as NSURL
    metadataCache.removeObject(forKey: cacheKey)
    documentCache.removeObject(forKey: cacheKey)
    metadataLoadTasks[url]?.task.cancel()
    metadataLoadTasks[url] = nil
    documentLoadTasks[url]?.task.cancel()
    documentLoadTasks[url] = nil
  }

  private func shouldRemoveMetadataTask(at url: URL, id: UUID, after error: Error) -> Bool {
    guard let loadTask = metadataLoadTasks[url], loadTask.id == id else {
      return false
    }

    return !isCurrentTaskCancellation(error) || !loadTask.hasWaiters
  }

  private func shouldRemoveDocumentTask(at url: URL, id: UUID, after error: Error) -> Bool {
    guard let loadTask = documentLoadTasks[url], loadTask.id == id else {
      return false
    }

    return !isCurrentTaskCancellation(error) || !loadTask.hasWaiters
  }

  private func isCurrentTaskCancellation(_ error: Error) -> Bool {
    guard Task.isCancelled else { return false }

    if error is CancellationError {
      return true
    }

    if let imageLoadingError = error as? ImageLoadingError,
       case .cancelled = imageLoadingError
    {
      return true
    }

    return false
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

  private nonisolated static func loadBitmap(
    from url: URL,
    fileSnapshot: FileSnapshot,
  ) throws -> ImageDocument {
    let freshURL = url.freshFileURL
    guard let imageSource = CGImageSourceCreateWithURL(freshURL as CFURL, nil) else {
      throw ImageLoadingError.corruptImage(freshURL)
    }
    let metadata = try ImageMetadata(bitmapURL: freshURL, imageSource: imageSource)

    let imageData: Data
    do {
      imageData = try Data(contentsOf: freshURL, options: [.mappedIfSafe, .uncached])
    } catch {
      throw normalizedError(error, for: freshURL)
    }

    guard let nsImage = NSImage(data: imageData) else {
      throw ImageLoadingError.corruptImage(freshURL)
    }

    let content: ImageContent = if metadata.isAnimated,
                                   nsImage.animatedGIFRepresentation != nil
    {
      .animatedGIF(nsImage, data: imageData)
    } else {
      .staticBitmap(nsImage)
    }

    return ImageDocument(
      url: freshURL,
      fileSnapshot: fileSnapshot,
      metadata: metadata,
      content: content,
    )
  }

  private nonisolated static func loadSVG(
    from url: URL,
    fileSnapshot: FileSnapshot,
  ) throws -> ImageDocument {
    let freshURL = url.freshFileURL
    let imageData: Data
    do {
      imageData = try Data(contentsOf: freshURL, options: [.mappedIfSafe, .uncached])
    } catch {
      throw normalizedError(error, for: freshURL)
    }
    let metadata = try ImageMetadata(svgURL: freshURL, data: imageData)

    guard let sourceImage = NSImage(data: imageData) else {
      throw ImageLoadingError.corruptImage(freshURL)
    }

    let pixelSize = metadata.displayPixelSize.nsSize

    guard let nsImage = rasterizedSVGImage(from: sourceImage, pixelSize: pixelSize) else {
      throw ImageLoadingError.corruptImage(freshURL)
    }

    return ImageDocument(
      url: freshURL,
      fileSnapshot: fileSnapshot,
      metadata: metadata,
      content: .svg(nsImage),
    )
  }

  private nonisolated static func normalizedError(
    _ error: Error,
    for url: URL,
  ) -> ImageLoadingError {
    if error is CancellationError {
      return .cancelled
    }

    if let imageLoadingError = error as? ImageLoadingError {
      return imageLoadingError
    }

    let error = error as NSError
    if error.domain == NSCocoaErrorDomain {
      switch CocoaError.Code(rawValue: error.code) {
      case .fileNoSuchFile:
        return .fileNotFound(url)
      case .fileReadNoPermission, .fileWriteNoPermission:
        return .permissionDenied(url)
      default:
        break
      }
    }

    if error.domain == NSPOSIXErrorDomain, error.code == Int(EACCES) || error.code == Int(EPERM) {
      return .permissionDenied(url)
    }

    return .ioFailure(url, error.localizedDescription)
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
    metadataCache.removeAllObjects()
    documentCache.removeAllObjects()
  }
}
