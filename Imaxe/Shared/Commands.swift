//
//  Commands.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/17.
//

import SwiftData
import SwiftUI

private struct RecentImagesKey: FocusedValueKey {
  typealias Value = [RecentImage]
}

extension FocusedValues {
  var recentImages: [RecentImage]? {
    get { self[RecentImagesKey.self] }
    set { self[RecentImagesKey.self] = newValue }
  }
}

// MARK: - FileOperationCommands

struct FileOperationCommands: Commands {
  @FocusedValue(ImageSession.self) private var imageSession
  @FocusedValue(HomeViewModel.self) private var homeViewModel
  @FocusedValue(\.recentImages) private var recentImagesValue
  @Environment(\.openWindow) private var openWindow

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
    CommandGroup(replacing: .newItem) {
      Button("Open Home Window") {
        openWindow(id: "home")
      }
      .keyboardShortcut("n", modifiers: [.command])
      .disabled(imageSession == nil && homeViewModel != nil)

      Divider()

      Button("Open Image...") {
        if let imageSession {
          imageSession.isImporterPresented = true
        } else {
          homeViewModel?.isImporterPresented = true
        }
      }
      .keyboardShortcut("o", modifiers: .command)
      .disabled(imageSession == nil && homeViewModel == nil)

      Button("Open from Pasteboard") {
        if let imageSession {
          imageSession.openImageFromPasteboard()
        } else if let homeViewModel {
          homeViewModel.openImageFromPasteboard()
        }
      }
      .keyboardShortcut("v", modifiers: [.command, .option])
      .disabled(imageSession == nil && homeViewModel == nil)

      Menu("Open Recent") {
        if recentImages.isEmpty {
          Button("No Recent Items") {}
            .disabled(true)
        } else {
          ForEach(recentImages) { recentImage in
            Button(recentImage.fileName) {
              if let imageSession {
                imageSession.openRecentImage(recentImage)
              } else if let homeViewModel {
                homeViewModel.openRecentImage(recentImage)
              }
            }
            .disabled(imageSession == nil && homeViewModel == nil)
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

// MARK: - ViewCommands

struct ViewCommands: Commands {
  @FocusedValue(ImageSession.self) private var imageSession

  var body: some Commands {
    CommandGroup(replacing: .sidebar) {
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
