//
//  Utilities.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/18.
//

import Foundation
import SwiftUI

extension CGFloat {
  func roundedDownToPixel(scale: CGFloat) -> CGFloat {
    guard scale > 0 else { return self }
    return floor(self * scale) / scale
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

extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}

extension NSImage {
  var pixelSize: NSSize {
    var representationSize = NSSize.zero

    for representation in representations {
      representationSize.width = max(representationSize.width, CGFloat(representation.pixelsWide))
      representationSize.height = max(representationSize.height, CGFloat(representation.pixelsHigh))
    }

    if representationSize.width > 0, representationSize.height > 0 {
      return representationSize
    }

    return size
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

extension NSSize {
  func isApproximatelyEqual(to other: NSSize) -> Bool {
    abs(width - other.width) < 1.0 && abs(height - other.height) < 1.0
  }
}

extension NSWindow {
  func setStandardButtonsVisibility(to showWindowButtons: Bool) {
    standardWindowButton(.closeButton)?.isHidden = !showWindowButtons
    standardWindowButton(.miniaturizeButton)?.isHidden = !showWindowButtons
    standardWindowButton(.zoomButton)?.isHidden = !showWindowButtons
  }
}
