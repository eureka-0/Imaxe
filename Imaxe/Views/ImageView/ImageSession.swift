//
//  ImageSession.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/17.
//

import AppKit
import SwiftUI

@Observable
final class ImageSession {
  struct Preferences: Equatable {
    let topBarHideDelay: TimeInterval
    let enableLoopBrowsing: Bool
    let actionOnImageFileChange: ActionOnImageFileChange
  }

  private(set) var currentImage: ImageContainer?
  private(set) var currentImageInfo: ImageInfo?
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
  @ObservationIgnored private var activeImageLoad = ImageLoadOperation()
  @ObservationIgnored private var imageFileWatcher: ImageFileWatcher?
  @ObservationIgnored private var displayedTemporaryURL: URL?
  @ObservationIgnored private var pendingTemporaryURL: URL?
  @ObservationIgnored var recordRecentImage: ((URL) async throws -> Void)?
  @ObservationIgnored var removeRecentImage: ((String) throws -> Void)?
  @ObservationIgnored var loadImageInfo: @Sendable (URL, ImageLoader.LoadRequestID) async throws
    -> ImageInfo = {
      try await ImageLoader.shared.loadInfo(from: $0, requestID: $1)
    }

  @ObservationIgnored var loadImageContainer: @Sendable (
    URL,
    ImageLoader.LoadRequestID,
  ) async throws -> ImageContainer = {
    try await ImageLoader.shared.loadImage(from: $0, requestID: $1)
  }

  @ObservationIgnored var loadFolderImageURLs: @Sendable (URL) async -> [URL]? = {
    await FolderNavigator.imageURLs(for: $0)
  }

  init(imageContainer: ImageContainer? = nil) {
    if let imageContainer {
      currentImage = imageContainer
      currentImageInfo = ImageInfo(url: imageContainer.url)
      displayedURL = imageContainer.url
      folderNavigator = FolderNavigator(
        for: imageContainer.url,
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
    } else if let url = currentImageInfo?.url ?? currentImage?.url {
      NSWorkspace.shared.activateFileViewerSelecting([url])
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
      && currentImage != nil
      && currentImageInfo != nil
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

      let timerTask = Task { @MainActor [weak self] in
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(0.05))
          guard let self, !Task.isCancelled else { return }
          loadingElapsedTime += 0.05
        }
      }

      defer {
        timerTask.cancel()
        if imageLoad === activeImageLoad {
          isLoading = false
          loadingElapsedTime = 0
          pendingURL = nil
          pendingTemporaryURL = nil
        }
      }

      async let infoResult = Self.result {
        try await loadImageInfo(url, imageLoad.requestID)
      }
      async let imageResult = Self.result {
        try await loadImageContainer(url, imageLoad.requestID)
      }
      async let imageURLs = loadFolderImageURLs(url)
      let (info, image, folderURLs) = await (infoResult, imageResult, imageURLs)

      guard imageLoad === activeImageLoad, !Task.isCancelled else {
        removeTemporaryFile(temporaryURL)
        return
      }

      switch (info, image) {
      case let (.success(info), .success(imageContainer)):
        let oldTemporaryURL = displayedTemporaryURL
        currentImage = imageContainer
        currentImageInfo = info
        displayedURL = url
        displayedTemporaryURL = temporaryURL
        folderNavigator = FolderNavigator(
          for: url,
          enableLoopBrowsing: enableLoopBrowsing,
          imageURLs: folderURLs ?? initialImageURLs(from: folderNavigator, for: url),
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

      case let (.failure(error), _), let (_, .failure(error)):
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
        alertMessage = "The file no longer exists and was removed from Recent Images:\n\(url.filePath)"
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
    removeTemporaryFile(pendingTemporaryURL)
    pendingTemporaryURL = nil
    let requestID = activeImageLoad.requestID
    Task {
      await ImageLoader.shared.cancelLoads(for: requestID)
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
          currentImage != nil
    else { return }

    imageFileWatcher = ImageFileWatcher(url: url) { [weak self] in
      guard let self,
            folderNavigator?.currentImageURL == url,
            pendingURL == nil
      else { return }

      loadImage(from: url, preservingViewportOnReload: true)
    }
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
}
