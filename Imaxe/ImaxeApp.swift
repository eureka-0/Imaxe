//
//  ImaxeApp.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/14.
//

import SwiftData
import SwiftUI

@main
struct ImaxeApp: App {
  @AppStorage(AppSettings.Keys.appearance.rawValue)
  private var appearance: Appearance = AppSettings.Defaults.appearance

  private let modelContainer: ModelContainer

  init() {
    do {
      let modelFileURL = URL.dataDirectory.appendingPathComponent("database.sqlite")

      #if DEBUG
        debugPrint("Model file URL: \(modelFileURL.fileSystemPath)")
      #endif

      let modelConfiguration = ModelConfiguration(url: modelFileURL)
      modelContainer = try ModelContainer(for: RecentImage.self, configurations: modelConfiguration)
    } catch {
      fatalError("Failed to create model container: \(error)")
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .ignoresSafeArea()
        .applyAppearance(appearance)
        .frame(
          minWidth: Constants.minimumWindowContentWidth,
          minHeight: Constants.minimumWindowContentHeight,
        )
        .configureWindow { window in
          window.isMovableByWindowBackground = true
          window.titleVisibility = .hidden
          window.titlebarAppearsTransparent = true
        }
    }
    .modelContainer(modelContainer)
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .defaultSize(width: Constants.defaultWindowWidth, height: Constants.defaultWindowHeight)
    .restorationBehavior(.disabled)
    .commands {
      FileOperationCommands(modelContainer: modelContainer)
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
