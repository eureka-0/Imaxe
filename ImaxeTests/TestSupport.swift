//
//  TestSupport.swift
//  ImaxeTests
//
//  Created by lxlong on 2026/6/14.
//

@testable import Imaxe
import SwiftUI
import Testing

@MainActor
enum TestSupport {
  static func sampleImageURL(_ fileName: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "Images/\(fileName)")
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

  static func withRecentImagesCountLimit<T>(
    _ limit: Int?,
    operation: () throws -> T,
  ) throws -> T {
    let key = AppSettings.Keys.recentImagesCountLimit.rawValue
    let previousValue = UserDefaults.standard.object(forKey: key)
    defer {
      restoreUserDefault(previousValue, forKey: key)
    }

    setRecentImagesCountLimit(limit, forKey: key)
    return try operation()
  }

  static func withRecentImagesCountLimit<T>(
    _ limit: Int?,
    operation: () async throws -> T,
  ) async throws -> T {
    let key = AppSettings.Keys.recentImagesCountLimit.rawValue
    let previousValue = UserDefaults.standard.object(forKey: key)
    defer {
      restoreUserDefault(previousValue, forKey: key)
    }

    setRecentImagesCountLimit(limit, forKey: key)
    return try await operation()
  }

  static func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping () -> Bool,
  ) async throws {
    let start = ContinuousClock.now

    while !condition() {
      if start.duration(to: .now) > timeout {
        Issue.record("Timed out waiting for condition.")
        return
      }
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  private static func setRecentImagesCountLimit(_ limit: Int?, forKey key: String) {
    if let limit {
      UserDefaults.standard.set(limit, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  private static func restoreUserDefault(_ value: Any?, forKey key: String) {
    if let value {
      UserDefaults.standard.set(value, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }
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
