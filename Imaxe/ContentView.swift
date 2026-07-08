//
//  ContentView.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/14.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \RecentImage.lastOpenedAt, order: .reverse) private var recentImages: [RecentImage]

  @State private var imageSession = ImageSession()
  @State private var isTargetedForDrop = false

  @AppStorage(AppSettings.Keys.topBarHideDelay.rawValue)
  private var topBarHideDelay = AppSettings.Defaults.topBarHideDelay

  @AppStorage(AppSettings.Keys.enableLoopBrowsing.rawValue)
  private var enableLoopBrowsing = AppSettings.Defaults.enableLoopBrowsing

  @AppStorage(AppSettings.Keys.actionOnImageFileChange.rawValue)
  private var actionOnImageFileChange = AppSettings.Defaults.actionOnImageFileChange

  private var isShowingImageInterface: Bool {
    imageSession.currentImage != nil || imageSession.isLoading
  }

  var body: some View {
    Group {
      if isShowingImageInterface {
        ImageView(imageSession: imageSession)
      } else {
        HomeView(imageSession: imageSession)
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
    .dismissTextFocusOnClickOutside()
    .onAppear {
      imageSession.topBarHideDelay = topBarHideDelay
      imageSession.enableLoopBrowsing = enableLoopBrowsing
      imageSession.actionOnImageFileChange = actionOnImageFileChange
      imageSession.recordRecentImage = { url in
        try RecentImagesStore.recordOpened(url, in: modelContext)
      }
      imageSession.removeRecentImage = { path in
        try RecentImagesStore.remove(path: path, in: modelContext)
      }
      refreshRecentImages()
    }
    .onChange(of: recentImages) { _, newValue in
      imageSession.recentImages = newValue
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
    .onChange(of: isShowingImageInterface) { _, newValue in
      if !newValue {
        imageSession.restoreStandardWindowButtons()
      }
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

  private func refreshRecentImages() {
    do {
      let removedCount = try RecentImagesStore.removeMissingFiles(in: modelContext)
      if removedCount > 0 {
        imageSession.recentImages = try RecentImagesStore.fetchRecentImages(in: modelContext)
      } else {
        imageSession.recentImages = recentImages
      }
    } catch {
      imageSession.recentImages = recentImages
      imageSession.alert = ImageAlert(
        title: "Failed to Refresh Recent Images",
        message: error.localizedDescription,
      )
    }
  }
}

#Preview {
  ContentView()
    .modelContainer(for: [RecentImage.self], inMemory: true)
}
