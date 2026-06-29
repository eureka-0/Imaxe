//
//  Utilities.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/18.
//

import AppKit
import OSLog
import SwiftUI

nonisolated struct IntSize: Hashable {
  let width: Int
  let height: Int

  var isValid: Bool {
    width > 0 && height > 0
  }

  var nsSize: NSSize {
    NSSize(width: width, height: height)
  }

  init(width: Int = 0, height: Int = 0) {
    self.width = width
    self.height = height
  }

  init(nsSize: NSSize) {
    if !nsSize.isApproximatelyInt {
      debugPrint("Warning: NSSize \(nsSize) is not approximately integer.")
    }

    width = Int(nsSize.width.rounded())
    height = Int(nsSize.height.rounded())
  }
}

extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}

extension NSBitmapImageRep {
  var gifFrameCount: Int? {
    (value(forProperty: .frameCount) as? NSNumber)?.intValue
  }

  var currentGIFFrame: Int? {
    (value(forProperty: .currentFrame) as? NSNumber)?.intValue
  }

  func currentGIFFrameDuration(fallback: Double = 0.1) -> Double {
    let duration = (value(forProperty: .currentFrameDuration) as? NSNumber)?.doubleValue
    if let duration, duration > 0 {
      return duration
    } else {
      return fallback
    }
  }
}

extension NSImage {
  nonisolated var pixelSize: NSSize {
    var pixelSize = NSSize.zero
    for representation in representations {
      pixelSize.width = max(pixelSize.width, CGFloat(representation.pixelsWide))
      pixelSize.height = max(pixelSize.height, CGFloat(representation.pixelsHigh))
    }

    if pixelSize.width > 0, pixelSize.height > 0 {
      return pixelSize
    }

    return size.validSize
  }

  nonisolated func pixelSize(preferred preferredSize: NSSize?) -> NSSize {
    if let preferredSize, preferredSize.width > 0, preferredSize.height > 0 {
      return preferredSize
    }

    return pixelSize
  }

  var animatedGIFRepresentation: NSBitmapImageRep? {
    representations
      .compactMap { $0 as? NSBitmapImageRep }
      .first { bitmapRep in
        let frameCount = bitmapRep.gifFrameCount ?? 0
        return frameCount > 1
      }
  }
}

extension NSRect {
  func constrained(to visibleFrame: NSRect) -> NSRect {
    var rect = self
    rect.size.width = min(rect.width, visibleFrame.width)
    rect.size.height = min(rect.height, visibleFrame.height)

    if rect.maxX > visibleFrame.maxX {
      rect.origin.x = visibleFrame.maxX - rect.width
    }
    if rect.minX < visibleFrame.minX {
      rect.origin.x = visibleFrame.minX
    }
    if rect.maxY > visibleFrame.maxY {
      rect.origin.y = visibleFrame.maxY - rect.height
    }
    if rect.minY < visibleFrame.minY {
      rect.origin.y = visibleFrame.minY
    }

    return rect
  }
}

extension NSScreen {
  func getPPI() -> (width: CGFloat, height: CGFloat)? {
    guard let displayID =
      deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    else {
      return nil
    }

    let physicalSize = CGDisplayScreenSize(displayID)
    let physicalSizeInInches = CGSize(
      width: physicalSize.width / 25.4,
      height: physicalSize.height / 25.4,
    )

    let ppiWidth = frame.width * backingScaleFactor / physicalSizeInInches.width
    let ppiHeight = frame.height * backingScaleFactor / physicalSizeInInches.height
    return (width: ppiWidth, height: ppiHeight)
  }
}

extension NSSize {
  nonisolated var validSize: NSSize {
    if width > 0, height > 0 {
      self
    } else {
      NSSize(width: 1, height: 1)
    }
  }

  nonisolated var isApproximatelyInt: Bool {
    abs(width.rounded() - width) < 0.1 && abs(height.rounded() - height) < 0.1
  }

