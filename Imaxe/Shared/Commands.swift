// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import AppKit
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
    if let recentImagesValue {
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
            Button {
              if let imageSession {
                imageSession.openRecentImage(recentImage)
              } else if let homeViewModel {
                homeViewModel.openRecentImage(recentImage)
              }
            } label: {
              Label {
                Text(recentImage.url.lastPathComponent)
              } icon: {
                Image(nsImage: NSWorkspace.shared.icon(forFile: recentImage.url.filePath))
                  .resizable()
                  .scaledToFit()
                  .frame(width: 16, height: 16)
              }
            }
            .disabled(imageSession == nil && homeViewModel == nil)
          }

          Divider()

          Button("Clear Menu") {
            do {
              try RecentImagesStore.clear(in: modelContainer.mainContext)
            } catch {
              imageSession?.alertTitle = "Failed to Clear Recent Images"
              imageSession?.alertMessage = error.localizedDescription
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
      .disabled(imageSession?.currentMetadata == nil && imageSession?.currentDocument == nil)
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
      .disabled(imageSession?.currentDocument == nil)

      Button("Zoom Out") {
        imageSession?.zoomOut()
      }
      .keyboardShortcut("-", modifiers: .command)
      .disabled(imageSession?.currentDocument == nil)

      Button("Fit to Window") {
        imageSession?.fitToWindow()
      }
      .keyboardShortcut("0", modifiers: .command)
      .disabled(imageSession?.currentDocument == nil)

      Button("Actual Size") {
        imageSession?.setZoomScale(1.0)
      }
      .keyboardShortcut("1", modifiers: .command)
      .disabled(imageSession?.currentDocument == nil)

      Divider()

      Button("Pan Left") {
        imageSession?.pan(horizontal: -Constants.keyboardPanDistance, vertical: 0)
      }
      .keyboardShortcut(.leftArrow, modifiers: .option)
      .disabled(imageSession?.currentDocument == nil)

      Button("Pan Right") {
        imageSession?.pan(horizontal: Constants.keyboardPanDistance, vertical: 0)
      }
      .keyboardShortcut(.rightArrow, modifiers: .option)
      .disabled(imageSession?.currentDocument == nil)

      Button("Pan Up") {
        imageSession?.pan(horizontal: 0, vertical: -Constants.keyboardPanDistance)
      }
      .keyboardShortcut(.upArrow, modifiers: .option)
      .disabled(imageSession?.currentDocument == nil)

      Button("Pan Down") {
        imageSession?.pan(horizontal: 0, vertical: Constants.keyboardPanDistance)
      }
      .keyboardShortcut(.downArrow, modifiers: .option)
      .disabled(imageSession?.currentDocument == nil)

      Divider()
    }
  }
}
