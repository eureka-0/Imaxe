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
    .windowToolbarStyle(.automatic)
    .windowResizability(.contentSize)
    .defaultSize(width: 900, height: 600)
    .commands {
      FileOperationCommands()
    }
  }
}
