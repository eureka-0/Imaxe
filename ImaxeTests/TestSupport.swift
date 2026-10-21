// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

@testable import Imaxe
import SwiftUI
import Testing

@MainActor
enum TestSupport {
  static func sampleImageURL(_ fileName: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "images/\(fileName)")
  }

  static func bitmapImage(width: Int = 10, height: Int = 20) -> NSImage {
    let representation = NSBitmapImageRep(
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
    )

    let image = NSImage(size: NSSize(width: width, height: height))
    if let representation {
      image.addRepresentation(representation)
    }
    return image
  }

  static func pngData(width: Int, height: Int) throws -> Data {
    let representation = try #require(
      NSBitmapImageRep(
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
      ),
    )

    let rect = NSRect(x: 0, y: 0, width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    NSColor.systemBlue.setFill()
    rect.fill()
    NSGraphicsContext.restoreGraphicsState()

    return try #require(representation.representation(using: .png, properties: [:]))
  }

  static func temporaryDirectory(prefix: String) throws -> URL {
    let directory = URL.temporaryDirectory
      .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  static func waitUntil(
    timeout: Duration = .seconds(30),
    condition: @escaping () -> Bool,
  ) async throws {
    let start = ContinuousClock.now

    while !condition() {
      if start.duration(to: .now) > timeout {
        throw WaitTimeoutError()
      }
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  private struct WaitTimeoutError: Error {}
}

extension CGFloat {
  func isApproximatelyEqual(to other: CGFloat) -> Bool {
    abs(self - other) < Constants.zoomScaleUpdateTolerance
  }
}

extension NSRect {
  func isApproximatelyEqual(to other: NSRect) -> Bool {
    origin.isApproximatelyEqual(to: other.origin)
      && size.isApproximatelyEqual(to: other.size)
  }
}

extension NSPoint {
  func isApproximatelyEqual(to other: NSPoint) -> Bool {
    abs(x - other.x) < 1.0 && abs(y - other.y) < 1.0
  }
}
