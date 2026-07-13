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

  private var isShowingImageInterface: Bool {
    imageSession.currentImage != nil || imageSession.isLoading
  }

  var body: some View {
    Group {
      if isShowingImageInterface {
        ImageView(imageSession: imageSession)
      } else {
        Color.clear
      }
    }
    .navigationTitle(imageSession.folderNavigator?.currentImageURL.lastPathComponent ?? "Imaxe")
    .focusedSceneValue(imageSession)
    .dismissTextFocusOnClickOutside()
    .onAppear {
      imageSession.topBarHideDelay = topBarHideDelay
      imageSession.enableLoopBrowsing = enableLoopBrowsing
      imageSession.actionOnImageFileChange = actionOnImageFileChange
      imageSession.recordRecentImage = { url in
        try await RecentImagesStore.recordOpened(url, in: modelContext)
      }
      imageSession.removeRecentImage = { path in
        try RecentImagesStore.remove(path: path, in: modelContext)
      }
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
    .onChange(of: recentImagesCountLimit) { _, _ in
      refreshRecentImages()
    }
    .onChange(of: isShowingImageInterface) { _, newValue in
      if !newValue {
        imageSession.restoreStandardWindowButtons()
      }
    }
    .fileImporter(
      isPresented: $imageSession.isImporterPresented,
      allowedContentTypes: ImageLoader.supportedImageTypes,
    ) { result in
      imageSession.onOpenImage(result: result, openWindow: openWindow)
    }
    .alert(imageSession.alert?.title ?? "", isPresented: $imageSession.showAlert) {
      Button("OK") {
        guard didFailInitialRequest else { return }
        if let request {
          DispatchQueue.main.async {
            dismissWindow(id: "image", value: request)
          }
        }
        openWindow(id: "home")
      }
    } message: {
      Text(imageSession.alert?.message ?? "")
    }
    .onOpenURL { url in
      imageSession.loadImage(from: url)
      dismissWindow(id: "home")
    }
    .handlesExternalEvents(preferring: [], allowing: [])
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
      imageSession.recentImages = try RecentImagesStore.fetchRecentImages(in: modelContext)
    } catch {
      imageSession.recentImages = recentImages
      imageSession.alert = ImageAlert(
        title: "Failed to Refresh Recent Images",
        message: error.localizedDescription,
      )
    }
  }

  private func openImages(at urls: [URL]) {
    guard !urls.isEmpty else { return }

    for url in urls {
      openWindow(id: "image", value: ImageWindowRequest(url: url))
    }
    dismissWindow(id: "home")
  }
}
