//
//  SharedUITests.swift
//  ImaxeTests
//
//  Created by lxlong on 2026/6/14.
//

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

    #expect(TextInputFocusState.isWindow(popoverWindow, attachedTo: parentWindow))
    #expect(popoverWindow.makeFirstResponder(textView))
    #expect(TextInputFocusState.isTextInputActive(in: parentWindow))
  }

  @Test func `noneditable text views do not suppress image navigation`() {
    let window = NSWindow()
    let textView = NSTextView()
    textView.isEditable = false
    window.contentView = textView

    #expect(window.makeFirstResponder(textView))
    #expect(!TextInputFocusState.isTextInputActive(in: window))
    #expect(!TextInputFocusState.handleHorizontalTextMovement(.left, in: window))
  }

  @Test func `navigation shortcuts move the cursor in an attached text input`() {
    let parentWindow = NSWindow()
    let popoverWindow = NSWindow()
    let textView = NSTextView()
    textView.string = "filename"
    popoverWindow.contentView = textView
    parentWindow.addChildWindow(popoverWindow, ordered: .above)

    #expect(popoverWindow.makeFirstResponder(textView))
    textView.setSelectedRange(NSRange(location: 0, length: textView.string.count))
    #expect(TextInputFocusState.handleHorizontalTextMovement(.left, in: popoverWindow))
    #expect(textView.selectedRange() == NSRange(location: 0, length: 0))

    popoverWindow.makeFirstResponder(nil)
    #expect(popoverWindow.makeFirstResponder(textView))
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    #expect(TextInputFocusState.handleHorizontalTextMovement(.right, in: parentWindow))
    #expect(textView.selectedRange() == NSRange(location: 1, length: 0))
  }

  private struct CollectionInitializerTestItem: Identifiable {
    let id: Int
  }
}
