//
//  Modifiers.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/13.
//

import AppKit
import SwiftUI

// MARK: Helpers

enum HorizontalTextMovement {
  case left
  case right
}

enum TextInputFocusState {
  static func isTextInputActive(in window: NSWindow) -> Bool {
    editableTextView(in: window) != nil
  }

  static func isWindow(_ window: NSWindow, attachedTo rootWindow: NSWindow) -> Bool {
    var currentWindow: NSWindow? = window
    while let candidate = currentWindow {
      if candidate === rootWindow {
        return true
      }
      currentWindow = candidate.parent
    }
    return false
  }

  static func handleHorizontalTextMovement(
    _ movement: HorizontalTextMovement,
    for event: NSEvent?,
  ) -> Bool {
    guard event?.type == .keyDown else { return false }
    return handleHorizontalTextMovement(
      movement,
      in: event?.window ?? NSApp.keyWindow,
    )
  }

  static func handleHorizontalTextMovement(
    _ movement: HorizontalTextMovement,
    in window: NSWindow?,
  ) -> Bool {
    guard
      let window,
      let textView = editableTextView(inWindowTreeContaining: window)
    else {
      return false
    }

    switch movement {
    case .left:
      textView.moveLeft(nil)
    case .right:
      textView.moveRight(nil)
    }
    return true
  }

  private static func editableTextView(inWindowTreeContaining window: NSWindow) -> NSTextView? {
    var rootWindow = window
    while let parent = rootWindow.parent {
      rootWindow = parent
    }
    return editableTextView(in: rootWindow)
  }

  private static func editableTextView(in window: NSWindow) -> NSTextView? {
    if let textView = window.firstResponder as? NSTextView, textView.isEditable {
      return textView
    }

    for childWindow in window.childWindows ?? [] {
      if let textView = editableTextView(in: childWindow) {
        return textView
      }
    }
    return nil
  }
}

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
          TextInputFocusState.isWindow(window, attachedTo: trackedWindow),
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
