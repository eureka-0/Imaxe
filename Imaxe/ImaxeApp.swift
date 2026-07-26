//
//  ImaxeApp.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/14.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_: Notification) {
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      Self.routeHorizontalArrowKey(event, in: event.window)
    }
  }

  static func routeHorizontalArrowKey(_ event: NSEvent, in window: NSWindow?) -> NSEvent? {
    let arrowKeyCodes: Set<UInt16> = [123, 124] // left: 123, right: 124
    guard arrowKeyCodes.contains(event.keyCode),
          let textView = window?.focusedTextView(scope: .windowTree)
    else {
      return event
    }

    textView.keyDown(with: event)
    return nil
  }
}

@main
struct ImaxeApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  @AppStorage(AppSettings.Keys.appearance.rawValue)
  private var appearance: Appearance = AppSettings.Defaults.appearance

  private let modelContainer: ModelContainer

  init() {
    let modelFileURL = URL.dataDirectory.appendingPathComponent("database.sqlite")
    do {
      try FileManager.default.ensureExists(for: URL.dataDirectory)
      let modelConfiguration = ModelConfiguration(url: modelFileURL)
      modelContainer = try ModelContainer(for: RecentImage.self, configurations: modelConfiguration)

      #if DEBUG
        AppLogger.shared.setDestination(to: .console)
        appLog("Application initialized", level: .info, category: .general)
        appLog(
          "Supported image types: \(ImageLoader.supportedImageUTTypesDescription)",
          level: .debug,
          category: .imageLoading,
        )

        appLog(
          "Model file URL: \(modelFileURL.filePath)",
          level: .debug,
          category: .persistence,
        )
      #else
        AppLogger.shared.setDestination(to: .file)
        appLog("Application initialized", level: .info, category: .general)
      #endif
    } catch {
      do {
        modelContainer = try ModelContainer(
          for: RecentImage.self,
          configurations: ModelConfiguration(isStoredInMemoryOnly: true),
        )
        appLog(
          "Persistent recent images are unavailable; using temporary storage.",
          level: .error,
          category: .persistence,
        )
      } catch {
        fatalError("Failed to create fallback model container: \(error)")
      }
    }
  }

  var body: some Scene {
    Group {
      Window("Home", id: "home") {
        HomeView()
          .configureAppWindow(appearance: appearance, shouldIgnoreSafeArea: true)
          .frame(width: Constants.defaultWindowWidth, height: Constants.defaultWindowHeight)
      }
      .windowStyle(.hiddenTitleBar)
      .windowResizability(.contentSize)
      .defaultSize(width: Constants.defaultWindowWidth, height: Constants.defaultWindowHeight)
      .defaultLaunchBehavior(.presented)
      .restorationBehavior(.disabled)

      WindowGroup("Image", id: "image", for: ImageWindowRequest.self) { $request in
        ContentView(request: request)
          .configureAppWindow(appearance: appearance, shouldIgnoreSafeArea: true)
          .frame(
            minWidth: Constants.minimumWindowContentWidth,
            minHeight: Constants.minimumWindowContentHeight,
          )
      }
      .windowStyle(.hiddenTitleBar)
      .windowResizability(.contentSize)
      .defaultSize(width: Constants.defaultWindowWidth, height: Constants.defaultWindowHeight)
      .defaultLaunchBehavior(.suppressed)
      .restorationBehavior(.disabled)
      .handlesExternalEvents(matching: ["*"])

      Settings {
        SettingsView()
          .applyAppearance(appearance)
      }
    }
    .modelContainer(modelContainer)
    .commands {
      CommandGroup(replacing: .toolbar) {}
      FileOperationCommands(modelContainer: modelContainer)
      ViewCommands()
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
  func configureAppWindow(
    appearance: Appearance? = nil,
    shouldIgnoreSafeArea: Bool = false,
  ) -> some View {
    Group {
      if let appearance, shouldIgnoreSafeArea {
        applyAppearance(appearance)
          .ignoresSafeArea()
      } else if let appearance {
        applyAppearance(appearance)
      } else if shouldIgnoreSafeArea {
        ignoresSafeArea()
      } else {
        self
      }
    }
    .configureWindow { window in
      window.isMovableByWindowBackground = true
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.tabbingMode = .disallowed
    }
  }

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
