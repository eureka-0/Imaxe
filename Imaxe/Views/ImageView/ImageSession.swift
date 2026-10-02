// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import AppKit
import SwiftUI

@Observable
final class ImageSession {
  struct Preferences: Equatable {
    let topBarHideDelay: TimeInterval
    let enableLoopBrowsing: Bool
    let actionOnImageFileChange: ActionOnImageFileChange
  }

  private(set) var currentDocument: ImageDocument?
  private(set) var currentMetadata: ImageMetadata?
  private(set) var displayedURL: URL?
  private(set) var pendingURL: URL?
  var isImporterPresented = false
  private(set) var isLoading = false
  private(set) var loadingElapsedTime: TimeInterval = 0
  var zoomScale: CGFloat = 1.0
  private(set) var isWindowPinned = false
  var alwaysFitToWindow = true
  private(set) var shouldApplyLoadedImageWindowSize = true
  private(set) var showTopBar = false
  private(set) var folderNavigator: FolderNavigator?

  private(set) var topBarHideDelay: TimeInterval = AppSettings.Defaults.topBarHideDelay

  private(set) var enableLoopBrowsing: Bool = AppSettings.Defaults.enableLoopBrowsing {
    didSet {
      folderNavigator?.enableLoopBrowsing = enableLoopBrowsing
    }
  }

  private(set) var actionOnImageFileChange = AppSettings.Defaults.actionOnImageFileChange {
    didSet {
      updateImageFileWatcher()
    }
  }

  var alertTitle: LocalizedStringResource = ""
  var alertMessage: String?

  var isAlertPresented: Bool {
    get { alertMessage != nil }
    set {
      if !newValue {
        alertTitle = ""
        alertMessage = nil
      }
    }
  }

  @ObservationIgnored private weak var owningWindow: NSWindow?
  @ObservationIgnored let viewportController = ImageViewportController()
  @ObservationIgnored private var topBarHideTask: Task<Void, Never>?
  @ObservationIgnored private var imageLoadTask: Task<Void, Never>?
  @ObservationIgnored private var loadingTimerTask: Task<Void, Never>?
  @ObservationIgnored private weak var loadingTimerOperation: ImageLoadOperation?
  @ObservationIgnored private var activeImageLoad = ImageLoadOperation()
  @ObservationIgnored private var imageFileWatcher: ImageFileWatcher?
  @ObservationIgnored private var displayedTemporaryURL: URL?
  @ObservationIgnored private var pendingTemporaryURL: URL?
  @ObservationIgnored var recordRecentImage: ((URL) async throws -> Void)?
  @ObservationIgnored var removeRecentImage: ((String) throws -> Void)?
  @ObservationIgnored var updateRecentImageLocation: ((String, URL) async throws -> Void)?
  @ObservationIgnored var loadImageMetadata: @Sendable (
    URL,
    ImageLoader.LoadRequestID,
  ) async throws -> ImageMetadata = {
    try await ImageLoader.shared.loadMetadata(from: $0, requestID: $1)
  }

  @ObservationIgnored var loadImageDocument: @Sendable (
    URL,
    ImageLoader.LoadRequestID,
  ) async throws -> ImageDocument = {
    try await ImageLoader.shared.loadDocument(from: $0, requestID: $1)
  }

  @ObservationIgnored var loadFolderImageURLs: @Sendable (URL) async -> [URL]? = {
    await FolderNavigator.imageURLs(for: $0)
  }

  @ObservationIgnored var hasActiveLoadingTimer: Bool {
    loadingTimerTask != nil
  }

  init(imageDocument: ImageDocument? = nil) {
    if let imageDocument {
      currentDocument = imageDocument
      currentMetadata = imageDocument.metadata
      displayedURL = imageDocument.url
      folderNavigator = FolderNavigator(
        for: imageDocument.url,
        enableLoopBrowsing: enableLoopBrowsing,
      )
    }
  }

  func apply(_ preferences: Preferences) {
    topBarHideDelay = preferences.topBarHideDelay
    enableLoopBrowsing = preferences.enableLoopBrowsing
    actionOnImageFileChange = preferences.actionOnImageFileChange
  }

  deinit {
    MainActor.assumeIsolated {
      close()
    }
  }

