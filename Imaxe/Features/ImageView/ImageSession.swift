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
  private(set) var currentImage: ImageContainer?
  private(set) var currentImageInfo: ImageInfo?
  var isImporterPresented = false
  private(set) var isLoading = false
  var imageScale: CGFloat = 1.0
  private(set) var isWindowPinned = false
  var alwaysFitToWindow = true
  private(set) var showTopBar = false
  private(set) var folderNavigator: FolderNavigator?

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
  @ObservationIgnored private var activeImageLoad = ImageLoadOperation()
  @ObservationIgnored private var imageFileWatcher: ImageFileWatcher?

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

  func revealCurrentImageInFinder() {
    if let url = currentImageInfo?.url ?? currentImage?.url {
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

  func setScale(_ newScale: CGFloat) {
    guard newScale.isFinite else { return }

    alwaysFitToWindow = false
    viewportController.setScale(newScale)
  }

  func zoomIn() {
    alwaysFitToWindow = false
    viewportController.scale(by: Constants.imageZoomStep)
  }

  func zoomOut() {
    alwaysFitToWindow = false
    viewportController.scale(by: 1.0 / Constants.imageZoomStep)
  }

  func openImageFromPasteboard() {
    let pasteboard = NSPasteboard.general

    if let imageType = pasteboard.availableType(from: [.fileURL, .URL, .png, .tiff]) {
      switch imageType {
      case .fileURL:
        if let fileURLString = pasteboard.string(forType: .fileURL),
           let fileURL = URL(string: fileURLString)
        {
          loadImage(from: fileURL, failureTitle: "Failed to Load Image from Pasteboard")
        }
      case .URL:
        if let urlString = pasteboard.string(forType: .URL),
           let url = URL(string: urlString)
        {
          loadImage(from: url, failureTitle: "Failed to Load Image from Pasteboard")
        }
      case .png, .tiff:
        if let data = pasteboard.data(forType: imageType),
           let tempDirectory = try? FileManager.default.url(
             for: .itemReplacementDirectory,
             in: .userDomainMask,
             appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
             create: true,
           )
        {
          let tempFileURL = tempDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(imageType == .png ? "png" : "tiff")
          do {
            try data.write(to: tempFileURL)
            loadImage(from: tempFileURL, failureTitle: "Failed to Load Image from Pasteboard")
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

  func loadImage(from url: URL, failureTitle: String? = nil) {
    imageLoadTask?.cancel()
    imageFileWatcher = nil
    let imageLoad = ImageLoadOperation()
    activeImageLoad = imageLoad
    let previousImage = currentImage
    let previousImageInfo = currentImageInfo
    let previousFolderNavigator = folderNavigator

    isLoading = true
    currentImage = nil
    currentImageInfo = nil
    folderNavigator = FolderNavigator(for: url, enableLoopBrowsing: enableLoopBrowsing)

    imageLoadTask = Task { @MainActor [weak self] in
      guard let self, imageLoad === activeImageLoad, !Task.isCancelled else { return }

      defer {
        if imageLoad === activeImageLoad {
          isLoading = false
        }
      }

      await withTaskGroup(of: ImageLoadEvent.self) { group in
        group.addTask {
          await .info(Self.loadInfoResult(from: url))
        }
        group.addTask {
          await .image(Self.loadImageResult(from: url))
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
              currentImageInfo = try? await ImageLoader.shared.loadInfo(from: url)
            }
            currentImage = imageContainer
            updateImageFileWatcher()

          case let .image(.failure(error)):
            group.cancelAll()
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

  private final class ImageLoadOperation {}

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

      loadImage(from: url)
    }
  }

  private nonisolated static func loadInfoResult(from url: URL) async -> Result<ImageInfo, Error> {
    do {
      return try await .success(ImageLoader.shared.loadInfo(from: url))
    } catch {
      return .failure(error)
    }
  }

  private nonisolated static func loadImageResult(
    from url: URL,
  ) async -> Result<ImageContainer, Error> {
    do {
      return try await .success(ImageLoader.shared.loadImage(from: url))
    } catch {
      return .failure(error)
    }
  }
}
