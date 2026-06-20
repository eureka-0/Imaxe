//
//  ImageView.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/17.
//

import SwiftUI

struct ImageView: View {
  @Bindable var imageSession: ImageSession

  var body: some View {
    ZStack(alignment: .top) {
      ImageScrollView(
        loadedImage: imageSession.currentImage,
        fitToWindowRequest: imageSession.fitToWindowRequest,
        fitWindowToImageRequest: imageSession.fitWindowToImageRequest,
        scale: $imageSession.imageScale,
        alwaysFitToWindow: $imageSession.alwaysFitToWindow,
      )

      topBar
        .opacity(imageSession.showTopBar ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: imageSession.showTopBar)
        .allowsHitTesting(imageSession.showTopBar)

      HoverTrackingStrip { isHovering in
        imageSession.setTopBarVisibility(to: isHovering)
      }
      .frame(maxWidth: .infinity)
      .frame(height: Constants.topBarHoverStripHeight)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      imageSession.setTopBarVisibility(to: false)

      DispatchQueue.main.async {
        imageSession.fitToWindow()
      }
    }
    .alert(item: $imageSession.alert) { alert in
      Alert(title: Text(alert.title), message: Text(alert.message))
    }
  }

  var topBar: some View {
    HStack(spacing: 12) {
      Spacer()
      navigationButtons
      fitToWindowButton
      scaleText
      fitWindowToImageButton
      pinWindowButton
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .padding(.horizontal, 10)
    .background(.regularMaterial.opacity(0.8))
    .frame(height: Constants.topBarHeight)
    .labelStyle(.iconOnly)
    .buttonStyle(TopBarButtonStyle())
  }

  @ViewBuilder
  private var navigationButtons: some View {
    Button(action: imageSession.navigateToPreviousImage) {
      Image(systemName: "chevron.left")
    }
    .disabled(!imageSession.folderNavigator.canNavigateToPrevious)

    HStack {
      Spacer(minLength: 0)
      Text(imageSession.folderNavigator.positionDescription)
      Spacer(minLength: 0)
    }
    .frame(width: 60)
    .padding(.vertical, 3)
    .background(.gray)

    Button(action: imageSession.navigateToNextImage) {
      Image(systemName: "chevron.right")
    }
    .disabled(!imageSession.folderNavigator.canNavigateToNext)
  }

  private var fitToWindowButton: some View {
    Button(action: imageSession.fitToWindow) {
      Label("Fit to Window", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
    }
    .keyboardShortcut("f", modifiers: .command)
    .help(Text("Fit the image to the window"))
  }

  private var scaleText: some View {
    Text(Double(imageSession.imageScale), format: .percent.precision(.fractionLength(0)))
      .frame(width: 56)
      .padding(.vertical, 3)
      .background(.gray.opacity(0.3))
      .clipShape(.rect(cornerRadius: 8))
  }

  private var fitWindowToImageButton: some View {
    Button(action: imageSession.fitWindowToImage) {
      Label("Fit Window to Image", systemImage: "rectangle.and.arrow.up.right.and.arrow.down.left")
    }
    .help(Text("Resize the window to fit the image"))
  }

  private var pinWindowButton: some View {
    Button(action: imageSession.toggleWindowPinning) {
      Label("Pin Window", systemImage: imageSession.isWindowPinned ? "pin.slash" : "pin")
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
