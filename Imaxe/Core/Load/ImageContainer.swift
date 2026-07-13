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
  private let animatedImageData: Data?

  var cacheCost: Int {
    let pixelCount = max(1, pixelSize.width) * max(1, pixelSize.height)
    let cost = (pixelCount * 4).rounded(.up)
    return Int(min(cost, Double(Int.max)))
  }

  init(
    url: URL,
    nsImage: NSImage,
    pixelSize: NSSize? = nil,
    animatedImageData: Data? = nil,
  ) {
    self.url = url
    self.nsImage = nsImage
    self.pixelSize = nsImage.pixelSize(preferred: pixelSize)
    self.animatedImageData = animatedImageData
    nsImage.cacheMode = .default
  }

  func makeAnimatedBitmapRepresentation() -> NSBitmapImageRep? {
    guard let animatedImageData,
          let bitmapRep = NSBitmapImageRep(data: animatedImageData),
          (bitmapRep.gifFrameCount ?? 0) > 1
    else { return nil }

    return bitmapRep
  }
}
