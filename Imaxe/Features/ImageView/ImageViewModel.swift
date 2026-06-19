//
//  ImageViewModel.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/17.
//

import SwiftUI

@Observable
final class ImageViewModel {
  var currentImage: NSImage?
  var imageScale: CGFloat = 1.0
  private(set) var fitToWindowRequest = 0
  private(set) var fitWindowToImageRequest = 0
  private(set) var isWindowPinned = false
  var alwaysFitToWindow = true
  private(set) var showTopBar = false

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
}
