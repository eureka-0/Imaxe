//
//  HomeView.swift
//  Imagxe
//
//  Created by lxlong on 2026/6/17.
//

import SwiftUI

struct HomeView: View {
  @State private var viewModel = HomeViewModel()

  var body: some View {
    VStack {
      Text("Welcome to Imagxe")
        .font(.largeTitle)
        .padding()

      Text("Import an image to get started.")
        .foregroundStyle(.secondary)
        .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