  func close() {
    topBarHideTask?.cancel()
    topBarHideTask = nil
    cancelCurrentImageLoad()
    imageLoadTask = nil
    removeTemporaryFile(displayedTemporaryURL)
    displayedTemporaryURL = nil
    imageFileWatcher = nil
  }

  func setTopBarVisibility(to isVisible: Bool, in window: NSWindow? = nil) {
    if let window {
      bindWindow(window)
    }

    topBarHideTask?.cancel()

    if !isVisible {
      topBarHideTask = Task { @MainActor [weak self] in
        guard let self else { return }

        try? await Task.sleep(for: .seconds(topBarHideDelay))
        guard !Task.isCancelled else { return }
        applyTopBarVisibility(false)
      }
      return
    }

    applyTopBarVisibility(true)
  }

  func bindWindow(_ window: NSWindow?) {
    guard let window else { return }

    owningWindow = window
    if !showTopBar {
      window.setStandardButtonsVisibility(to: false)
    }
  }

  func restoreStandardWindowButtons() {
    topBarHideTask?.cancel()
    topBarHideTask = nil
    showTopBar = false
    owningWindow?.setStandardButtonsVisibility(to: true)
  }

  private func applyTopBarVisibility(_ isVisible: Bool) {
    showTopBar = isVisible
    owningWindow?.setStandardButtonsVisibility(to: isVisible)
  }

  func toggleWindowPinning() {
    isWindowPinned.toggle()
    owningWindow?.level = isWindowPinned ? .floating : .normal
  }

  func revealInFinder(for urls: [URL]? = nil) {
    if let urls {
      NSWorkspace.shared.activateFileViewerSelecting(urls)
    } else if let url = currentMetadata?.url ?? currentDocument?.url {
      NSWorkspace.shared.activateFileViewerSelecting([url])
    }
  }

  @discardableResult
  static func renameFile(at url: URL, to proposedFileName: String) throws -> URL {
    let fileName = proposedFileName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !fileName.isEmpty,
          fileName != ".",
          fileName != "..",
          !fileName.contains("/"),
          !fileName.contains("\0")
    else {
      throw FileEditingError.invalidFileName
    }

    let destinationURL = url.deletingLastPathComponent()
      .appending(path: fileName, directoryHint: .notDirectory)
    guard destinationURL != url else { return url }

    try FileManager.default.moveItem(at: url, to: destinationURL)
    return destinationURL
  }

  @discardableResult
  func renameCurrentImage(to proposedFileName: String) -> Bool {
    guard let sourceURL = displayedURL, currentDocument != nil, !isLoading else { return false }

    imageFileWatcher = nil
    do {
      let destinationURL = try Self.renameFile(at: sourceURL, to: proposedFileName)
      applyRelocatedCurrentImage(from: sourceURL, to: destinationURL)
      return true
    } catch {
      updateImageFileWatcher()
      alertTitle = "Failed to Rename Item"
      alertMessage = error.localizedDescription
      return false
    }
  }

  @discardableResult
  func moveCurrentImage(to directoryURL: URL) -> Bool {
    guard let sourceURL = displayedURL, currentDocument != nil, !isLoading else {
      appLog("Cannot move image: no current image or image is loading.", level: .debug)
      return false
    }

    imageFileWatcher = nil
    do {
      let resourceValues = try directoryURL.resourceValues(forKeys: [.isDirectoryKey])
      guard resourceValues.isDirectory == true else {
        throw FileEditingError.invalidDirectory
      }

      let destinationURL = directoryURL.appending(
        path: sourceURL.lastPathComponent,
        directoryHint: .notDirectory,
      )
      guard destinationURL != sourceURL else {
        updateImageFileWatcher()
        return true
      }

      try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
      applyRelocatedCurrentImage(from: sourceURL, to: destinationURL)
      return true
    } catch {
      updateImageFileWatcher()
      alertTitle = "Failed to Move Item"
      alertMessage = error.localizedDescription
      return false
    }
  }

  func currentImageTagNames() -> Set<String> {
    guard let url = displayedURL else { return [] }

    do {
      let values = try url.freshResourceValues(forKeys: [.tagNamesKey])
      return Set(values.tagNames ?? [])
    } catch {
      alertTitle = "Failed to Read File Tags"
      alertMessage = error.localizedDescription
      return []
    }
  }

