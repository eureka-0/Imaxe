//
//  Commands.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/17.
//

import SwiftUI

struct FileOperationCommands: Commands {
  @FocusedValue(ImageSession.self) private var imageSession

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("Open Image...") {
        imageSession?.openImage()
      }
      .keyboardShortcut("o", modifiers: .command)
      .disabled(imageSession == nil)
    }
  }
}
