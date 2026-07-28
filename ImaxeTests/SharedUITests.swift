// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import AppKit
@testable import Imaxe
import SwiftUI
import Testing

@MainActor
@Suite("Shared UI")
struct SharedUITests {
  @Test func `color hex serializes grayscale colors as rgba`() {
    let color = Color(.sRGB, white: 0.5, opacity: 0.25)

    #expect(color.hex == "#80808040")
  }

  @Test func `color hex preserves rgb and alpha components`() {
    let color = Color(hex: "#33669980")

    #expect(color.hex == "#33669980")
  }

  @Test func `image collection single mode initializers compile`() {
    let items = [CollectionInitializerTestItem(id: 1)]

    _ = ImageCollectionView(
      items,
      listRow: { item, _ in
        Text("Row \(item.id)")
      },
    )

    _ = ImageCollectionView(
      items,
      gridItem: { item, _ in
        Text("Grid \(item.id)")
      },
    )

    _ = ImageCollectionView(
      items,
      listRow: { item, _ in
        Text("Row \(item.id)")
      },
      contextMenu: { _ in
        Button("Inspect") {}
      },
    )

    _ = ImageCollectionView(
      items,
      gridItem: { item, _ in
        Text("Grid \(item.id)")
      },
      contextMenu: { _ in
        Button("Inspect") {}
      },
    )
  }

  @Test func `fixed window dimensions are finite and constrained`() {
    #expect(
      AppSettings.normalizedFixedLoadedImageWindowDimension(
        .nan,
        minimum: Constants.minimumWindowContentWidth,
      ) == Double(Constants.minimumWindowContentWidth),
    )
    #expect(
      AppSettings.normalizedFixedLoadedImageWindowDimension(
        1,
        minimum: Constants.minimumWindowContentHeight,
      ) == Double(Constants.minimumWindowContentHeight),
    )
    #expect(
      AppSettings.normalizedFixedLoadedImageWindowDimension(
        20000,
        minimum: Constants.minimumWindowContentHeight,
      ) == 10000,
    )
  }

  @Test func `text input focus is detected in attached popover windows`() {
    let parentWindow = NSWindow()
    let popoverWindow = NSWindow()
    let textView = NSTextView()
    popoverWindow.contentView = textView
    parentWindow.addChildWindow(popoverWindow, ordered: .above)

    #expect(parentWindow.isAttachedTo(parentWindow))
    #expect(popoverWindow.isAttachedTo(parentWindow))
    #expect(popoverWindow.makeFirstResponder(textView))
    #expect(parentWindow.focusedTextView(scope: .windowTree) === textView)
  }

  @Test func `noneditable text views do not suppress image navigation`() {
    let window = NSWindow()
    let textView = NSTextView()
    textView.isEditable = false
    window.contentView = textView

    #expect(window.makeFirstResponder(textView))
    #expect(window.focusedTextView() == nil)
    #expect(window.focusedTextView(isEditable: nil) === textView)
  }

  @Test func `navigation shortcuts move the cursor in an attached text input`() throws {
    let parentWindow = NSWindow()
    let popoverWindow = NSWindow()
    let textView = NSTextView()
    textView.string = "filename"
    popoverWindow.contentView = textView
    parentWindow.addChildWindow(popoverWindow, ordered: .above)

    #expect(popoverWindow.makeFirstResponder(textView))
    textView.setSelectedRange(NSRange(location: 0, length: textView.string.count))
    let leftArrowEvent = try #require(horizontalArrowEvent(keyCode: 123, characters: "\u{F702}"))
    #expect(AppDelegate.routeHorizontalArrowKey(leftArrowEvent, in: popoverWindow) == nil)
    #expect(textView.selectedRange() == NSRange(location: 0, length: 0))

    popoverWindow.makeFirstResponder(nil)
    #expect(popoverWindow.makeFirstResponder(textView))
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    let rightArrowEvent = try #require(horizontalArrowEvent(keyCode: 124, characters: "\u{F703}"))
    #expect(AppDelegate.routeHorizontalArrowKey(rightArrowEvent, in: parentWindow) == nil)
    #expect(textView.selectedRange() == NSRange(location: 1, length: 0))
  }

  private func horizontalArrowEvent(keyCode: UInt16, characters: String) -> NSEvent? {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: characters,
      charactersIgnoringModifiers: characters,
      isARepeat: false,
      keyCode: keyCode,
    )
  }

  private struct CollectionInitializerTestItem: Identifiable {
    let id: Int
  }
}
