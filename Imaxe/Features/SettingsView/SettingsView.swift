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

  var body: some View {
    Form {
      Picker("Appearance:", selection: $appearance) {
        ForEach(Appearance.allCases) {
          Text($0.description).tag($0)
        }
      }
      .pickerStyle(.segmented)
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
  private var fixedLoadedImageWindowSizeUnit =
    AppSettings.Defaults.fixedLoadedImageWindowSizeUnit

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
    .onChange(of: fixedLoadedImageWindowWidth) { _, newValue in
      fixedLoadedImageWindowWidth = sanitizedWidth(newValue)
    }
    .onChange(of: fixedLoadedImageWindowHeight) { _, newValue in
      fixedLoadedImageWindowHeight = sanitizedHeight(newValue)
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
        .labelsHidden()
        .monospacedDigit()
        .frame(width: 52)

        Text("Height:")

        TextField(
          "Height",
          value: $fixedLoadedImageWindowHeight,
          format: .number.precision(.fractionLength(0)),
        )
        .labelsHidden()
        .monospacedDigit()
        .frame(width: 52)

        Picker("", selection: $fixedLoadedImageWindowSizeUnit) {
          ForEach(LoadedImageWindowSizeUnit.allCases) {
            Text($0.description).tag($0)
          }
        }
        .labelsHidden()
      }
    }
  }

  private func sanitizedWidth(_ value: Double) -> Double {
    guard value.isFinite, value > 0 else {
      return AppSettings.Defaults.fixedLoadedImageWindowWidth
    }
    return value.clamped(to: Constants.minimumWindowContentWidth ... 10000)
  }

  private func sanitizedHeight(_ value: Double) -> Double {
    guard value.isFinite, value > 0 else {
      return AppSettings.Defaults.fixedLoadedImageWindowHeight
    }
    return value.clamped(to: Constants.minimumWindowContentHeight ... 10000)
  }
}
