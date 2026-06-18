//
//  ImageViewModel.swift
//  Imagxe
//
//  Created by lxlong on 2026/6/17.
//

import SwiftUI

@Observable
final class ImageViewModel {
  var currentImage: NSImage?
  var imageScale: CGFloat = 1.0
  private(set) var fitToWindowRequest = 0
  private(set) var isWindowPinned = false

  func toggleWindowPinning() {
    isWindowPinned.toggle()

    if let window = NSApplication.shared.keyWindow {
      window.level = isWindowPinned ? .floating : .normal
    }
  }

  func fitToWindow() {
    fitToWindowRequest += 1
  }

  func fitWindowToImage() {
    if let window = NSApplication.shared.keyWindow {
      guard let imageSize = currentImage?.pixelSize else {
        return
      }

      // Record the current center point of the window
      let oldFrame = window.frame
      let center = NSPoint(x: oldFrame.midX, y: oldFrame.midY)

      // Calculate the new frame size based on the image size and scale
      var newWidth = imageSize.width * imageScale
      var newHeight = imageSize.height * imageScale

      if let visibleFrame = NSScreen.main?.visibleFrame.size {
        newWidth = min(newWidth, visibleFrame.width)
        newHeight = min(newHeight, visibleFrame.height)
      }

      let contentRect = NSRect(origin: .zero, size: CGSize(width: newWidth, height: newHeight))
      let targetFrameRect = window.frameRect(forContentRect: contentRect)
      let newFrameSize = targetFrameRect.size

      // Calculate the new frame to keep the window centered around the same point
      let newFrame = NSRect(
        x: center.x - newFrameSize.width / 2.0,
        y: center.y - newFrameSize.height / 2.0,
        width: newFrameSize.width,
        height: newFrameSize.height,
      )

      window.setFrame(newFrame, display: false, animate: true)
    }
  }
}
