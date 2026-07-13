//
//  ImageViewportController.swift
//  Imaxe
//
//  Created by Codex on 2026/6/28.
//

import Foundation

enum ImageViewportCommand {
  case fitToWindow
  case fitWindowToImage
  case setZoomScale(to: CGFloat)
  case zoomIn, zoomOut
  case fitToScreen
  case pan(horizontal: CGFloat, vertical: CGFloat)
}

protocol ImageViewportCommandHandling: AnyObject {
  func handle(_ command: ImageViewportCommand)
}

final class ImageViewportController {
  weak var handler: ImageViewportCommandHandling?

  func fitToWindow() {
    handler?.handle(.fitToWindow)
  }

  func fitWindowToImage() {
    handler?.handle(.fitWindowToImage)
  }

  func setZoomScale(_ zoomScale: CGFloat) {
    handler?.handle(.setZoomScale(to: zoomScale))
  }

  func zoomIn() {
    handler?.handle(.zoomIn)
  }

  func zoomOut() {
    handler?.handle(.zoomOut)
  }

  func fitToScreen() {
    handler?.handle(.fitToScreen)
  }

  func pan(horizontal: CGFloat, vertical: CGFloat) {
    handler?.handle(.pan(horizontal: horizontal, vertical: vertical))
  }
}
