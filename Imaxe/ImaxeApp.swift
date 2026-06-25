//
//  ImaxeApp.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/14.
//

import SwiftUI

@main
struct ImaxeApp: App {
  @AppStorage(AppSettings.Keys.appearance.rawValue)
  private var appearance: Appearance = AppSettings.Defaults.appearance

  var body: some Scene {
    WindowGroup {
      ContentView()
        .applyAppearance(appearance)
        .ignoresSafeArea()
        .frame(
          minWidth: Constants.minimumWindowContentWidth,
          minHeight: Constants.minimumWindowContentHeight,
        )
        .configureWindow { window in
          window.isMovableByWindowBackground = true
        }
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .defaultSize(width: 680, height: 520)
    .restorationBehavior(.disabled)
    .commands {
      FileOperationCommands()
      ViewCommands()
    }

    Settings {
      SettingsView()
        .applyAppearance(appearance)
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

  func applyAppearance(_ appearance: Appearance) -> some View {
    onAppear {
      switch appearance {
      case .light: NSApp.appearance = NSAppearance(named: .aqua)
      case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
      case .system: NSApp.appearance = nil
      }
    }
    .onChange(of: appearance) { _, newValue in
      switch newValue {
      case .light: NSApp.appearance = NSAppearance(named: .aqua)
      case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
      case .system: NSApp.appearance = nil
      }
    }
  }
}
