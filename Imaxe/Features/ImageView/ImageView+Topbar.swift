//
//  ImageView+Topbar.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/18.
//

import SwiftUI

extension ImageView {
  var topBar: some View {
    HStack(spacing: 12) {
      Spacer()
      fitToWindowButton
      scaleText
      fitWindowToImageButton
      pinWindowButton
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .padding(.horizontal, 10)
    .background(.black.opacity(0.7))
    .frame(height: 32)
    .labelStyle(.iconOnly)
    .buttonStyle(TopBarButtonStyle())
  }

  private var fitToWindowButton: some View {
    Button(action: viewModel.fitToWindow) {
      Label("Fit to Window", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
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
    Button(action: viewModel.fitWindowToImage) {
      Label("Fit Window to Image", systemImage: "rectangle.and.arrow.up.right.and.arrow.down.left")
    }
    .disabled(viewModel.currentImage == nil)
    .help(Text("Resize the window to fit the image"))
  }

  private var pinWindowButton: some View {
    Button(action: viewModel.toggleWindowPinning) {
      Label("Pin Window", systemImage: viewModel.isWindowPinned ? "pin.slash" : "pin")
    }
    .keyboardShortcut("p", modifiers: .command)
    .help(Text("Toggle window pinning"))
  }
}

private struct TopBarButtonStyle: ButtonStyle {
  @State private var isHovering = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(5)
      .background(isHovering ? Color.gray.opacity(0.5) : Color.clear)
      .clipShape(.rect(cornerRadius: 8))
      .onHover { isHovering in
        self.isHovering = isHovering
      }
  }
}