  nonisolated var intSize: IntSize {
    IntSize(nsSize: self)
  }

  func isApproximatelyEqual(to other: NSSize) -> Bool {
    abs(width - other.width) < 1.0 && abs(height - other.height) < 1.0
  }
}

extension NSView {
  func backingAlignedSize(
    _ size: NSSize, options: AlignmentOptions = [.alignAllEdgesNearest],
  ) -> NSSize {
    backingAlignedRect(NSRect(origin: .zero, size: size), options: options).size
  }

  func backingAlignedPoint(
    _ point: NSPoint, options: AlignmentOptions = [.alignAllEdgesNearest],
  ) -> NSPoint {
    backingAlignedRect(NSRect(origin: point, size: .zero), options: options).origin
  }
}

extension NSWindow {
  var titlebarHeight: CGFloat {
    frame.height - contentLayoutRect.height
  }

  func resizeToDefaultSize() {
    setContentSize(NSSize(
      width: Constants.defaultWindowWidth,
      height: Constants.defaultWindowHeight - titlebarHeight,
    ))
  }

  func setStandardButtonsVisibility(to showWindowButtons: Bool) {
    standardWindowButton(.closeButton)?.isHidden = !showWindowButtons
    standardWindowButton(.miniaturizeButton)?.isHidden = !showWindowButtons
    standardWindowButton(.zoomButton)?.isHidden = !showWindowButtons
  }

  func convertFromBacking(_ size: CGSize) -> CGSize {
    convertFromBacking(NSRect(origin: .zero, size: size)).size
  }

  func centeredConstrainedFrame(_ windowSize: NSSize) -> NSRect {
    let clampedWindowSize = NSSize(
      width: max(windowSize.width, Constants.minimumWindowContentWidth),
      height: max(windowSize.height, Constants.minimumWindowContentHeight + titlebarHeight),
    )
    let frame = NSRect(
      x: frame.midX - clampedWindowSize.width / 2.0,
      y: frame.midY - clampedWindowSize.height / 2.0,
      width: clampedWindowSize.width,
      height: clampedWindowSize.height,
    )

    if let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
      return frame.constrained(to: visibleFrame)
    }

    return frame
  }
}

extension ShapeStyle where Self == Color {
  static var windowBackground: Color {
    Color(nsColor: .windowBackgroundColor)
  }

  static var controlBackground: Color {
    Color(nsColor: .controlBackgroundColor)
  }

  static var controlAccent: Color {
    Color(nsColor: .controlAccentColor)
  }

  static var controlText: Color {
    Color(nsColor: .controlTextColor)
  }

  static var separator: Color {
    Color(nsColor: .separatorColor)
  }

  func fromHex(_ hex: String) -> Color {
    var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

    var rgb: UInt64 = 0
    Scanner(string: hexSanitized).scanHexInt64(&rgb)

    let r = Double((rgb & 0xFF0000) >> 16) / 255.0
    let g = Double((rgb & 0x00FF00) >> 8) / 255.0
    let b = Double(rgb & 0x0000FF) / 255.0

    return Color(red: r, green: g, blue: b)
  }
}

extension UserDefaults {
  @objc dynamic var imageActualSizeStrategy: String? {
    string(forKey: AppSettings.Keys.imageActualSizeStrategy.rawValue)
  }

  @objc dynamic var imageInterpolationStrategy: String? {
    string(forKey: AppSettings.Keys.imageInterpolationStrategy.rawValue)
  }

  var imageActualSizeStrategyValue: ImageActualSizeStrategy {
    imageActualSizeStrategy.flatMap { ImageActualSizeStrategy(rawValue: $0) }
      ?? AppSettings.Defaults.imageActualSizeStrategy
  }

  var imageInterpolationStrategyValue: ImageInterpolationStrategy {
    imageInterpolationStrategy.flatMap { ImageInterpolationStrategy(rawValue: $0) }
      ?? AppSettings.Defaults.imageInterpolationStrategy
  }
}
