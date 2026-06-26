//
//  Utilities.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/18.
//

import AppKit
import Foundation
import SwiftUI

struct WindowViewportSizingContext {
  let screen: NSScreen?
  let visibleFrame: NSRect
  let viewportContentDelta: NSSize
  let minimumContentSize: NSSize
  let maximumContentSize: NSSize
  let maxViewportSize: NSSize
}

struct WindowViewportResizeTarget {
  let frame: NSRect
  let viewportSize: NSSize
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

extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
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

  func positioned(within visibleFrame: NSRect) -> NSRect {
    var rect = self

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
  func isApproximatelyEqual(to other: NSSize) -> Bool {
    abs(width - other.width) < 1.0 && abs(height - other.height) < 1.0
  }
}

extension NSView {
  func backingAlignedSize(
    _ size: NSSize, roundingRule: FloatingPointRoundingRule = .down,
  ) -> NSSize {
    let backingSize = convertToBacking(size)
    let alignedBackingSize = NSSize(
      width: backingSize.width.rounded(roundingRule),
      height: backingSize.height.rounded(roundingRule),
    )
    return convertFromBacking(alignedBackingSize)
  }

  func backingAlignedPoint(
    _ point: NSPoint, roundingRule: FloatingPointRoundingRule = .toNearestOrAwayFromZero,
  ) -> NSPoint {
    let backingPoint = convertToBacking(point)
    let alignedBackingPoint = NSPoint(
      x: backingPoint.x.rounded(roundingRule),
      y: backingPoint.y.rounded(roundingRule),
    )
    return convertFromBacking(alignedBackingPoint)
  }
}

extension NSWindow {
  func setStandardButtonsVisibility(to showWindowButtons: Bool) {
    standardWindowButton(.closeButton)?.isHidden = !showWindowButtons
    standardWindowButton(.miniaturizeButton)?.isHidden = !showWindowButtons
    standardWindowButton(.zoomButton)?.isHidden = !showWindowButtons
  }

  func convertFromBacking(_ size: CGSize) -> CGSize {
    convertFromBacking(NSRect(origin: .zero, size: size)).size
  }

  func viewportResizeTarget(
    forViewportSize viewportSize: NSSize,
    in sizingContext: WindowViewportSizingContext,
    aligningViewportIn view: NSView,
  ) -> WindowViewportResizeTarget {
    let targetViewportSize = view.backingAlignedSize(
      NSSize(width: max(1, viewportSize.width), height: max(1, viewportSize.height)),
    )
    let targetContentSize = contentSize(
      forViewportSize: targetViewportSize,
      in: sizingContext,
    )
    let effectiveViewportSize = NSSize(
      width: max(1, targetContentSize.width - sizingContext.viewportContentDelta.width),
      height: max(1, targetContentSize.height - sizingContext.viewportContentDelta.height),
    )
    let targetFrame = centeredFrame(forContentSize: targetContentSize)
    let constrainedFrame = constrainedBackingAlignedFrame(targetFrame, in: sizingContext)
    return WindowViewportResizeTarget(frame: constrainedFrame, viewportSize: effectiveViewportSize)
  }

  func contentSize(
    forViewportSize viewportSize: NSSize,
    in sizingContext: WindowViewportSizingContext,
  ) -> NSSize {
    NSSize(
      width: Self.clampedDimension(
        viewportSize.width + sizingContext.viewportContentDelta.width,
        minimum: sizingContext.minimumContentSize.width,
        maximum: sizingContext.maximumContentSize.width,
      ),
      height: Self.clampedDimension(
        viewportSize.height + sizingContext.viewportContentDelta.height,
        minimum: sizingContext.minimumContentSize.height,
        maximum: sizingContext.maximumContentSize.height,
      ),
    )
  }

  func centeredFrame(forContentSize contentSize: NSSize) -> NSRect {
    let frameSize = frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
    return NSRect(
      x: frame.midX - frameSize.width / 2.0,
      y: frame.midY - frameSize.height / 2.0,
      width: frameSize.width,
      height: frameSize.height,
    )
  }

  func constrainedBackingAlignedFrame(
    _ frame: NSRect,
    in sizingContext: WindowViewportSizingContext,
  ) -> NSRect {
    let constrainedFrame = constrainFrameRect(
      frame.positioned(within: sizingContext.visibleFrame),
      to: sizingContext.screen,
    )
    let backingAlignedFrame = backingAlignedScreenFrame(
      constrainedFrame,
      screen: sizingContext.screen,
    )
    return constrainFrameRect(
      backingAlignedFrame.positioned(within: sizingContext.visibleFrame),
      to: sizingContext.screen,
    )
  }

  @discardableResult func correctFrameToMatchViewportIfNeeded(
    _ desiredViewportSize: NSSize,
    actualViewportSize: NSSize,
    sizingContext: WindowViewportSizingContext,
    aligningViewportIn view: NSView,
  ) -> Bool {
    let desiredBackingSize = view.convertToBacking(desiredViewportSize)
    let actualBackingSize = view.convertToBacking(actualViewportSize)
    let overageInBackingPixels = NSSize(
      width: actualBackingSize.width - desiredBackingSize.width,
      height: actualBackingSize.height - desiredBackingSize.height,
    )
    let maxOverage = max(overageInBackingPixels.width, overageInBackingPixels.height)

    guard maxOverage > 0.25, maxOverage <= 1.25 else { return false }

    let correctedTarget = viewportResizeTarget(
      forViewportSize: desiredViewportSize,
      in: sizingContext,
      aligningViewportIn: view,
    )
    guard !frame.isApproximatelyEqual(to: correctedTarget.frame) else { return false }

    setFrame(correctedTarget.frame, display: true)
    return true
  }

  private func backingAlignedScreenFrame(_ frame: NSRect, screen: NSScreen?) -> NSRect {
    if let screen {
      return screen.backingAlignedRect(
        frame,
        options: [
          .alignMinXNearest,
          .alignMinYNearest,
          .alignWidthNearest,
          .alignHeightNearest,
        ],
      )
    }

    let scale = max(1, backingScaleFactor)
    return NSRect(
      x: (frame.origin.x * scale).rounded() / scale,
      y: (frame.origin.y * scale).rounded() / scale,
      width: max(1 / scale, (frame.width * scale).rounded() / scale),
      height: max(1 / scale, (frame.height * scale).rounded() / scale),
    )
  }

  private static func clampedDimension(
    _ value: CGFloat, minimum: CGFloat, maximum: CGFloat,
  ) -> CGFloat {
    guard maximum >= minimum else { return maximum }
    return value.clamped(to: minimum ... maximum)
  }
}

extension NSRect {
  func isApproximatelyEqual(to other: NSRect) -> Bool {
    abs(origin.x - other.origin.x) < 0.5
      && abs(origin.y - other.origin.y) < 0.5
      && abs(width - other.width) < 0.5
      && abs(height - other.height) < 0.5
  }
}

extension UserDefaults {
  @objc dynamic var imageActualSizeStrategy: String? {
    string(forKey: AppSettings.Keys.imageActualSizeStrategy.rawValue)
  }

  var imageActualSizeStrategyValue: ImageActualSizeStrategy {
    imageActualSizeStrategy.flatMap { ImageActualSizeStrategy(rawValue: $0) }
      ?? AppSettings.Defaults.imageActualSizeStrategy
  }
}
