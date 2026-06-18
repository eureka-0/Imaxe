//
//  ImageView+Topbar.swift
//  Imagxe
//
//  Created by lxlong on 2026/6/18.
//

import SwiftUI

extension ImageView {
  var topBar: some View {
    HStack {
      Spacer()
      fitToWindowButton
      scaleText
      fitWindowToImageButton
      pinWindowButton
    }
    .frame(height: 30)
    .padding(.horizontal, 10)
    .background(.thinMaterial)
    .labelStyle(.iconOnly)
    .buttonStyle(.plain)
  }

  private var fitToWindowButton: some View {
    Button("Fit to Window", systemImage: "arrow.up.left.and.down.right.magnifyingglass") {
      viewModel.fitToWindow()
    }
    .keyboardShortcut("f", modifiers: .command)
    .disabled(viewModel.currentImage == nil)
    .help(Text("Fit the image to the window"))
  }

  private var scaleText: some View {
    Text(Double(viewModel.imageScale), format: .percent.precision(.fractionLength(0)))
      .frame(width: 56)
      .padding(.vertical, 3)
      .background(.gray.opacity(0.3))
      .clipShape(.rect(cornerRadius: 8))
      .disabled(viewModel.currentImage == nil)
  }

  private var fitWindowToImageButton: some View {
    Button("Fit Window to Image", systemImage: "rectangle.and.arrow.up.right.and.arrow.down.left") {
      viewModel.fitWindowToImage()
    }
    .disabled(viewModel.currentImage == nil)
    .help(Text("Resize the window to fit the image"))
  }

  private var pinWindowButton: some View {
    Button("Pin Window", systemImage: viewModel.isWindowPinned ? "pin.slash" : "pin") {
      viewModel.toggleWindowPinning()
    }
    .keyboardShortcut("p", modifiers: .command)
    .help(Text("Toggle window pinning"))
  }
}
