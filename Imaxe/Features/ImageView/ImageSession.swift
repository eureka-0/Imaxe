//
//  ImageSession.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/17.
//

import SwiftUI

@Observable
final class ImageSession {
  private(set) var currentImage: LoadedImage
  var imageScale: CGFloat = 1.0
  private(set) var fitToWindowRequest = 0
  private(set) var fitWindowToImageRequest = 0
  private(set) var isWindowPinned = false
  var alwaysFitToWindow = true
  private(set) var showTopBar = false
  private(set) var folderNavigator: FolderNavigator

  var alert: ImageAlert?
  @ObservationIgnored private weak var owningWindow: NSWindow?
  @ObservationIgnored private var topBarHideTask: Task<Void, Never>?

  init(loadedImage: LoadedImage) {
    currentImage = loadedImage
    folderNavigator = FolderNavigator(for: loadedImage.info.sourceURL)
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

  func reloadCurrentImage() {
    do {
      currentImage = try ImageLoader.shared.load(from: folderNavigator.currentImageURL)
    } catch {
      alert = ImageAlert(title: "Failed to Load Image", message: error.localizedDescription)
    }
  }

  func navigateToPreviousImage() {
    let success = folderNavigator.moveToPrevious()
    if success {
      reloadCurrentImage()
    }
  }

  func navigateToNextImage() {
    let success = folderNavigator.moveToNext()
    if success {
      reloadCurrentImage()
    }
  }
}
