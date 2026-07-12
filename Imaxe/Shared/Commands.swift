//
//  Commands.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/17.
//

import SwiftData
import SwiftUI

private struct OpenImageActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

private struct RecentImagesKey: FocusedValueKey {
  typealias Value = [RecentImage]
}

private struct OpenRecentImageActionKey: FocusedValueKey {
  typealias Value = (RecentImage) -> Void
}

extension FocusedValues {
  var openImageAction: (() -> Void)? {
    get { self[OpenImageActionKey.self] }
    set { self[OpenImageActionKey.self] = newValue }
  }

  var recentImages: [RecentImage]? {
    get { self[RecentImagesKey.self] }
    set { self[RecentImagesKey.self] = newValue }
  }

  var openRecentImageAction: ((RecentImage) -> Void)? {
    get { self[OpenRecentImageActionKey.self] }
    set { self[OpenRecentImageActionKey.self] = newValue }
  }
}

struct FileOperationCommands: Commands {
  @FocusedValue(ImageSession.self) private var imageSession
  @FocusedValue(\.openImageAction) private var openImageAction
  @FocusedValue(\.recentImages) private var recentImagesValue
  @FocusedValue(\.openRecentImageAction) private var openRecentImageAction

  let modelContainer: ModelContainer

  private var recentImages: [RecentImage] {
    if let imageSession {
      Array(imageSession.recentImages.prefix(Constants.maximumRecentImagesToDisplayInMenu))
    } else if let recentImagesValue {
      Array(recentImagesValue.prefix(Constants.maximumRecentImagesToDisplayInMenu))
    } else {
      []
    }
  }

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Divider()

      Button("Open Image...") {
        if let imageSession {
          imageSession.isImporterPresented = true
        } else {
          openImageAction?()
        }
      }
      .keyboardShortcut("o", modifiers: .command)
      .disabled(imageSession == nil && openImageAction == nil)

      Button("Open from Pasteboard") {
        imageSession?.openImageFromPasteboard()
      }
      .disabled(imageSession == nil)

      Menu("Open Recent") {
        if recentImages.isEmpty {
          Button("No Recent Items") {}
            .disabled(true)
        } else {
          ForEach(recentImages) { recentImage in
            Button(recentImage.fileName) {
              if let imageSession {
                imageSession.openRecentImage(recentImage)
              } else if let openRecentImageAction {
                openRecentImageAction(recentImage)
              }
            }
            .disabled(imageSession == nil && openRecentImageAction == nil)
          }

          Divider()

          Button("Clear Menu") {
            do {
              try RecentImagesStore.clear(in: modelContainer.mainContext)
            } catch {
              imageSession?.alert = ImageAlert(
                title: "Failed to Clear Recent Images",
                message: error.localizedDescription,
              )
            }
          }
        }
      }
      .disabled(false)

      Divider()

      Button("Reveal in Finder") {
        imageSession?.revealInFinder()
      }
      .keyboardShortcut("r", modifiers: [.command, .shift])
      .disabled(imageSession?.currentImageInfo == nil && imageSession?.currentImage == nil)
    }
  }
}

struct ViewCommands: Commands {
  @FocusedValue(ImageSession.self) private var imageSession

  var body: some Commands {
    CommandGroup(after: .sidebar) {
      Button("Previous Image") {
        imageSession?.navigateToPreviousImage()
      }
      .keyboardShortcut(.leftArrow, modifiers: [])
      .disabled(imageSession?.folderNavigator?.canNavigateToPrevious != true)

      Button("Next Image") {
        imageSession?.navigateToNextImage()
      }
      .keyboardShortcut(.rightArrow, modifiers: [])
      .disabled(imageSession?.folderNavigator?.canNavigateToNext != true)

      Divider()

      Button("Zoom In") {
        imageSession?.zoomIn()
      }
      .keyboardShortcut("+", modifiers: .command)
      .disabled(imageSession?.currentImage == nil)

      Button("Zoom Out") {
        imageSession?.zoomOut()
      }
      .keyboardShortcut("-", modifiers: .command)
      .disabled(imageSession?.currentImage == nil)

      Button("Fit to Window") {
        imageSession?.fitToWindow()
      }
      .keyboardShortcut("0", modifiers: .command)
      .disabled(imageSession?.currentImage == nil)

      Button("Actual Size") {
        imageSession?.setZoomScale(1.0)
      }
      .keyboardShortcut("1", modifiers: .command)
      .disabled(imageSession?.currentImage == nil)

      Divider()
    }
  }
}
