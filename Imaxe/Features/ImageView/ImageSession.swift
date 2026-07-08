//
//  ImageSession.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/17.
//

import AppKit
import SwiftUI

struct ImageAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}

@Observable
final class ImageSession {
  private(set) var currentImage: ImageContainer?
  private(set) var currentImageInfo: ImageInfo?
  var isImporterPresented = false
  private(set) var isLoading = false
  var zoomScale: CGFloat = 1.0
  private(set) var isWindowPinned = false
  var alwaysFitToWindow = true
  private(set) var shouldApplyLoadedImageWindowSize = true
  private(set) var showTopBar = false
  private(set) var folderNavigator: FolderNavigator?
  var recentImages: [RecentImage] = []

  var topBarHideDelay: TimeInterval = AppSettings.Defaults.topBarHideDelay

  var enableLoopBrowsing: Bool = AppSettings.Defaults.enableLoopBrowsing {
    didSet {
      folderNavigator?.enableLoopBrowsing = enableLoopBrowsing
    }
  }

  var actionOnImageFileChange = AppSettings.Defaults.actionOnImageFileChange {
    didSet {
      updateImageFileWatcher()
    }
  }

  var alert: ImageAlert?
  @ObservationIgnored private weak var owningWindow: NSWindow?
  @ObservationIgnored let viewportController = ImageViewportController()
  @ObservationIgnored private var topBarHideTask: Task<Void, Never>?
  @ObservationIgnored private var imageLoadTask: Task<Void, Never>?
  @ObservationIgnored private var folderLoadTask: Task<Void, Never>?
  @ObservationIgnored private var activeImageLoad = ImageLoadOperation()
  @ObservationIgnored private var imageFileWatcher: ImageFileWatcher?
  @ObservationIgnored var recordRecentImage: ((URL) -> Void)?

  init(imageContainer: ImageContainer? = nil) {
    if let imageContainer {
      currentImage = imageContainer
      currentImageInfo = ImageInfo(url: imageContainer.url)
      folderNavigator = FolderNavigator(
        for: imageContainer.url,
        enableLoopBrowsing: enableLoopBrowsing,
      )
    }
  }

  deinit {
    topBarHideTask?.cancel()
    imageLoadTask?.cancel()
    folderLoadTask?.cancel()
    let requestID = activeImageLoad.requestID
    Task {
      await ImageLoader.shared.cancelLoads(for: requestID)
    }
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
    let pasteboard = NSPasteboard.general

    if let imageType = pasteboard.availableType(from: [.fileURL, .URL, .png, .tiff]) {
      switch imageType {
      case .fileURL:
        if let fileURLString = pasteboard.string(forType: .fileURL),
           let fileURL = URL(string: fileURLString)
        {
          loadImage(
            from: fileURL,
            failureTitle: "Failed to Load Image from Pasteboard",
            addToRecent: false,
          )
        }
      case .URL:
        if let urlString = pasteboard.string(forType: .URL),
           let url = URL(string: urlString)
        {
          loadImage(
            from: url,
            failureTitle: "Failed to Load Image from Pasteboard",
            addToRecent: false,
          )
        }
      case .png, .tiff:
        if let data = pasteboard.data(forType: imageType),
           let tempDirectory = FileManager.default.tempDirectory
        {
          let tempFileURL = tempDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(imageType == .png ? "png" : "tiff")
          do {
            try data.write(to: tempFileURL)
            loadImage(
              from: tempFileURL,
              failureTitle: "Failed to Load Image from Pasteboard",
              addToRecent: false,
            )
          } catch {
            alert = ImageAlert(
              title: "Failed to Load Image from Pasteboard",
              message: error.localizedDescription,
            )
          }
        }
      default:
        break
      }
    }
  }

  func onOpenImage(result: Result<URL, Error>) {
    switch result {
    case let .success(url):
      loadImage(from: url, failureTitle: "Failed to Open Image")
    case let .failure(error):
      alert = ImageAlert(title: "Failed to Open Image", message: error.localizedDescription)
    }
  }

  func reloadCurrentImage() {
    guard let folderNavigator else { return }
    loadImage(from: folderNavigator.currentImageURL)
  }

  func navigateToPreviousImage() {
    let success = folderNavigator?.moveToPrevious() ?? false
    if success {
      reloadCurrentImage()
    }
  }

  func navigateToNextImage() {
    let success = folderNavigator?.moveToNext() ?? false
    if success {
      reloadCurrentImage()
    }
  }

