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
  let request: ImageWindowRequest?

  @Environment(\.dismissWindow) private var dismissWindow
  @Environment(\.openWindow) private var openWindow
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \RecentImage.lastOpenedAt, order: .reverse) private var recentImages: [RecentImage]

  @State private var imageSession = ImageSession()
  @State private var didFailInitialRequest = false
  @State private var didLoadInitialURL = false
  @State private var isTargetedForDrop = false

  @AppStorage(AppSettings.Keys.topBarHideDelay.rawValue)
  private var topBarHideDelay = AppSettings.Defaults.topBarHideDelay

  @AppStorage(AppSettings.Keys.enableLoopBrowsing.rawValue)
  private var enableLoopBrowsing = AppSettings.Defaults.enableLoopBrowsing

  @AppStorage(AppSettings.Keys.actionOnImageFileChange.rawValue)
  private var actionOnImageFileChange = AppSettings.Defaults.actionOnImageFileChange

  @AppStorage(AppSettings.Keys.recentImagesCountLimit.rawValue)
  private var recentImagesCountLimit = AppSettings.Defaults.recentImagesCountLimit

  private var imageSessionPreferences: ImageSession.Preferences {
    ImageSession.Preferences(
      topBarHideDelay: topBarHideDelay,
      enableLoopBrowsing: enableLoopBrowsing,
      actionOnImageFileChange: actionOnImageFileChange,
    )
  }

  var body: some View {
    ImageView(
      imageSession: imageSession,
      onAlertAcknowledged: handleImageAlertAcknowledged,
    )
    .navigationTitle(imageSession.currentMetadata?.fileName ?? "Imaxe")
    .focusedSceneValue(imageSession)
    .focusedSceneValue(\.recentImages, recentImages)
    .dismissTextFocusOnClickOutside()
    .onAppear {
      configureImageSession()
      updateRecentImageDirectories()
      refreshRecentImages()
      loadInitialRequestIfNeeded()
      dismissWindow(id: "home")
    }
    .onDisappear {
      imageSession.close()
    }
    .overlay(
      ContainerRelativeShape()
        .strokeBorder(
          isTargetedForDrop ? Color.accentColor : .clear,
          lineWidth: 3,
        ),
    )
    .dropDestination(for: URL.self) { urls, _ in
      openImages(at: urls)
      return !urls.isEmpty
    } isTargeted: { isTargeted in
      isTargetedForDrop = isTargeted
    }
    .onChange(of: imageSessionPreferences) { _, newValue in
      imageSession.apply(newValue)
    }
    .onChange(of: recentImagesCountLimit) {
      refreshRecentImages()
    }
    .onChange(of: recentImages.map(\.path)) {
      updateRecentImageDirectories()
    }
    .onOpenURL { url in
      imageSession.loadImage(from: url)
      dismissWindow(id: "home")
    }
    .handlesExternalEvents(preferring: [], allowing: [])
  }

  private func configureImageSession() {
    imageSession.apply(imageSessionPreferences)
    imageSession.recordRecentImage = { url in
      try await RecentImagesStore.recordOpened(url, in: modelContext)
    }
    imageSession.removeRecentImage = { path in
      try RecentImagesStore.remove(path: path, in: modelContext)
    }
    imageSession.updateRecentImageLocation = { oldPath, newURL in
      try await RecentImagesStore.updateLocation(
        from: oldPath,
        to: newURL,
        in: modelContext,
      )
    }
  }

  private func handleImageAlertAcknowledged() {
    guard didFailInitialRequest else { return }
    didFailInitialRequest = false
    if let request {
      DispatchQueue.main.async {
        dismissWindow(id: "image", value: request)
      }
    }
    openWindow(id: "home")
  }

  private func loadInitialRequestIfNeeded() {
    guard !didLoadInitialURL, let request else { return }
    didLoadInitialURL = true
    imageSession.loadImage(
      from: request.url,
      addToRecent: request.addsToRecent,
      recentImagePathToRemoveOnFileNotFound: request.recentImagePath,
      temporaryURL: request.temporaryURL,
      onFailure: {
        didFailInitialRequest = true
      },
    )
  }

  private func refreshRecentImages() {
    do {
      _ = try RecentImagesStore.fetchRecentImages(in: modelContext)
    } catch {
      imageSession.alertTitle = "Failed to Refresh Recent Images"
      imageSession.alertMessage = error.localizedDescription
    }
  }

  private func updateRecentImageDirectories() {
    imageSession.updateRecentImageDirectoryURLs(
      recentImages.map { $0.url.deletingLastPathComponent() },
    )
  }

  private func openImages(at urls: [URL]) {
    guard !urls.isEmpty else { return }

    for url in urls {
      openWindow(id: "image", value: ImageWindowRequest(url: url))
    }
    dismissWindow(id: "home")
  }
}