  @discardableResult
  func setCurrentImageTagNames(_ tagNames: Set<String>) -> Bool {
    guard let url = displayedURL else { return false }

    do {
      try (url as NSURL).setResourceValue(tagNames.sorted(), forKey: .tagNamesKey)
      return true
    } catch {
      alertTitle = "Failed to Update File Tags"
      alertMessage = error.localizedDescription
      return false
    }
  }

  func fitToWindow() {
    alwaysFitToWindow = true
    viewportController.fitToWindow()
  }

  func fitWindowToImage() {
    viewportController.fitWindowToImage()
  }

  func setZoomScale(_ newZoomScale: CGFloat) {
    guard newZoomScale.isFinite else { return }

    alwaysFitToWindow = false
    viewportController.setZoomScale(newZoomScale)
  }

  func zoomIn() {
    alwaysFitToWindow = false
    viewportController.zoomIn()
  }

  func zoomOut() {
    alwaysFitToWindow = false
    viewportController.zoomOut()
  }

  func pan(horizontal: CGFloat, vertical: CGFloat) {
    alwaysFitToWindow = false
    viewportController.pan(horizontal: horizontal, vertical: vertical)
  }

  private func applyRelocatedCurrentImage(from sourceURL: URL, to destinationURL: URL) {
    guard sourceURL != destinationURL else {
      updateImageFileWatcher()
      return
    }

    let sourceDirectory = sourceURL.deletingLastPathComponent()
    let destinationDirectory = destinationURL.deletingLastPathComponent()
    let existingImageURLs = folderNavigator?.imageURLs ?? [sourceURL]
    let initialImageURLs = sourceDirectory == destinationDirectory
      ? existingImageURLs.map { $0 == sourceURL ? destinationURL : $0 }
      : [destinationURL]

    displayedURL = destinationURL
    if displayedTemporaryURL == sourceURL {
      displayedTemporaryURL = destinationURL
    }
    if let currentDocument {
      self.currentDocument = currentDocument.relocated(to: destinationURL)
      currentMetadata = self.currentDocument?.metadata
    } else {
      currentMetadata = currentMetadata?.relocated(to: destinationURL)
    }
    folderNavigator = FolderNavigator(
      for: destinationURL,
      enableLoopBrowsing: enableLoopBrowsing,
      imageURLs: initialImageURLs,
    )
    updateImageFileWatcher()

    Task { [weak self] in
      guard let self else { return }
      let imageURLs = await loadFolderImageURLs(destinationURL)
      guard displayedURL == destinationURL, let imageURLs else { return }
      folderNavigator = FolderNavigator(
        for: destinationURL,
        enableLoopBrowsing: enableLoopBrowsing,
        imageURLs: imageURLs,
      )
    }

    guard let updateRecentImageLocation else { return }
    Task { [weak self] in
      do {
        try await updateRecentImageLocation(sourceURL.filePath, destinationURL)
      } catch {
        self?.alertTitle = "Failed to Update Recent Images"
        self?.alertMessage = error.localizedDescription
      }
    }
  }

  func openImageFromPasteboard() {
    do {
      guard let image = try extractImageFromPasteboard() else { return }
      loadImage(
        from: image.url,
        failureTitle: "Failed to Load Image from Pasteboard",
        addToRecent: false,
        temporaryURL: image.temporaryURL,
      )
    } catch {
      alertTitle = "Failed to Load Image from Pasteboard"
      alertMessage = error.localizedDescription
    }
  }

  func onOpenImage(result: Result<[URL], Error>, openWindow: OpenWindowAction? = nil) {
    switch result {
    case let .success(urls):
      if let openWindow {
        for url in urls {
          openWindow(id: "image", value: ImageWindowRequest(url: url))
        }
      } else if let url = urls.first {
        loadImage(from: url, failureTitle: "Failed to Open Image")
      }
    case let .failure(error):
      alertTitle = "Failed to Open Image"
      alertMessage = error.localizedDescription
    }
  }

  func reloadCurrentImage() {
    guard let displayedURL else { return }
    loadImage(from: displayedURL)
  }

  func openRecentImage(_ recentImage: RecentImage) {
    loadImage(
      from: recentImage.url,
      failureTitle: "Failed to Open Recent Image",
      recentImagePathToRemoveOnFileNotFound: recentImage.path,
    )
  }

