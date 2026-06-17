//
//  ImagxeApp.swift
//  Imagxe
//
//  Created by lxlong on 2026/6/14.
//

import SwiftUI

@main
struct ImagxeApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .commands {
      FileOperationCommands()
    }
  }
}

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
