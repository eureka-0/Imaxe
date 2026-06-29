//
//  ImageContainer.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/27.
//

import AppKit

final nonisolated class ImageContainer: Sendable {
  let url: URL
  let nsImage: NSImage
  /// The image's true size in pixels, used for the 100% display baseline and metadata.
  let pixelSize: NSSize

  var cacheCost: Int {
    let pixelCount = max(1, pixelSize.width) * max(1, pixelSize.height)
    let cost = (pixelCount * 4).rounded(.up)
    return Int(min(cost, Double(Int.max)))
  }

  init(
    url: URL,
    nsImage: NSImage,
    pixelSize: NSSize? = nil,
  ) {
    self.url = url
    self.nsImage = nsImage
    self.pixelSize = nsImage.pixelSize(preferred: pixelSize)
    nsImage.cacheMode = .default
  }
}
