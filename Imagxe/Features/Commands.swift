//
//  Commands.swift
//  Imagxe
//
//  Created by lxlong on 2026/6/17.
//

import SwiftUI

struct FileOperationCommands: Commands {
  @FocusedValue(ContentViewModel.self) private var contentViewModel

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("Open Image...") {
        contentViewModel?.openImage()
      }
      .keyboardShortcut("o", modifiers: .command)
      .disabled(contentViewModel == nil)
    }
  }
}
