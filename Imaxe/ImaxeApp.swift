// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import Combine
import Sparkle
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - CheckForUpdates

final class CheckForUpdatesViewModel: ObservableObject {
  @Published var canCheckForUpdates: Bool = false

  init(updater: SPUUpdater) {
    updater.publisher(for: \.canCheckForUpdates)
      .assign(to: &$canCheckForUpdates)
  }
}

struct CheckForUpdatesView: View {
  @ObservedObject var viewModel: CheckForUpdatesViewModel
  private let updater: SPUUpdater

  init(updater: SPUUpdater) {
    self.updater = updater
    viewModel = CheckForUpdatesViewModel(updater: updater)
  }

  var body: some View {
    Button("Check for Updates") {
      updater.checkForUpdates()
    }
    .disabled(!viewModel.canCheckForUpdates)
  }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationWillTerminate(_: Notification) {
    #if DEBUG
      TestStorage.current?.remove()
    #endif
  }

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

// MARK: - ImaxeApp

@main
struct ImaxeApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  @AppStorage(AppSettings.Keys.appearance.rawValue, store: AppSettings.userDefaults)
  private var appearance: Appearance = AppSettings.Defaults.appearance

  private let updaterController: SPUStandardUpdaterController
  private let modelContainer: ModelContainer

  init() {
    updaterController = SPUStandardUpdaterController(
      startingUpdater: !ProcessInfo.processInfo.arguments.contains("--disable-updates-for-testing"),
      updaterDelegate: nil,
      userDriverDelegate: nil,
    )
    let modelFileURL = URL.dataDirectory.appendingPathComponent("database.sqlite")
    do {
      try FileManager.default.ensureExists(for: URL.dataDirectory)
      let modelConfiguration = ModelConfiguration(url: modelFileURL)
      let container = try ModelContainer(for: RecentImage.self, configurations: modelConfiguration)

      #if DEBUG
        if TestStorage.current != nil,
           let pathsJSON = ProcessInfo.processInfo.environment["IMAXE_UI_TEST_RECENT_IMAGES"],
           let data = pathsJSON.data(using: .utf8)
        {
          let paths = try JSONDecoder().decode([String].self, from: data)
          for path in paths {
            container.mainContext.insert(RecentImage(url: URL(fileURLWithPath: path)))
          }
          try container.mainContext.save()
        }
      #endif
      modelContainer = container

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
        SettingsView(updater: updaterController.updater)
          .applyAppearance(appearance)
      }
    }
    .modelContainer(modelContainer)
    .commands {
      CommandGroup(after: .appInfo) {
        CheckForUpdatesView(updater: updaterController.updater)
      }
      CommandGroup(replacing: .toolbar) {}
      FileOperationCommands()
      ViewCommands()
    }
  }
}

// MARK: - Helpers

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
