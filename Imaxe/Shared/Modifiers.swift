//
//  Modifiers.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/13.
//

import AppKit
import SwiftUI

// MARK: Helpers

private struct DismissTextFocusOnClickOutside: NSViewRepresentable {
  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> NSView {
    let view = WindowTrackingView(frame: .zero)
    view.onWindowChange = { [weak coordinator = context.coordinator] window in
      coordinator?.trackedWindow = window
    }
    context.coordinator.install()
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.trackedWindow = nsView.window
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    if let view = nsView as? WindowTrackingView {
      view.onWindowChange = nil
    }
    coordinator.trackedWindow = nil
    coordinator.uninstall()
  }

  final class Coordinator {
    private var monitor: Any?
    weak var trackedWindow: NSWindow?

    func install() {
      guard monitor == nil else { return }

      monitor = NSEvent.addLocalMonitorForEvents(matching: [
        .leftMouseDown,
        .rightMouseDown,
      ]) { [weak self] event in
        guard
          let self,
          let trackedWindow,
          let window = event.window,
          window.isAttachedTo(trackedWindow),
          let contentView = window.contentView
        else {
          return event
        }

        let location = contentView.convert(event.locationInWindow, from: nil)
        if let hitView = contentView.hitTest(location),
           !TextFocusPreservingRegistry.shared.contains(event.locationInWindow, in: window),
           !hitView.preservesTextFocus,
           !hitView.isInsideTextInput
        {
          window.makeFirstResponder(nil)
        }

        return event
      }
    }

    func uninstall() {
      if let monitor {
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
      }
    }
  }
}

private struct TextFocusPreservingArea: NSViewRepresentable {
  func makeNSView(context _: Context) -> NSView {
    let view = TextFocusPreservingView(frame: .zero)
    view.autoresizingMask = [.width, .height]
    return view
  }

  func updateNSView(_ nsView: NSView, context _: Context) {
    nsView.needsLayout = true
  }
}

private final class TextFocusPreservingView: NSView {
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    TextFocusPreservingRegistry.shared.register(self)
  }
}

private final class TextFocusPreservingRegistry {
  static let shared = TextFocusPreservingRegistry()

  private let views = NSHashTable<TextFocusPreservingView>.weakObjects()

  func register(_ view: TextFocusPreservingView) {
    views.add(view)
  }

  func contains(_ locationInWindow: NSPoint, in window: NSWindow) -> Bool {
    views.allObjects.contains { view in
      guard view.window === window else { return false }

      let locationInView = view.convert(locationInWindow, from: nil)
      return view.bounds.contains(locationInView)
    }
  }
}

// MARK: View Modifiers

extension View {
  func dismissTextFocusOnClickOutside() -> some View {
    background(DismissTextFocusOnClickOutside().frame(width: 0, height: 0))
  }

  func preservesTextFocusOnClick() -> some View {
    overlay {
      TextFocusPreservingArea()
        .allowsHitTesting(false)
    }
  }
}

// MARK: NSView Extensions

extension NSView {
  var preservesTextFocus: Bool {
    if self is TextFocusPreservingView {
      return true
    }

    return superview?.preservesTextFocus ?? false
  }

  var isInsideTextInput: Bool {
    if self is NSTextField || self is NSTextView || self is NSSearchField {
      return true
    }

    return superview?.isInsideTextInput ?? false
  }

  func backingAlignedSize(
    _ size: NSSize,
    options: AlignmentOptions = [.alignAllEdgesNearest],
  ) -> NSSize {
    backingAlignedRect(NSRect(origin: .zero, size: size), options: options).size
  }

  func backingAlignedPoint(
    _ point: NSPoint,
    options: AlignmentOptions = [.alignAllEdgesNearest],
  ) -> NSPoint {
    backingAlignedRect(NSRect(origin: point, size: .zero), options: options).origin
  }
}

private final class WindowTrackingView: NSView {
  var onWindowChange: ((NSWindow?) -> Void)?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    onWindowChange?(window)
  }
}
