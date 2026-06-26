//
//  ImageSession.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/17.
//

import SwiftUI

@Observable
final class ImageSession {
  private(set) var currentImage: LoadedImage?
  var isImporterPresented = false
  private(set) var isLoading = false
  private(set) var loadingImageInfo: ImageInfo?
  var imageScale: CGFloat = 1.0
  private(set) var fitToWindowRequest = 0
  private(set) var fitWindowToImageRequest = 0
  private(set) var applyLoadedImageWindowSizeRequest = 0
  private(set) var isWindowPinned = false
  var alwaysFitToWindow = true
  private(set) var showTopBar = false
  private(set) var folderNavigator: FolderNavigator?

  var alert: ImageAlert?
  @ObservationIgnored private weak var owningWindow: NSWindow?
  @ObservationIgnored private var topBarHideTask: Task<Void, Never>?
  @ObservationIgnored private var imageLoadTask: Task<Void, Never>?
  @ObservationIgnored private var imageLoadRequestID = 0

  init(loadedImage: LoadedImage? = nil) {
    currentImage = loadedImage
    folderNavigator = loadedImage.map { FolderNavigator(for: $0.info.sourceURL) }
  }

  deinit {
    topBarHideTask?.cancel()
    imageLoadTask?.cancel()
  }

  func setTopBarVisibility(to isVisible: Bool, in window: NSWindow? = nil) {
    if let window {
      bindWindow(window)
    }

    topBarHideTask?.cancel()

    if !isVisible {
      topBarHideTask = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(Constants.topBarHideDelay))
        guard !Task.isCancelled else { return }

        self?.applyTopBarVisibility(false)
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

  func fitToWindow() {
    DispatchQueue.main.async {
      self.alwaysFitToWindow = true
      self.fitToWindowRequest += 1
    }
  }

  func fitWindowToImage() {
    DispatchQueue.main.async {
      self.fitWindowToImageRequest += 1
    }
  }

  func applyLoadedImageWindowSize() {
    DispatchQueue.main.async {
      self.applyLoadedImageWindowSizeRequest += 1
    }
  }

  func setScale(_ newScale: CGFloat) {
    guard newScale.isFinite else { return }

    alwaysFitToWindow = false
    imageScale = newScale.clamped(to: Constants.imageScaleRange)
  }

  func zoomIn() {
    setScale(imageScale * Constants.imageZoomStep)
  }

  func zoomOut() {
    setScale(imageScale / Constants.imageZoomStep)
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
    imageLoadRequestID += 1
    let requestID = imageLoadRequestID
    let previousImage = currentImage
    let previousFolderNavigator = folderNavigator

    isLoading = true
    loadingImageInfo = ImageInfo(url: url)
    folderNavigator = FolderNavigator(for: url)
    currentImage = nil

    imageLoadTask = Task { @MainActor [weak self] in
      guard let self, requestID == imageLoadRequestID, !Task.isCancelled else { return }

      defer {
        isLoading = false
      }

      do {
        let loadedImage = try await ImageLoader.shared.load(from: url)
        loadingImageInfo = nil
        imageScale = 1.0
        alwaysFitToWindow = false
        applyLoadedImageWindowSizeRequest += 1
        currentImage = loadedImage
      } catch {
        loadingImageInfo = nil
        currentImage = previousImage
        folderNavigator = previousFolderNavigator
        alert = ImageAlert(
          title: failureTitle ?? "Failed to Load Image",
          message: error.localizedDescription,
        )
      }
    }
  }
}
