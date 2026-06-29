//
//  ContentView.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/14.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @State private var imageSession = ImageSession()
  @State private var isTargetedForDrop = false

  @AppStorage(AppSettings.Keys.topBarHideDelay.rawValue)
  private var topBarHideDelay = AppSettings.Defaults.topBarHideDelay

  @AppStorage(AppSettings.Keys.enableLoopBrowsing.rawValue)
  private var enableLoopBrowsing = AppSettings.Defaults.enableLoopBrowsing

  @AppStorage(AppSettings.Keys.actionOnImageFileChange.rawValue)
  private var actionOnImageFileChange = AppSettings.Defaults.actionOnImageFileChange

  var body: some View {
    Group {
      if imageSession.currentImage != nil || imageSession.isLoading {
        ImageView(imageSession: imageSession)
      } else {
        HomeView()
      }
    }
    .navigationTitle(imageSession.folderNavigator?.currentImageURL.lastPathComponent ?? "Imaxe")
    .overlay(
      ContainerRelativeShape()
        .strokeBorder(
          isTargetedForDrop ? Color.accentColor : .clear,
          lineWidth: 3,
        ),
    )
    .focusedSceneValue(imageSession)
    .onAppear {
      imageSession.topBarHideDelay = topBarHideDelay
      imageSession.enableLoopBrowsing = enableLoopBrowsing
      imageSession.actionOnImageFileChange = actionOnImageFileChange
    }
    .onChange(of: topBarHideDelay) { _, newValue in
      imageSession.topBarHideDelay = newValue
    }
    .onChange(of: enableLoopBrowsing) { _, newValue in
      imageSession.enableLoopBrowsing = newValue
    }
    .onChange(of: actionOnImageFileChange) { _, newValue in
      imageSession.actionOnImageFileChange = newValue
    }
    .fileImporter(
      isPresented: $imageSession.isImporterPresented,
      allowedContentTypes: ImageLoader.supportedImageTypes,
      onCompletion: imageSession.onOpenImage,
    )
    .alert(item: $imageSession.alert) { alert in
      Alert(title: Text(alert.title), message: Text(alert.message))
    }
    .dropDestination(for: URL.self) { urls, _ in
      guard let url = urls.first else { return false }

      imageSession.loadImage(from: url)
      return true
    } isTargeted: { isTargeted in
      isTargetedForDrop = isTargeted
    }
    .onOpenURL { url in
      imageSession.loadImage(from: url)
    }
  }
}

#Preview {
  ContentView()
}
