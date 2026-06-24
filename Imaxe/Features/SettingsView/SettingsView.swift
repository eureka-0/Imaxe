//
//  SettingsView.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/23.
//

import SwiftUI

struct SettingsView: View {
  @AppStorage(AppSettings.Keys.appearance.rawValue)
  private var appearance: Appearance = AppSettings.Defaults.appearance

  var body: some View {
    TabView {
      generalSettings
        .tabItem { Label("General", systemImage: "gearshape") }
    }
    .scenePadding()
    .frame(width: 520)
  }

  var generalSettings: some View {
    Form {
      Picker("Appearance", selection: $appearance) {
        ForEach(Appearance.allCases) {
          Text($0.id).tag($0)
        }
      }
      .pickerStyle(SegmentedPickerStyle())
    }
  }
}