  func navigateToPreviousImage() {
    guard var candidate = folderNavigator, candidate.moveToPrevious() else { return }
    loadImage(from: candidate.currentImageURL)
  }

  func navigateToNextImage() {
    guard var candidate = folderNavigator, candidate.moveToNext() else { return }
    loadImage(from: candidate.currentImageURL)
  }

  func loadImage(
    from url: URL,
    failureTitle: LocalizedStringResource? = nil,
    addToRecent: Bool = true,
    preservingViewportOnReload: Bool = false,
    recentImagePathToRemoveOnFileNotFound: String? = nil,
    temporaryURL: URL? = nil,
    onFailure: (() -> Void)? = nil,
  ) {
    let shouldPreserveCurrentImage = preservingViewportOnReload
      && currentDocument != nil
    cancelCurrentImageLoad()
    let imageLoad = ImageLoadOperation()
    activeImageLoad = imageLoad

    isLoading = true
    loadingElapsedTime = 0
    pendingURL = url
    pendingTemporaryURL = temporaryURL
    shouldApplyLoadedImageWindowSize = !shouldPreserveCurrentImage

    imageLoadTask = Task { @MainActor [weak self] in
      guard let self, imageLoad === activeImageLoad, !Task.isCancelled else { return }
      startLoadingTimer(for: imageLoad)

      defer {
        imageLoad.metadataTask?.cancel()
        stopLoadingTimer(for: imageLoad)
        if imageLoad === activeImageLoad {
          isLoading = false
          loadingElapsedTime = 0
          pendingURL = nil
          pendingTemporaryURL = nil
        }
      }

      imageLoad.metadataTask = Task { @MainActor [weak self, weak imageLoad] in
        guard let self, let imageLoad else { return }
        let metadataResult = await Self.result {
          try await loadImageMetadata(url, imageLoad.requestID)
        }
        guard imageLoad === activeImageLoad,
              !imageLoad.hasCommittedDocument,
              !Task.isCancelled,
              case let .success(metadata) = metadataResult
        else { return }

        currentMetadata = metadata
      }
      startFolderScan(for: url, imageLoad: imageLoad)
      let document = await Self.result {
        try await loadImageDocument(url, imageLoad.requestID)
      }

      guard imageLoad === activeImageLoad, !Task.isCancelled else {
        removeTemporaryFile(temporaryURL)
        return
      }

      switch document {
      case let .success(imageDocument):
        imageLoad.hasCommittedDocument = true
        imageLoad.metadataTask?.cancel()
        let oldTemporaryURL = displayedTemporaryURL
        currentDocument = imageDocument
        currentMetadata = imageDocument.metadata
        displayedURL = url
        displayedTemporaryURL = temporaryURL
        folderNavigator = FolderNavigator(
          for: url,
          enableLoopBrowsing: enableLoopBrowsing,
          imageURLs: imageLoad.folderURLs ?? initialImageURLs(from: folderNavigator, for: url),
        )
        updateImageFileWatcher()
        if oldTemporaryURL != temporaryURL {
          removeTemporaryFile(oldTemporaryURL)
        }
        if addToRecent {
          do {
            try await recordRecentImage?(url)
            guard imageLoad === activeImageLoad, !Task.isCancelled else { return }
          } catch {
            alertTitle = "Failed to Update Recent Images"
            alertMessage = error.localizedDescription
          }
        }

      case let .failure(error):
        imageLoad.folderTask?.cancel()
        currentMetadata = currentDocument?.metadata
        removeTemporaryFile(temporaryURL)
        handleImageLoadFailure(
          error,
          url: url,
          failureTitle: failureTitle,
          recentImagePathToRemoveOnFileNotFound: recentImagePathToRemoveOnFileNotFound,
        )
        onFailure?()
      }
    }
  }

  private final class ImageLoadOperation {
    let requestID = ImageLoader.LoadRequestID()
    var metadataTask: Task<Void, Never>?
    var folderTask: Task<Void, Never>?
    var folderURLs: [URL]?
    var hasCommittedDocument = false
  }

