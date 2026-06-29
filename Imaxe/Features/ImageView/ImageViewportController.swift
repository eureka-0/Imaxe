//
//  ImageViewportController.swift
//  Imaxe
//
//  Created by Codex on 2026/6/28.
//

enum ImageViewportCommand {
  case fitToWindow
  case fitWindowToImage
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
}
