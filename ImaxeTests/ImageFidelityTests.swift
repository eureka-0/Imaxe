// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import AppKit
import ImageIO
@testable import Imaxe
import Testing
import UniformTypeIdentifiers

@Suite("Image Fidelity")
struct ImageFidelityTests {
  @Test(arguments: Array(1 ... 8))
  func `orientation matrix renders all mirrored and rotated corners`(
    _ orientation: Int,
  ) async throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-orientation")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "oriented.tiff")
    try ImageFixtureMatrix.write([ImageFixtureMatrix.image()], to: url, properties: [
      kCGImagePropertyOrientation: orientation,
      kCGImagePropertyDPIWidth: 144,
      kCGImagePropertyDPIHeight: 72,
    ])
    let document = try await ImageLoader.shared.loadDocument(from: url)
    let expected = [
      [1, 2, 4, 3],
      [2, 1, 3, 4],
      [3, 4, 2, 1],
      [4, 3, 1, 2],
      [1, 4, 2, 3],
      [4, 1, 3, 2],
      [3, 2, 4, 1],
      [2, 3, 1, 4],
    ]
    #expect(document.metadata.orientation.rawValue == UInt32(orientation))
    #expect(document.metadata.rawPixelSize == IntSize(width: 16, height: 8))
    #expect(document.pixelSize == (orientation >= 5
        ? NSSize(width: 8, height: 16) : NSSize(width: 16, height: 8)))
    #expect(try ImageFixtureMatrix.cornerColors(document.nsImage) == expected[orientation - 1])

    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let proxy = try #require(ImageLoader.downsampledBitmap(
      from: source,
      metadata: document.metadata,
      maximumDimension: 8,
    ))
    #expect(try ImageFixtureMatrix.cornerColors(proxy.image) == expected[orientation - 1])
    #expect(document.metadata.DPI == IntSize(width: 144, height: 72))
    #expect(document.metadata.displayDPI == (orientation >= 5
        ? IntSize(width: 72, height: 144) : IntSize(width: 144, height: 72)))
  }

  @Test func `transparent proxy preserves alpha and unassociated color`() throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-alpha")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "alpha.png")
    let fixture = try ImageFixtureMatrix.image(
      width: 64,
      height: 32,
      translucent: true,
      transparentEdge: true,
    )
    try ImageFixtureMatrix.write([fixture], to: url, type: .png)
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let metadata = try ImageMetadata(bitmapURL: url, imageSource: source)
    let proxy = try #require(ImageLoader.downsampledBitmap(
      from: source,
      metadata: metadata,
      maximumDimension: 32,
    ))
    let rep = try ImageFixtureMatrix.render(proxy.image)
    let color = try #require(rep.colorAt(x: 20, y: 4)?.usingColorSpace(.sRGB))
    #expect(metadata.hasAlpha)
    #expect(abs(color.alphaComponent - 0.5) < 0.02, "\(color)")
    #expect(color.greenComponent > 0.95)
    #expect(color.redComponent < 0.02 && color.blueComponent < 0.02)
    let edge = try #require(rep.colorAt(x: 23, y: 4)?.usingColorSpace(.sRGB))
    let clear = try #require(rep.colorAt(x: 28, y: 4)?.usingColorSpace(.sRGB))
    #expect(edge.alphaComponent > 0.01 && edge.alphaComponent < 0.52)
    #expect(edge.greenComponent > 0.95)
    #expect(edge.redComponent < 0.02 && edge.blueComponent < 0.02)
    #expect(clear.alphaComponent < 0.01)
  }

  @Test(arguments: [CGColorSpace.sRGB as String, CGColorSpace.displayP3 as String])
  func `embedded ICC profile survives lossless proxy`(_ spaceName: String) throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-icc")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "profile.png")
    let space = try #require(CGColorSpace(name: spaceName as CFString))
    let fixture = try ImageFixtureMatrix.image(
      width: 64,
      height: 32,
      colorSpace: space,
      topLeft: [30000, 42000, 16000, 65535],
    )
    try ImageFixtureMatrix.write([fixture], to: url, type: .png)
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let metadata = try ImageMetadata(bitmapURL: url, imageSource: source)
    let original = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let proxy = try #require(ImageLoader.downsampledBitmap(
      from: source,
      metadata: metadata,
      maximumDimension: 32,
    ))
    let proxySource = try #require(CGImageSourceCreateWithData(proxy.data as CFData, nil))
    let decoded = try #require(CGImageSourceCreateImageAtIndex(proxySource, 0, nil))
    #expect(original.colorSpace?.copyICCData() == decoded.colorSpace?.copyICCData())
    #expect(metadata.colorProfileName != nil)
    let reference = try ImageFixtureMatrix.render(NSImage(cgImage: original, size: NSSize(
      width: original.width,
      height: original.height,
    )))
    let rendered = try ImageFixtureMatrix.render(proxy.image)
    let expected = try #require(reference.colorAt(x: 16, y: 8)?.usingColorSpace(.sRGB))
    let actual = try #require(rendered.colorAt(x: 8, y: 4)?.usingColorSpace(.sRGB))
    #expect(abs(expected.redComponent - actual.redComponent) < 0.02, "\(expected) -> \(actual)")
    #expect(abs(expected.greenComponent - actual.greenComponent) < 0.02, "\(expected) -> \(actual)")
    #expect(abs(expected.blueComponent - actual.blueComponent) < 0.02, "\(expected) -> \(actual)")
  }

  @Test(arguments: ["png", "tiff"])
  func `sixteen bit proxy retains depth alpha and samples`(_ ext: String) throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-depth")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "sixteen.\(ext)")
    let fixture = try ImageFixtureMatrix.image(
      width: 64,
      height: 32,
      depth: 16,
      translucent: true,
      topLeft: [50000, 12345, 0, 65535],
    )
    try ImageFixtureMatrix.write([fixture], to: url, type: ext == "png" ? .png : .tiff)
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let metadata = try ImageMetadata(bitmapURL: url, imageSource: source)
    let proxy = try #require(ImageLoader.downsampledBitmap(
      from: source,
      metadata: metadata,
      maximumDimension: 32,
    ))
    let proxySource = try #require(CGImageSourceCreateWithData(proxy.data as CFData, nil))
    let decoded = try #require(CGImageSourceCreateImageAtIndex(proxySource, 0, nil))
    #expect(metadata.depth == 16)
    #expect(decoded.bitsPerComponent == 16)
    #expect(decoded.alphaInfo != .none)
    #expect(try ImageFixtureMatrix.cornerColors(proxy.image) == [1, 2, 4, 3])
    let original = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let originalRep = NSBitmapImageRep(cgImage: original)
    let decodedRep = NSBitmapImageRep(cgImage: decoded)
    let expected = try #require(originalRep.colorAt(x: 16, y: 8))
    let actual = try #require(decodedRep.colorAt(x: 8, y: 4))
    #expect(abs(expected.redComponent - actual.redComponent) < 2.0 / 65535)
    #expect(abs(expected.greenComponent - actual.greenComponent) < 2.0 / 65535)
  }

  @Test func `reloading after cache eviction preserves metadata and rendered pixels`() async throws {
    let loader = ImageLoader()
    let url = TestSupport.sampleImageURL("sample_1280×853.png")
    let first = try await loader.loadDocument(from: url)
    let firstPixels = try ImageFixtureMatrix.render(
      first.nsImage,
      size: NSSize(width: 16, height: 8),
    )
    await loader.clearCache()
    let second = try await loader.loadDocument(from: url)
    let secondPixels = try ImageFixtureMatrix.render(
      second.nsImage,
      size: NSSize(width: 16, height: 8),
    )
    #expect(first.metadata == second.metadata)
    #expect(first.fileSnapshot == second.fileSnapshot)
    #expect(first.renderedPixelSize == second.renderedPixelSize)
    for y in 0 ..< 8 {
      for x in 0 ..< 16 {
        #expect(firstPixels.colorAt(x: x, y: y) == secondPixels.colorAt(x: x, y: y))
      }
    }
  }

  @Test func `format strategies share explicit retained pixel budgets`() async throws {
    let samples = [
      ("sample_1280×853.png", ImageLoadingStrategy.staticBitmap),
      ("sample_1280×853.tiff", .tiffFirstPage),
      ("sample_384×512.gif", .animatedGIF),
      ("sample_1280×853.svg", .svg),
    ]
    for (name, strategy) in samples {
      let document = try await ImageLoader.shared
        .loadDocument(from: TestSupport.sampleImageURL(name))
      #expect(ImageLoadingStrategy(metadata: document.metadata) == strategy)
      #expect(document.renderedPixelSize.width <= Int(Constants.maximumImageDimension))
      #expect(document.renderedPixelSize.height <= Int(Constants.maximumImageDimension))
      if strategy == .animatedGIF {
        #expect(document.cacheCost >= document.metadata.estimatedFullFrameBytes)
      }
    }
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-budget")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "wide.png")
    try TestSupport.pngData(width: 5000, height: 4000).write(to: url)
    let document = try await ImageLoader().loadDocument(from: url)
    #expect(document.isDownsampled)
    #expect(document.cacheCost <= ImageLoadingPolicy.bitmapBytes)
    #expect(document.metadata.rawPixelSize == IntSize(width: 5000, height: 4000))
  }

  @Test func `GIF finite loops stop on final frame and infinite loops continue`() {
    var finite = GIFPlaybackState()
    let steps = (0 ..< 4).map { _ in finite.advance(frameCount: 2, loopCount: 2) }
    #expect(steps == [true, true, true, false])
    #expect(finite.frame == 1 && finite.isFinished)
    let didAdvanceAfterFinishing = finite.advance(frameCount: 2, loopCount: 2)
    #expect(!didAdvanceAfterFinishing)
    var infinite = GIFPlaybackState()
    for _ in 0 ..< 100 {
      let didAdvance = infinite.advance(frameCount: 2, loopCount: 0)
      #expect(didAdvance)
    }
    #expect(!infinite.isFinished)
  }

  @Test func `GIF proxy preserves loop count frame timing and rendered frames`() throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-gif-properties")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "finite.gif")
    let frames = try [ImageFixtureMatrix.image(), ImageFixtureMatrix.image()]
    let destination = try #require(CGImageDestinationCreateWithURL(
      url as CFURL,
      UTType.gif.identifier as CFString,
      frames.count,
      nil,
    ))
    CGImageDestinationSetProperties(destination, [
      kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 2],
    ] as CFDictionary)
    for (index, frame) in frames.enumerated() {
      let delay = index == 0 ? 0.1 : 0.2
      CGImageDestinationAddImage(destination, frame, [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: delay],
      ] as CFDictionary)
    }
    #expect(CGImageDestinationFinalize(destination))
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let animation = try ImageLoader.downsampledAnimatedGIF(from: source, maximumDimension: 8)
    let proxy = try #require(animation)
    let rep = try #require(proxy.image.animatedGIFRepresentation)
    #expect((rep.value(forProperty: .loopCount) as? NSNumber)?.intValue == 2)
    for index in 0 ..< 2 {
      rep.setProperty(.currentFrame, withValue: index)
      #expect(abs(rep.currentGIFFrameDuration() - (index == 0 ? 0.1 : 0.2)) < 0.01)
      #expect(try ImageFixtureMatrix.cornerColors(proxy.image) == [1, 2, 4, 3])
    }
  }

  @Test func `SVG rasterization retains transparent regions and view box geometry`() async throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-svg-alpha")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "transparent.svg")
    try """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 32">
      <rect width="32" height="32" fill="#00ff00" fill-opacity="0.5"/>
    </svg>
    """.write(to: url, atomically: true, encoding: .utf8)
    let document = try await ImageLoader().loadDocument(from: url)
    let rep = try ImageFixtureMatrix.render(document.nsImage)
    let green = try #require(rep.colorAt(x: 16, y: 16))
    let clear = try #require(rep.colorAt(x: 48, y: 16))
    #expect(abs(green.alphaComponent - 0.5) < 0.02)
    #expect(green.greenComponent > 0.95)
    #expect(clear.alphaComponent < 0.01)
    #expect(document.metadata.rawPixelSize == IntSize(width: 64, height: 32))
  }

  @Test func `rotated anisotropic DPI preserves physical print dimensions`() throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-print-dpi")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "print.tiff")
    try ImageFixtureMatrix.write([ImageFixtureMatrix.image()], to: url, properties: [
      kCGImagePropertyOrientation: 6,
      kCGImagePropertyDPIWidth: 144,
      kCGImagePropertyDPIHeight: 72,
    ])
    let snapshot = try #require(FileSnapshot(url: url))
    let document = try ImageLoader.loadBitmap(from: url, fileSnapshot: snapshot)
    let defaults = UserDefaults.standard
    let key = AppSettings.Keys.imageActualSizeStrategy.rawValue
    let previous = defaults.object(forKey: key)
    defaults.set(ImageActualSizeStrategy.printSize.rawValue, forKey: key)
    defer {
      if let previous {
        defaults.set(previous, forKey: key)
      } else {
        defaults.removeObject(forKey: key)
      }
    }
    let canvas = ImageCanvasView(document: document)
    // 8/72 and 16/144 inches remain equal after the 90-degree rotation.
    #expect(abs(canvas.frame.width - canvas.frame.height) < 0.001)
    #expect(abs(canvas.frame.width - 8.0 / 72 * Constants.fallbackScreenPPI.0) < 0.001)
    #expect(document.metadata.DPI == IntSize(width: 144, height: 72))
    #expect(document.metadata.DPIDescription == "144 x 72 Pixels/Inch")
  }

  @Test func `multi page TIFF always renders first page and retains page metadata`() async throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-pages")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "pages.tiff")
    let first = try ImageFixtureMatrix.image(width: 16, height: 8)
    let second = try ImageFixtureMatrix.image(
      width: 32,
      height: 32,
      topLeft: [0, 0, 65535, 65535],
    )
    try ImageFixtureMatrix.write([first, second], to: url)
    let document = try await ImageLoader.shared.loadDocument(from: url)
    #expect(document.metadata.imageCount == 2)
    #expect(document.metadata.primaryImageIndex == 0)
    #expect(document.metadata.isMultiPage)
    #expect(document.metadata.rawPixelSize == IntSize(width: 16, height: 8))
    #expect(document.nsImage.representations.count == 1)
    #expect(try ImageFixtureMatrix.cornerColors(document.nsImage) == [1, 2, 4, 3])
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let proxy = try #require(ImageLoader.downsampledBitmap(
      from: source,
      metadata: document.metadata,
      maximumDimension: 8,
    ))
    let proxySource = try #require(CGImageSourceCreateWithData(proxy.data as CFData, nil))
    #expect(CGImageSourceGetCount(proxySource) == 1)
    #expect(proxy.pixelSize == IntSize(width: 8, height: 4))
  }
}
