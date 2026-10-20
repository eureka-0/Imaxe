// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import SwiftUI

struct HoverTrackingStrip: NSViewRepresentable {
  let onHoverChange: (Bool, NSWindow?) -> Void

  func makeNSView(context _: Context) -> HoverTrackingNSView {
    let view = HoverTrackingNSView()
    view.onHoverChange = onHoverChange
    return view
  }

  func updateNSView(_ nsView: HoverTrackingNSView, context _: Context) {
    nsView.onHoverChange = onHoverChange
  }

  static func dismantleNSView(_ nsView: HoverTrackingNSView, coordinator _: ()) {
    nsView.resetHovering()
    nsView.onHoverChange = nil
  }

  final class HoverTrackingNSView: NSView {
    var onHoverChange: ((Bool, NSWindow?) -> Void)?

    private var isHovering = false
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
      nil
    }

    override func hitTest(_: NSPoint) -> NSView? {
      nil
    }

    override func updateTrackingAreas() {
      if let trackingArea {
        removeTrackingArea(trackingArea)
      }

      let trackingArea = NSTrackingArea(
        rect: .zero,
        options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
        owner: self,
        userInfo: nil,
      )
      addTrackingArea(trackingArea)
      self.trackingArea = trackingArea

      super.updateTrackingAreas()
    }

    override func mouseEntered(with _: NSEvent) {
      setHovering(true)
    }

    override func mouseExited(with _: NSEvent) {
      setHovering(false)
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()

      if let window {
        onHoverChange?(isHovering, window)
      } else {
        resetHovering()
      }
    }

    private func setHovering(_ isHovering: Bool) {
      guard self.isHovering != isHovering else { return }

      self.isHovering = isHovering
      onHoverChange?(isHovering, window)
    }

    func resetHovering() {
      setHovering(false)
    }
  }
}
