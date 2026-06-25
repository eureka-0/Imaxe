//
//  ImaxeTests.swift
//  ImaxeTests
//
//  Created by lxlong on 2026/6/14.
//

import Testing
@testable import Imaxe
import AppKit

@MainActor
struct ImaxeTests {

  @Test func bitmapLoadedImageUsesPixelSize() {
    let image = bitmapImage()
    let url = URL(fileURLWithPath: "/tmp/example.png")

    let loadedImage = LoadedImage(image: image, sourceURL: url)

    #expect(loadedImage.pixelSize == NSSize(width: 10, height: 20))
    #expect(loadedImage.pointSize == NSSize(width: 10, height: 20))
    #expect(loadedImage.info.pixelWidth == 10)
    #expect(loadedImage.info.pixelHeight == 20)
  }

  @Test func canvasOccupiesImagePixelSizeInBackingPixels() {
    let image = bitmapImage()
    let url = URL(fileURLWithPath: "/tmp/example.png")
    let loadedImage = LoadedImage(image: image, sourceURL: url)

    let canvas = ImageCanvasView(loadedImage: loadedImage, scale: 1.0)
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: NSSize(width: 200, height: 200)),
      styleMask: [.titled],
      backing: .buffered,
      defer: false,
    )
    window.contentView?.addSubview(canvas)

    // At 100% the canvas must occupy exactly the image's pixel size in backing pixels, regardless of
    // the screen's backing scale factor.
    let backingSize = canvas.convertToBacking(canvas.bounds.size)
    #expect(backingSize.isApproximatelyEqual(to: loadedImage.pixelSize))
  }

  @Test func svgLoadedImageRasterizesToBitmapAndUsesViewBoxSize() async throws {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "SampleImages/sample_1280×853.svg")

    let loadedImage = try await ImageLoader.shared.load(from: url)
    let bitmapRep = try #require(loadedImage.image.representations.first as? NSBitmapImageRep)

    #expect(loadedImage.pixelSize == NSSize(width: 1280, height: 853))
    #expect(loadedImage.info.pixelWidth == 1280)
    #expect(loadedImage.info.pixelHeight == 853)
    #expect(loadedImage.image.representations.count == 1)
    #expect(bitmapRep.pixelsWide == 1280)
    #expect(bitmapRep.pixelsHigh == 853)
  }

  @Test func complexSVGRasterizesToBitmap() async throws {
    let url = URL.temporaryDirectory
      .appending(path: "imaxe-svg-with-paint-server.svg")
    let svg = """
    <svg width="100%" height="100%" viewBox="0 0 4267 4267" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="gradient"><stop offset="0" style="stop-color:#fff"/></linearGradient>
        <clipPath id="clip"><path d="M0 0h4267v4267h-4267z"/></clipPath>
      </defs>
      <g clip-path="url(#clip)">
        <path d="M0 0h4267v4267h-4267z" style="fill:url(#gradient);"/>
        <circle cx="2133.5" cy="2133.5" r="1200" style="fill:#3478f6;"/>
      </g>
    </svg>
    """
    try svg.write(to: url, atomically: true, encoding: .utf8)

    let loadedImage = try await ImageLoader.shared.load(from: url)
    let bitmapRep = try #require(loadedImage.image.representations.first as? NSBitmapImageRep)

    #expect(loadedImage.pixelSize == NSSize(width: 4267, height: 4267))
    #expect(loadedImage.image.representations.count == 1)
    #expect(bitmapRep.pixelsWide == 4267)
    #expect(bitmapRep.pixelsHigh == 4267)
  }

  private func bitmapImage() -> NSImage {
    let representation = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: 10,
      pixelsHigh: 20,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0,
    )

    let image = NSImage(size: NSSize(width: 10, height: 20))
    if let representation {
      image.addRepresentation(representation)
    }
    return image
  }
}
