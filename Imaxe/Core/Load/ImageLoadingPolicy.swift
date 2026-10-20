// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import Foundation
import UniformTypeIdentifiers

nonisolated enum ImageLoadingStrategy: String, Sendable {
  case staticBitmap
  case animatedGIF
  case tiffFirstPage
  case svg

  init(metadata: ImageMetadata) {
    if metadata.isSVG {
      self = .svg
    } else if metadata.isAnimated {
      self = .animatedGIF
    } else if metadata.containerType?.conforms(to: .tiff) == true {
      self = .tiffFirstPage
    } else {
      self = .staticBitmap
    }
  }
}

/// Budgets describe retained decoded pixels, not ImageIO's temporary allocations or process RSS.
nonisolated enum ImageLoadingPolicy {
  static let bitmapBytes = 64 * 1024 * 1024
  static let animationBytes = 64 * 1024 * 1024
  static let svgBytes = 64 * 1024 * 1024

  static func maximumDimension(for metadata: ImageMetadata) -> Int {
    let strategy = ImageLoadingStrategy(metadata: metadata)
    let frameCount = strategy == .animatedGIF ? max(1, metadata.imageCount) : 1
    let budget = strategy == .svg ? svgBytes
      : strategy == .animatedGIF ? animationBytes : bitmapBytes
    let bytesPerPixel = ImageMetadata.estimatedBytesPerPixel(depth: metadata.depth)
    let size = metadata.displayPixelSize
    let pixels = Double(size.width) * Double(size.height)
    let allowedPixels = Double(budget) / Double(bytesPerPixel) / Double(frameCount)
    let scale = min(1, sqrt(allowedPixels / max(1, pixels)))
    return max(1, min(
      Int(Constants.maximumImageDimension),
      Int((Double(max(size.width, size.height)) * scale).rounded(.down)),
    ))
  }
}
