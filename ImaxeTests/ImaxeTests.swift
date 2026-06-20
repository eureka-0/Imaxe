//
//  ImaxeTests.swift
//  ImaxeTests
//
//  Created by lxlong on 2026/6/14.
//

import Testing
@testable import Imaxe
import AppKit

struct ImaxeTests {

  @Test func svgExtensionIsTreatedAsVector() {
    let image = bitmapImage()
    let url = URL(fileURLWithPath: "/tmp/example.svg")

    let kind = ImageKind(sourceURL: url, image: image)

    #expect(kind == .vector)
  }

  @Test func bitmapRepresentationsAreTreatedAsBitmap() throws {
    let image = bitmapImage()
    let url = URL(fileURLWithPath: "/tmp/example.png")

    let kind = ImageKind(sourceURL: url, image: image)

    #expect(kind == .bitmap)
    #expect(kind.cacheMode == .default)
  }

  @Test func bitmapLoadedImageUsesPixelSizeAndHasNoSVGPaths() {
    let image = bitmapImage()
    let url = URL(fileURLWithPath: "/tmp/example.png")

    let loadedImage = LoadedImage(image: image, sourceURL: url)

    #expect(loadedImage.kind == .bitmap)
    #expect(loadedImage.svgPaths == nil)
    #expect(loadedImage.displaySize == NSSize(width: 10, height: 20))
    #expect(loadedImage.info.pixelWidth == 10)
    #expect(loadedImage.info.pixelHeight == 20)
  }

  @Test func nonBitmapRepresentationsAreTreatedAsVector() {
    let image = NSImage(size: NSSize(width: 100, height: 80), flipped: false) { _ in
      true
    }
    let url = URL(fileURLWithPath: "/tmp/example.pdf")

    let kind = ImageKind(sourceURL: url, image: image)

    #expect(kind == .vector)
    #expect(kind.cacheMode == .never)
  }

  @Test func svgLoadedImageStoresVectorPathsAndUsesViewBoxSize() throws {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "SampleImages/sample_1280×853.svg")

    let loadedImage = try ImageLoader.shared.load(from: url)

    #expect(loadedImage.kind == .vector)
    #expect(loadedImage.svgPaths?.isEmpty == false)
    #expect(loadedImage.displaySize == NSSize(width: 1280, height: 853))
    #expect(loadedImage.info.pixelWidth == 1280)
    #expect(loadedImage.info.pixelHeight == 853)
    #expect(loadedImage.image.representations.isEmpty)
  }

  @Test func complexSVGUsesNSImageFallback() throws {
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

    let loadedImage = try ImageLoader.shared.load(from: url)

    #expect(loadedImage.kind == .vector)
    #expect(loadedImage.svgPaths == nil)
    #expect(loadedImage.displaySize == NSSize(width: 4267, height: 4267))
    #expect(loadedImage.image.representations.isEmpty == false)
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