  private func handleImageLoadFailure(
    _ error: Error,
    url: URL,
    failureTitle: LocalizedStringResource?,
    recentImagePathToRemoveOnFileNotFound: String?,
  ) {
    if let recentImagePathToRemoveOnFileNotFound, Self.isFileNotFound(error) {
      guard let removeRecentImage else {
        alertTitle = "Recent Image Missing"
        alertMessage = "The file no longer exists:\n\(url.filePath)"
        return
      }

      do {
        try removeRecentImage(recentImagePathToRemoveOnFileNotFound)
        alertTitle = "Recent Image Removed"
        alertMessage =
          "The file no longer exists and was removed from Recent Images:\n\(url.filePath)"
      } catch {
        alertTitle = "Failed to Remove Recent Image"
        alertMessage = error.localizedDescription
      }
      return
    }

    alertTitle = failureTitle ?? "Failed to Load Image"
    alertMessage = error.localizedDescription
  }

  private static func isFileNotFound(_ error: Error) -> Bool {
    guard let imageLoadingError = error as? ImageLoadingError else {
      return false
    }

    if case .fileNotFound = imageLoadingError {
      return true
    }

    return false
  }

  private func cancelCurrentImageLoad() {
    imageLoadTask?.cancel()
    activeImageLoad.folderTask?.cancel()
    currentMetadata = currentDocument?.metadata
    stopLoadingTimer(for: activeImageLoad)
    removeTemporaryFile(pendingTemporaryURL)
    pendingTemporaryURL = nil
    let requestID = activeImageLoad.requestID
    Task {
      await ImageLoader.shared.cancelLoads(for: requestID)
    }
  }

  private func startFolderScan(for url: URL, imageLoad: ImageLoadOperation) {
    imageLoad.folderTask = Task { [weak self, weak imageLoad] in
      guard let self, let imageLoad else { return }
      let urls = await loadFolderImageURLs(url)
      guard imageLoad === activeImageLoad, !Task.isCancelled else { return }
      imageLoad.folderURLs = urls
      if imageLoad.hasCommittedDocument, displayedURL == url, let urls {
        folderNavigator = FolderNavigator(
          for: url,
          enableLoopBrowsing: enableLoopBrowsing,
          imageURLs: urls,
        )
      }
    }
  }

  private func initialImageURLs(
    from previousFolderNavigator: FolderNavigator?,
    for url: URL,
  ) -> [URL]? {
    guard previousFolderNavigator?.rootURL == url.deletingLastPathComponent() else {
      return nil
    }

    return previousFolderNavigator?.imageURLs
  }

  private func updateImageFileWatcher() {
    imageFileWatcher = nil

    guard actionOnImageFileChange == .reload,
          let url = displayedURL,
          currentDocument != nil
    else { return }

    imageFileWatcher = ImageFileWatcher(url: url) { [weak self] event in
      guard let self, folderNavigator?.currentImageURL == url else { return }

      switch event {
      case .modified, .replaced, .recreated:
        guard pendingURL == nil else { return }
        loadImage(from: url, preservingViewportOnReload: true)
      case .deleted:
        alertTitle = "Image File Deleted"
        alertMessage = String(localized: "The image file was deleted:\n\(url.filePath)")
      }
    }
  }

  private func startLoadingTimer(for imageLoad: ImageLoadOperation) {
    loadingTimerTask?.cancel()
    loadingTimerOperation = imageLoad
    loadingTimerTask = Task { @MainActor [weak self, weak imageLoad] in
      while let self, let imageLoad, !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(50))
        guard !Task.isCancelled,
              loadingTimerOperation === imageLoad,
              activeImageLoad === imageLoad
        else { return }
        loadingElapsedTime += 0.05
      }
    }
  }

  private func stopLoadingTimer(for imageLoad: ImageLoadOperation) {
    guard loadingTimerOperation === imageLoad else { return }

    loadingTimerTask?.cancel()
    loadingTimerTask = nil
    loadingTimerOperation = nil
    loadingElapsedTime = 0
  }

  private func removeTemporaryFile(_ url: URL?) {
    guard let url else { return }
    try? FileManager.default.removeItem(at: url)
  }

  private static func result<T>(
    _ operation: () async throws -> T,
  ) async -> Result<T, Error> {
    do {
      return try await .success(operation())
    } catch {
      return .failure(error)
    }
  }

  private enum FileEditingError: LocalizedError {
    case invalidDirectory
    case invalidFileName

    var errorDescription: String? {
      switch self {
      case .invalidDirectory:
        "The selected location is not a folder."
      case .invalidFileName:
        "Enter a valid file name."
      }
    }
  }
}
