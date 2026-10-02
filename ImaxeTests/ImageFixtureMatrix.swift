// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import AppKit
import ImageIO
@testable import Imaxe
import Testing
import UniformTypeIdentifiers

enum ImageFixtureMatrix {
  static func image(
    width: Int = 16,
    height: Int = 8,
    depth: Int = 8,
    colorSpace: CGColorSpace? = nil,
    translucent: Bool = false,
    transparentEdge: Bool = false,
    topLeft: [UInt16]? = nil,
  ) throws -> CGImage {
    let space = try #require(colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB))
    var bytes = Data()
    for y in 0 ..< height {
      for x in 0 ..< width {
        let greenAlpha: UInt16 = transparentEdge && x >= width * 3 / 4
          ? 0 : translucent ? 32768 : 65535
        let colors: [[UInt16]] = [
          topLeft ?? [65535, 0, 0, 65535],
          [0, 65535, 0, greenAlpha],
          [0, 0, 65535, 65535],
          [65535, 65535, 0, 65535],
        ]
        let index = (y < height / 2 ? 0 : 2) + (x < width / 2 ? 0 : 1)
        for (channel, value) in colors[index].enumerated() {
          let premultiplied = channel == 3 ? value : UInt16(
            UInt32(value) * UInt32(colors[index][3]) / 65535,
          )
          if depth == 16 {
            bytes.append(UInt8(premultiplied & 255))
            bytes.append(UInt8(premultiplied >> 8))
          } else {
            bytes.append(UInt8(premultiplied >> 8))
          }
        }
      }
    }
    let provider = try #require(CGDataProvider(data: bytes as CFData))
    let order: CGBitmapInfo = depth == 16 ? .byteOrder16Little : []
    return try #require(CGImage(
      width: width,
      height: height,
      bitsPerComponent: depth,
      bitsPerPixel: depth * 4,
      bytesPerRow: width * 4 * depth / 8,
      space: space,
      bitmapInfo: order.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent,
    ))
  }

  static func write(
    _ images: [CGImage],
    to url: URL,
    type: UTType = .tiff,
    properties: [CFString: Any] = [:],
  ) throws {
    let destination = try #require(CGImageDestinationCreateWithURL(
      url as CFURL,
      type.identifier as CFString,
      images.count,
      nil,
    ))
    for image in images {
      CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    }
    #expect(CGImageDestinationFinalize(destination))
  }

  static func render(_ image: NSImage, size: NSSize? = nil) throws -> NSBitmapImageRep {
    let size = size ?? image.size
    let rep = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: Int(size.width),
      pixelsHigh: Int(size.height),
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0,
    ))
    let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .none
    image.draw(
      in: NSRect(origin: .zero, size: size),
      from: .zero,
      operation: .copy,
      fraction: 1,
      respectFlipped: false,
      hints: nil,
    )
    NSGraphicsContext.restoreGraphicsState()
    return rep
  }

  static func cornerColors(_ image: NSImage) throws -> [Int] {
    let rep = try render(image)
    return try [
      (rep.pixelsWide / 4, rep.pixelsHigh / 4),
      (rep.pixelsWide * 3 / 4, rep.pixelsHigh / 4),
      (rep.pixelsWide / 4, rep.pixelsHigh * 3 / 4),
      (rep.pixelsWide * 3 / 4, rep.pixelsHigh * 3 / 4),
    ].map { x, y in
      let color = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
      let r = color.redComponent > 0.5 ? 1 : 0
      let g = color.greenComponent > 0.5 ? 2 : 0
      let b = color.blueComponent > 0.5 ? 4 : 0
      return r + g + b
    }
  }
}
