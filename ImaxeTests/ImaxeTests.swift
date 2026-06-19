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

  @Test func nonBitmapRepresentationsAreTreatedAsVector() {
    let image = NSImage(size: NSSize(width: 100, height: 80), flipped: false) { _ in
      true
    }
    let url = URL(fileURLWithPath: "/tmp/example.pdf")

    let kind = ImageKind(sourceURL: url, image: image)

    #expect(kind == .vector)
    #expect(kind.cacheMode == .never)
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
