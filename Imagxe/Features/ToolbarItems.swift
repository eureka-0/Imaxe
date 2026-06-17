//
//  ToolbarItems.swift
//  Imagxe
//
//  Created by lxlong on 2026/6/17.
//

import SwiftUI

struct ToolbarItems: ToolbarContent {
  let contentViewModel: ContentViewModel?

  var body: some ToolbarContent {
    ToolbarItem {
      Button("Fit to Window", systemImage: "arrow.up.left.and.down.right.magnifyingglass") {
        contentViewModel?.fitToWindow()
      }
      .keyboardShortcut("f", modifiers: .command)
      .disabled(contentViewModel == nil)
    }

    ToolbarSpacer(.fixed)

    ToolbarItem {
      Text(
        Double(contentViewModel?.imageScale ?? 1.0),
        format: .percent.precision(.fractionLength(0)),
      )
      .frame(width: 60)
      .disabled(contentViewModel == nil)
    }
  }
}
