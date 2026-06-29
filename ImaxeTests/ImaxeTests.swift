//
//  ImaxeTests.swift
//  ImaxeTests
//
//  Created by lxlong on 2026/6/14.
//

import AppKit
@testable import Imaxe
import Testing

@MainActor
struct ImaxeTests {
  @Test func `bitmap image container uses pixel size`() {
    let image = bitmapImage()
    let url = URL(fileURLWithPath: "/tmp/example.png")

    let imageContainer = ImageContainer(url: url, nsImage: image)

    #expect(imageContainer.pixelSize == NSSize(width: 10, height: 20))
    #expect(imageContainer.nsImage.size == NSSize(width: 10, height: 20))
  }

  @Test func `canvas occupies image pixel size in backing pixels`() {
    let image = bitmapImage()
    let url = URL(fileURLWithPath: "/tmp/example.png")
    let imageContainer = ImageContainer(url: url, nsImage: image)
    let imageInfo = ImageInfo(url: url)

    let canvas = ImageCanvasView(
      imageContainer: imageContainer,
      imageInfo: imageInfo,
      zoomScale: 1.0,
    )
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: NSSize(width: 200, height: 200)),
      styleMask: [.titled],
      backing: .buffered,
      defer: false,
    )
    window.contentView?.addSubview(canvas)

    // At 100% the canvas must occupy exactly the image's pixel size in backing pixels, regardless
    // of the screen's backing scale factor.
    let backingSize = canvas.convertToBacking(canvas.bounds.size)
    #expect(backingSize.isApproximatelyEqual(to: imageContainer.pixelSize))
  }

  @Test func `image info loads sample metadata without image decode`() async throws {
    let url = sampleImageURL("sample_1280×853.png")

    let info = try await ImageLoader.shared.loadInfo(from: url)

    #expect(info.url == url)
    #expect(info.fileName == "sample_1280×853.png")
    #expect(info.pixelSize == IntSize(width: 1280, height: 853))
    #expect(info.DPI == IntSize(width: 72, height: 72))
    #expect(info.fileSize > 0)
  }

  @Test func `svg loaded image rasterizes to bitmap and uses view box size`() async throws {
    let url = sampleImageURL("sample_1280×853.svg")

    let imageInfo = try await ImageLoader.shared.loadInfo(from: url)
    let imageContainer = try await ImageLoader.shared.loadImage(from: url)
    let bitmapRep = try #require(imageContainer.nsImage.representations.first as? NSBitmapImageRep)

    #expect(imageInfo.pixelSize == IntSize(width: 1280, height: 853))
    #expect(imageContainer.pixelSize == NSSize(width: 1280, height: 853))
    #expect(imageContainer.nsImage.representations.count == 1)
    #expect(bitmapRep.pixelsWide == 1280)
    #expect(bitmapRep.pixelsHigh == 853)
  }

  @Test func `complex SVG rasterizes to bitmap`() async throws {
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

    let imageInfo = try await ImageLoader.shared.loadInfo(from: url)
    let imageContainer = try await ImageLoader.shared.loadImage(from: url)
    let bitmapRep = try #require(imageContainer.nsImage.representations.first as? NSBitmapImageRep)

    #expect(imageInfo.pixelSize == IntSize(width: 4267, height: 4267))
    #expect(imageContainer.pixelSize == NSSize(width: 4267, height: 4267))
    #expect(imageContainer.nsImage.representations.count == 1)
    #expect(bitmapRep.pixelsWide == 4267)
    #expect(bitmapRep.pixelsHigh == 4267)
  }

  @Test func `image loader returns cached image container for same url`() async throws {
    let url = sampleImageURL("sample_1280×853.png")

    let firstImage = try await ImageLoader.shared.loadImage(from: url)
    let secondImage = try await ImageLoader.shared.loadImage(from: url)

    #expect(firstImage === secondImage)
  }

  @Test func `image loader reloads changed file at same url`() async throws {
    let url = URL.temporaryDirectory
      .appending(path: "imaxe-changing-image-\(UUID().uuidString).png")

    try pngData(width: 10, height: 20).write(to: url)
    let firstImage = try await ImageLoader.shared.loadImage(from: url)
    let firstInfo = try await ImageLoader.shared.loadInfo(from: url)

    try pngData(width: 12, height: 24).write(to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: 2)],
      ofItemAtPath: url.path,
    )

    let secondImage = try await ImageLoader.shared.loadImage(from: url)
    let secondInfo = try await ImageLoader.shared.loadInfo(from: url)

    #expect(firstImage !== secondImage)
    #expect(firstImage.pixelSize == NSSize(width: 10, height: 20))
    #expect(firstInfo.pixelSize == IntSize(width: 10, height: 20))
    #expect(secondImage.pixelSize == NSSize(width: 12, height: 24))
    #expect(secondInfo.pixelSize == IntSize(width: 12, height: 24))
  }

  @Test func `image file watcher reports stable file change`() async throws {
    let url = URL.temporaryDirectory
      .appending(path: "imaxe-watched-image-\(UUID().uuidString).png")
    try pngData(width: 10, height: 20).write(to: url)
    let changedImageData = try pngData(width: 12, height: 24)

    var watcher: ImageFileWatcher?
    let didChange = await withCheckedContinuation { continuation in
      watcher = ImageFileWatcher(url: url) {
        continuation.resume(returning: true)
      }

      DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(100)) {
        try? changedImageData.write(to: url)
        try? FileManager.default.setAttributes(
          [.modificationDate: Date(timeIntervalSinceNow: 2)],
          ofItemAtPath: url.path,
        )
      }
    }

    #expect(didChange)
    _ = watcher
  }

  private func sampleImageURL(_ fileName: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "SampleImages/\(fileName)")
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

  private func pngData(width: Int, height: Int) throws -> Data {
    let representation = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: width,
      pixelsHigh: height,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0,
    ))

    let rect = NSRect(x: 0, y: 0, width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    NSColor.systemBlue.setFill()
    rect.fill()
    NSGraphicsContext.restoreGraphicsState()

    return try #require(representation.representation(using: .png, properties: [:]))
  }
}
