//
//  SettingsView.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/23.
//

import SwiftUI

struct SettingsView: View {
  var body: some View {
    TabView {
      GeneralSettingsView()
        .tabItem { Label("General", systemImage: "gearshape") }

      ImageSettingsView()
        .tabItem { Label("Image", systemImage: "photo.on.rectangle") }
    }
    .scenePadding()
    .frame(width: 620)
  }
}

struct GeneralSettingsView: View {
  @AppStorage(AppSettings.Keys.appearance.rawValue)
  private var appearance = AppSettings.Defaults.appearance

  @AppStorage(AppSettings.Keys.topBarHideDelay.rawValue)
  private var topBarHideDelay = AppSettings.Defaults.topBarHideDelay

  @AppStorage(AppSettings.Keys.enableLoopBrowsing.rawValue)
  private var enableLoopBrowsing = AppSettings.Defaults.enableLoopBrowsing

  var body: some View {
    Form {
      Picker("Appearance:", selection: $appearance) {
        ForEach(Appearance.allCases) {
          Text($0.description).tag($0)
        }
      }
      .pickerStyle(.segmented)

      Picker("Top bar hide delay:", selection: $topBarHideDelay) {
        ForEach([0, 0.5, 1.0, 1.5, 2.0, 3.0, 5.0, 10.0], id: \.self) { delay in
          if delay == 1 {
            Text("\(delay, specifier: "%.1f") second").tag(delay)
          } else {
            Text("\(delay, specifier: "%.1f") seconds").tag(delay)
          }
        }
      }
      .pickerStyle(.menu)

      Toggle("Enable loop browsing:", isOn: $enableLoopBrowsing)
        .toggleStyle(SettingsToggleStyle())
    }
  }
}

struct ImageSettingsView: View {
  @AppStorage(AppSettings.Keys.imageActualSizeStrategy.rawValue)
  private var imageActualSizeStrategy = AppSettings.Defaults.imageActualSizeStrategy

  @AppStorage(AppSettings.Keys.loadedImageWindowSizeMode.rawValue)
  private var loadedImageWindowSizeMode = AppSettings.Defaults.loadedImageWindowSizeMode

  @AppStorage(AppSettings.Keys.fixedLoadedImageWindowWidth.rawValue)
  private var fixedLoadedImageWindowWidth = AppSettings.Defaults.fixedLoadedImageWindowWidth

  @AppStorage(AppSettings.Keys.fixedLoadedImageWindowHeight.rawValue)
  private var fixedLoadedImageWindowHeight = AppSettings.Defaults.fixedLoadedImageWindowHeight

  @AppStorage(AppSettings.Keys.fixedLoadedImageWindowSizeUnit.rawValue)
  private var fixedLoadedImageWindowSizeUnit = AppSettings.Defaults.fixedLoadedImageWindowSizeUnit

  @FocusState private var widthInputFocused: Bool
  @FocusState private var heightInputFocused: Bool

  var body: some View {
    Form {
      Picker("Define 100% zoom as:", selection: $imageActualSizeStrategy) {
        ForEach(ImageActualSizeStrategy.allCases) {
          Text($0.description).tag($0)
        }
      }
      .pickerStyle(.menu)

      Picker("Default zoom level:", selection: $loadedImageWindowSizeMode) {
        ForEach(LoadedImageWindowSizeMode.allCases) {
          Text($0.description).tag($0)
        }
      }
      .pickerStyle(.menu)

      if loadedImageWindowSizeMode == .fixedSize {
        fixedLoadedImageWindowSizeField
      }
    }
  }

  private var fixedLoadedImageWindowSizeField: some View {
    LabeledContent("") {
      HStack(spacing: 5) {
        Text("Width:")

        TextField(
          "Width",
          value: $fixedLoadedImageWindowWidth,
          format: .number.precision(.fractionLength(0)),
        )
        .focused($widthInputFocused)
        .onSubmit {
          fixedLoadedImageWindowWidth = sanitizedWidth(fixedLoadedImageWindowWidth)
        }
        .onChange(of: widthInputFocused) { _, newValue in
          if !newValue {
            fixedLoadedImageWindowWidth = sanitizedWidth(fixedLoadedImageWindowWidth)
          }
        }
        .labelsHidden()
        .monospacedDigit()
        .frame(width: 62)

        Text("Height:")

        TextField(
          "Height",
          value: $fixedLoadedImageWindowHeight,
          format: .number.precision(.fractionLength(0)),
        )
        .focused($heightInputFocused)
        .onSubmit {
          fixedLoadedImageWindowHeight = sanitizedHeight(fixedLoadedImageWindowHeight)
        }
        .onChange(of: heightInputFocused) { _, newValue in
          if !newValue {
            fixedLoadedImageWindowHeight = sanitizedHeight(fixedLoadedImageWindowHeight)
          }
        }
        .labelsHidden()
        .monospacedDigit()
        .frame(width: 62)

        Picker("", selection: $fixedLoadedImageWindowSizeUnit) {
          ForEach(LoadedImageWindowSizeUnit.allCases) {
            Text($0.description).tag($0)
          }
        }
        .labelsHidden()

        if fixedLoadedImageWindowWidth != AppSettings.Defaults.fixedLoadedImageWindowWidth
          || fixedLoadedImageWindowHeight != AppSettings.Defaults.fixedLoadedImageWindowHeight
          || fixedLoadedImageWindowSizeUnit != AppSettings.Defaults.fixedLoadedImageWindowSizeUnit
        {
          Button("Reset", systemImage: "arrow.counterclockwise") {
            fixedLoadedImageWindowWidth = AppSettings.Defaults.fixedLoadedImageWindowWidth
            fixedLoadedImageWindowHeight = AppSettings.Defaults.fixedLoadedImageWindowHeight
            fixedLoadedImageWindowSizeUnit = AppSettings.Defaults.fixedLoadedImageWindowSizeUnit
          }
          .buttonStyle(.borderless)
          .labelStyle(.iconOnly)
        }
      }
    }
  }

  private func sanitizedWidth(_ value: Double) -> Double {
    value.clamped(to: Constants.minimumWindowContentWidth ... 10000)
  }

  private func sanitizedHeight(_ value: Double) -> Double {
    value.clamped(to: Constants.minimumWindowContentHeight ... 10000)
  }
}

private struct SettingsToggleStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    LabeledContent {
      Toggle("", isOn: configuration.$isOn)
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
    } label: {
      configuration.label
    }
  }
}
