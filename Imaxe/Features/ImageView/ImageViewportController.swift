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
  case setScale(to: CGFloat)
  case scale(by: CGFloat)
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

  func setScale(_ scale: CGFloat) {
    handler?.handle(.setScale(to: scale))
  }

  func scale(by factor: CGFloat) {
    handler?.handle(.scale(by: factor))
  }
}
