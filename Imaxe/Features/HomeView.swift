//
//  HomeView.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/17.
//

import SwiftUI

struct HomeView: View {
  @State private var viewModel = HomeViewModel()

  var body: some View {
    VStack {
      HStack {
        Spacer()

        SettingsLink {
          Label("Settings", systemImage: "gearshape")
        }
        .buttonStyle(.borderless)
        .padding(.top, 8)
        .padding(.horizontal)
      }

      Spacer()

      Text("Welcome to Imaxe")
        .font(.largeTitle)
        .padding()

      Text("Import an image to get started.")
        .foregroundStyle(.secondary)
        .padding()

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
