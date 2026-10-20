// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import AppKit
import ImageIO
@testable import Imaxe
import Testing
import UniformTypeIdentifiers

@Suite("Image Compatibility")
struct ImageCompatibilityTests {
  @Test(arguments: [false, true], [UTType.tiff, .jpeg])
  func `grayscale and CMYK proxies preserve source metadata and displayed color`(
    _ cmyk: Bool,
    _ type: UTType,
  ) throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-color-model")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "model.\(type.preferredFilenameExtension ?? "tiff")")
    let space = cmyk ? CGColorSpaceCreateDeviceCMYK()
      : try #require(CGColorSpace(name: CGColorSpace.genericGrayGamma2_2))
    let samples: [UInt8] = cmyk ? [25, 90, 160, 35] : [95]
    let image = try componentImage(space: space, samples: samples)
    try ImageFixtureMatrix.write([image], to: url, type: type)
    let snapshot = try #require(FileSnapshot(url: url))
    let document = try ImageLoader.loadBitmap(
      from: url,
      fileSnapshot: snapshot,
      maximumDimension: 32,
    )
    #expect(document.metadata.colorModel == (cmyk ? "CMYK" : "Gray"))
    #expect(document.metadata.rawPixelSize == IntSize(width: 64, height: 32))
    #expect(document.isDownsampled)
    try expectDisplayedColor(document.nsImage, matches: image)
  }

  @Test func `custom calibrated ICC survives proxy and renders its calibrated color`() throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-custom-icc")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "custom.png")
    let space = try #require(CGColorSpace(
      calibratedRGBWhitePoint: [0.95047, 1, 1.08883],
      blackPoint: nil,
      gamma: [1.6, 1.8, 2.0],
      matrix: [0.4124, 0.2126, 0.0193, 0.3576, 0.7152, 0.1192, 0.1805, 0.0722, 0.9505],
    ))
    let profile = try #require(space.copyICCData())
    #expect(profile != CGColorSpace(name: CGColorSpace.sRGB)?.copyICCData())
    let image = try ImageFixtureMatrix.image(
      width: 64,
      height: 32,
      colorSpace: space,
      topLeft: [30000, 42000, 16000, 65535],
    )
    try ImageFixtureMatrix.write([image], to: url, type: .png)
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let original = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(original.colorSpace?.copyICCData() == profile)
    let metadata = try ImageMetadata(bitmapURL: url, imageSource: source)
    let proxy = try #require(ImageLoader.downsampledBitmap(
      from: source,
      metadata: metadata,
      maximumDimension: 32,
    ))
    let proxySource = try #require(CGImageSourceCreateWithData(proxy.data as CFData, nil))
    let decoded = try #require(CGImageSourceCreateImageAtIndex(proxySource, 0, nil))
    #expect(decoded.colorSpace?.copyICCData() == original.colorSpace?.copyICCData())
    try expectDisplayedColor(proxy.image, matches: original)
  }

  @Test(arguments: [UTType.png, .tiff])
  func `sixteen bit gradient proxy retains more than eight bit precision`(_ type: UTType) throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-gradient")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "gradient.\(type.preferredFilenameExtension ?? "tiff")")
    var bytes = Data()
    for _ in 0 ..< 8 {
      for x in 0 ..< 1024 {
        for value in [UInt16(1500 + x * 60), UInt16(1500 + x * 60), UInt16(1500 + x * 60), 65535] {
          bytes.append(UInt8(value & 255))
          bytes.append(UInt8(value >> 8))
        }
      }
    }
    let provider = try #require(CGDataProvider(data: bytes as CFData))
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let image = try #require(CGImage(
      width: 1024,
      height: 8,
      bitsPerComponent: 16,
      bitsPerPixel: 64,
      bytesPerRow: 8192,
      space: space,
      bitmapInfo: CGBitmapInfo.byteOrder16Little.union(
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      ),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent,
    ))
    try ImageFixtureMatrix.write([image], to: url, type: type)
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let metadata = try ImageMetadata(bitmapURL: url, imageSource: source)
    let proxy = try #require(ImageLoader.downsampledBitmap(
      from: source,
      metadata: metadata,
      maximumDimension: 512,
    ))
    let proxySource = try #require(CGImageSourceCreateWithData(proxy.data as CFData, nil))
    let decoded = try #require(CGImageSourceCreateImageAtIndex(proxySource, 0, nil))
    #expect(metadata.depth == 16 && decoded.bitsPerComponent == 16)
    let rep = NSBitmapImageRep(cgImage: decoded)
    var values = [Int]()
    for x in 0 ..< decoded.width {
      let color = try #require(rep.colorAt(x: x, y: 0))
      values.append(Int((color.redComponent * 65535).rounded()))
    }
    #expect(Set(values).count > 256)
    #expect(zip(values, values.dropFirst()).allSatisfy { $0 < $1 })
    #expect(values.contains { $0 % 257 != 0 })
    #expect((values.first ?? 65535) < 2000 && (values.last ?? 0) > 62000)
  }

  @Test func `partial GIF frames retain background and previous disposal through proxy`() throws {
    let data = disposalGIF()
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    #expect(CGImageSourceGetCount(source) == 4)
    let original = try #require(NSImage(data: data))
    let animation = try ImageLoader.downsampledAnimatedGIF(from: source, maximumDimension: 4)
    let proxy = try #require(animation)
    for image in [original, proxy.image] {
      let rep = try #require(image.animatedGIFRepresentation)
      #expect(rep.gifFrameCount == 4)
      for frame in 0 ..< 4 {
        rep.setProperty(.currentFrame, withValue: frame)
        let rendered = try ImageFixtureMatrix.render(image)
        let left = try #require(rendered.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB))
        let right = try #require(rendered.colorAt(x: rendered.pixelsWide - 1, y: 0)?
          .usingColorSpace(.sRGB))
        if frame == 0 {
          #expect(left.redComponent > 0.95 && right.redComponent > 0.95)
        } else if frame == 1 {
          #expect(left.greenComponent > 0.95 && right.redComponent > 0.95)
        } else if frame == 2 {
          #expect(left.alphaComponent < 0.01 && right.blueComponent > 0.95)
        } else {
          #expect(left.greenComponent > 0.95 && right.redComponent > 0.95)
          let clear = try #require(rendered.colorAt(x: 0, y: rendered.pixelsHigh - 1))
          #expect(clear.alphaComponent < 0.01)
        }
        #expect(abs(rep.currentGIFFrameDuration() - Double(frame + 1) / 10) < 0.01)
      }
    }
  }

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

  private func componentImage(space: CGColorSpace, samples: [UInt8]) throws -> CGImage {
    let bytes = Data(Array(repeating: samples, count: 64 * 32).flatMap(\.self))
    let provider = try #require(CGDataProvider(data: bytes as CFData))
    return try #require(CGImage(
      width: 64,
      height: 32,
      bitsPerComponent: 8,
      bitsPerPixel: samples.count * 8,
      bytesPerRow: 64 * samples.count,
      space: space,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent,
    ))
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

  private func disposalGIF() -> Data {
    // Hand-encoded local rectangles make the expected composition independent of ImageIO's encoder.
    var bytes = Array("GIF89a".utf8) + [8, 0, 4, 0, 0x81, 0, 0]
      + [0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255]
    bytes += [0x21, 0xFF, 11] + Array("NETSCAPE2.0".utf8) + [3, 1, 0, 0, 0]
    let frames = [(0, 8, 4, 1, 1), (0, 4, 4, 2, 2), (4, 4, 4, 3, 3), (0, 2, 2, 2, 1)]
    for (index, frame) in frames.enumerated() {
      let (left, width, height, color, disposal) = frame
      bytes += [0x21, 0xF9, 4, UInt8(disposal << 2 | 1), UInt8((index + 1) * 10), 0, 0, 0]
      bytes += [0x2C, UInt8(left), 0, 0, 0, UInt8(width), 0, UInt8(height), 0, 0, 2]
      let codes = Array(repeating: [4, color], count: width * height).flatMap(\.self) + [5]
      var compressed = [UInt8]()
      var accumulator = 0
      var count = 0
      for code in codes {
        accumulator |= code << count
        count += 3
        if count >= 8 {
          compressed.append(UInt8(accumulator & 255))
          accumulator >>= 8
          count -= 8
        }
      }
      if count > 0 {
        compressed.append(UInt8(accumulator & 255))
      }
      bytes += [UInt8(compressed.count)] + compressed + [0]
    }
    bytes.append(0x3B)
    return Data(bytes)
  }
}
