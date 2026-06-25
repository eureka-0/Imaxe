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
    .frame(width: 520)
  }
}

struct GeneralSettingsView: View {
  @AppStorage(AppSettings.Keys.appearance.rawValue)
  private var appearance = AppSettings.Defaults.appearance

  var body: some View {
    Form {
      Picker("Appearance:", selection: $appearance) {
        ForEach(Appearance.allCases) {
          Text($0.id).tag($0)
        }
      }
      .pickerStyle(.segmented)
    }
  }
}

struct ImageSettingsView: View {
  @AppStorage(AppSettings.Keys.imageActualSizeStrategy.rawValue)
  private var imageActualSizeStrategy = AppSettings.Defaults.imageActualSizeStrategy

  var body: some View {
    Form {
      Picker("Define 100% zoom as:", selection: $imageActualSizeStrategy) {
        ForEach(ImageActualSizeStrategy.allCases) {
          Text($0.description).tag($0)
        }
      }
      .pickerStyle(.inline)
    }
  }
}