  func loadImage(
    from url: URL,
    failureTitle: String? = nil,
    addToRecent: Bool = true,
    preservingViewportOnReload: Bool = false,
  ) {
    let previousImage = currentImage
    let previousImageInfo = currentImageInfo
    let previousFolderNavigator = folderNavigator
    let shouldPreserveCurrentImage = preservingViewportOnReload
      && currentImage != nil
      && currentImageInfo != nil
    cancelCurrentImageLoad()
    imageFileWatcher = nil
    let imageLoad = ImageLoadOperation()
    activeImageLoad = imageLoad

    isLoading = true
    shouldApplyLoadedImageWindowSize = !shouldPreserveCurrentImage
    if !shouldPreserveCurrentImage {
      currentImage = nil
      currentImageInfo = nil
    }
    folderNavigator = FolderNavigator(
      for: url,
      enableLoopBrowsing: enableLoopBrowsing,
      imageURLs: initialImageURLs(from: previousFolderNavigator, for: url),
    )
    loadFolderNavigator(for: url, imageLoad: imageLoad)

    imageLoadTask = Task { @MainActor [weak self] in
      guard let self, imageLoad === activeImageLoad, !Task.isCancelled else { return }

      defer {
        if imageLoad === activeImageLoad {
          isLoading = false
        }
      }

      await withTaskGroup(of: ImageLoadEvent.self) { group in
        group.addTask {
          await .info(Self.loadInfoResult(from: url, requestID: imageLoad.requestID))
        }
        group.addTask {
          await .image(Self.loadImageResult(from: url, requestID: imageLoad.requestID))
        }

        for await event in group {
          guard imageLoad === activeImageLoad, !Task.isCancelled else {
            group.cancelAll()
            return
          }

          switch event {
          case let .info(.success(info)):
            currentImageInfo = info

          case .info(.failure):
            break

          case let .image(.success(imageContainer)):
            if currentImageInfo == nil {
              currentImageInfo = try? await ImageLoader.shared.loadInfo(
                from: url,
                requestID: imageLoad.requestID,
              )
            }
            currentImage = imageContainer
            updateImageFileWatcher()
            if addToRecent {
              recordRecentImage?(url)
            }

          case let .image(.failure(error)):
            group.cancelAll()
            folderLoadTask?.cancel()
            currentImage = previousImage
            currentImageInfo = previousImageInfo
            folderNavigator = previousFolderNavigator
            updateImageFileWatcher()
            alert = ImageAlert(
              title: failureTitle ?? "Failed to Load Image",
              message: error.localizedDescription,
            )
            return
          }
        }
      }
    }
  }

  private enum ImageLoadEvent {
    case info(Result<ImageInfo, Error>)
    case image(Result<ImageContainer, Error>)
  }

  private final class ImageLoadOperation {
    let requestID = ImageLoader.LoadRequestID()
  }

  private func cancelCurrentImageLoad() {
    imageLoadTask?.cancel()
    folderLoadTask?.cancel()
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

  private func loadFolderNavigator(for url: URL, imageLoad: ImageLoadOperation) {
    folderLoadTask = Task { @MainActor [weak self] in
      guard let self else { return }

      guard let imageURLs = await FolderNavigator.imageURLs(for: url),
            imageLoad === activeImageLoad,
            folderNavigator?.currentImageURL == url,
            !Task.isCancelled
      else { return }

      folderNavigator?.replaceImageURLs(imageURLs)
    }
  }

  private func updateImageFileWatcher() {
    imageFileWatcher = nil

    guard actionOnImageFileChange == .reload,
          let url = folderNavigator?.currentImageURL,
          currentImage != nil
    else { return }

    imageFileWatcher = ImageFileWatcher(url: url) { [weak self] in
      guard let self,
            folderNavigator?.currentImageURL == url
      else { return }

      loadImage(from: url, preservingViewportOnReload: true)
    }
  }

  private nonisolated static func loadInfoResult(
    from url: URL,
    requestID: ImageLoader.LoadRequestID,
  ) async -> Result<ImageInfo, Error> {
    do {
      return try await .success(ImageLoader.shared.loadInfo(from: url, requestID: requestID))
    } catch {
      return .failure(error)
    }
  }

  private nonisolated static func loadImageResult(
    from url: URL,
    requestID: ImageLoader.LoadRequestID,
  ) async -> Result<ImageContainer, Error> {
    do {
      return try await .success(ImageLoader.shared.loadImage(from: url, requestID: requestID))
    } catch {
      return .failure(error)
    }
  }
}
