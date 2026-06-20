//
//  Extensions.swift
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
