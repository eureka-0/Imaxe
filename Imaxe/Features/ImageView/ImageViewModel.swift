//
//  ImageViewModel.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/17.
//

import SwiftUI

@Observable
final class ImageViewModel {
  private(set) var currentImage: LoadedImage
  var imageScale: CGFloat = 1.0
  private(set) var fitToWindowRequest = 0
  private(set) var fitWindowToImageRequest = 0
  private(set) var isWindowPinned = false
  var alwaysFitToWindow = true
  private(set) var showTopBar = false
  private(set) var folderNavigator: FolderNavigator

  var showErrorAlert: Bool
  var alertTitle: String
  var errorMessage: String

  init(loadedImage: LoadedImage) {
    currentImage = loadedImage
    folderNavigator = FolderNavigator(for: loadedImage.info.sourceURL)
    showErrorAlert = false
    alertTitle = ""
    errorMessage = ""
  }

  func setCurrentImage(_ newImage: LoadedImage) {
    currentImage = newImage
    folderNavigator.currentImageURL = newImage.info.sourceURL
  }

  func setTopBarVisibility(to isVisible: Bool) {
    showTopBar = isVisible

    let mouseLocation = NSEvent.mouseLocation
    var standardWindowButtonVisibilityHandled = false
    for window in NSApplication.shared.orderedWindows {
      if !standardWindowButtonVisibilityHandled, window.frame.contains(mouseLocation) {
        standardWindowButtonVisibilityHandled = true
        window.standardWindowButton(.closeButton)?.isHidden = !showTopBar
        window.standardWindowButton(.miniaturizeButton)?.isHidden = !showTopBar
        window.standardWindowButton(.zoomButton)?.isHidden = !showTopBar
      } else {
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
      }
    }
  }

  func toggleWindowPinning() {
    isWindowPinned.toggle()

    if let window = NSApplication.shared.keyWindow {
      window.level = isWindowPinned ? .floating : .normal
    }
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

  func setFolderNavigator(for url: URL) {
    folderNavigator = FolderNavigator(for: url)
  }

  func reloadCurrentImage() {
    do {
      currentImage = try ImageLoader.shared.load(from: folderNavigator.currentImageURL)
    } catch {
      showErrorAlert = true
      alertTitle = "Failed to Load Image"
      errorMessage = error.localizedDescription
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
