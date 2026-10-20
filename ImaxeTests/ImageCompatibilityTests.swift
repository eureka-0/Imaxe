// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import AppKit
import ImageIO
@testable import Imaxe
import Testing

@Suite("Image Compatibility")
struct ImageCompatibilityTests {
  @Test func `floating point TIFF proxy retains samples and uses a conservative byte estimate`(
  ) throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-float")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "float.tiff")
    var bytes = Data()
    for _ in 0 ..< 64 * 32 {
      for value: Float in [0.25, 0.5, 1.5, 1] {
        let bits = value.bitPattern
        for shift in stride(from: 0, to: 32, by: 8) {
          bytes.append(UInt8((bits >> shift) & 255))
        }
      }
    }
    let provider = try #require(CGDataProvider(data: bytes as CFData))
    let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
    let image = try #require(CGImage(
      width: 64,
      height: 32,
      bitsPerComponent: 32,
      bitsPerPixel: 128,
      bytesPerRow: 1024,
      space: space,
      bitmapInfo: CGBitmapInfo.floatComponents.union(.byteOrder32Little).union(
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      ),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent,
    ))
    try ImageFixtureMatrix.write([image], to: url)
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let metadata = try ImageMetadata(bitmapURL: url, imageSource: source)
    #expect(metadata.depth == 32)
    #expect(metadata.estimatedFullFrameBytes == 64 * 32 * 16)
    let proxy = try #require(ImageLoader.downsampledBitmap(
      from: source,
      metadata: metadata,
      maximumDimension: 32,
    ))
    let proxySource = try #require(CGImageSourceCreateWithData(proxy.data as CFData, nil))
    let decoded = try #require(CGImageSourceCreateImageAtIndex(proxySource, 0, nil))
    #expect(decoded.bitsPerComponent == 32)
    #expect(decoded.bitmapInfo.contains(.floatComponents))
    let color = try #require(NSBitmapImageRep(cgImage: decoded).colorAt(x: 8, y: 4))
    #expect(abs(color.redComponent - 0.25) < 0.001)
    #expect(abs(color.greenComponent - 0.5) < 0.001)
    #expect(abs(color.blueComponent - 1.5) < 0.001)
    try expectDisplayedColor(proxy.image, matches: image)
  }

  private func expectDisplayedColor(_ image: NSImage, matches reference: CGImage) throws {
    let expectedRep = try ImageFixtureMatrix.render(NSImage(
      cgImage: reference,
      size: NSSize(width: reference.width, height: reference.height),
    ))
    let actualRep = try ImageFixtureMatrix.render(image)
    let expected = try #require(expectedRep.colorAt(x: 8, y: 4)?.usingColorSpace(.sRGB))
    let actual = try #require(actualRep.colorAt(x: 4, y: 2)?.usingColorSpace(.sRGB))
    #expect(abs(expected.redComponent - actual.redComponent) < 0.03)
    #expect(abs(expected.greenComponent - actual.greenComponent) < 0.03)
    #expect(abs(expected.blueComponent - actual.blueComponent) < 0.03)
  }
}
