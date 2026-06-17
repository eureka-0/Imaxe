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
        .configureWindow { window in
          window.isMovableByWindowBackground = true
        }
        .ignoresSafeArea()
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .defaultSize(width: 900, height: 630)
    .restorationBehavior(.disabled)
    .commands {
      FileOperationCommands()
    }
  }
}

private struct WindowConfigurator: NSViewRepresentable {
  let configure: (NSWindow) -> Void

  func makeNSView(context _: Context) -> NSView {
    let view = NSView()
    configureWindow(for: view)
    return view
  }

  func updateNSView(_ nsView: NSView, context _: Context) {
    configureWindow(for: nsView)
  }

  private func configureWindow(for view: NSView) {
    DispatchQueue.main.async {
      guard let window = view.window else { return }
      configure(window)
    }
  }
}

private extension View {
  func configureWindow(_ configure: @escaping (NSWindow) -> Void) -> some View {
    background(WindowConfigurator(configure: configure))
  }
}
