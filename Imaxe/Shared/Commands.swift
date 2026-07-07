//
//  Commands.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/17.
//

import SwiftData
import SwiftUI

struct FileOperationCommands: Commands {
  @FocusedValue(ImageSession.self) private var imageSession

  let modelContainer: ModelContainer

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Divider()

      Button("Open Image...") {
        imageSession?.isImporterPresented = true
      }
      .keyboardShortcut("o", modifiers: .command)
      .disabled(imageSession == nil)

      Button("Open from Pasteboard") {
        imageSession?.openImageFromPasteboard()
      }
      .keyboardShortcut("v", modifiers: .command)
      .disabled(imageSession == nil)

      Menu("Open Recent") {
        if recentImages.isEmpty {
          Button("No Recent Items") {}
            .disabled(true)
        } else {
          ForEach(recentImages) { recentImage in
            Button(recentImage.fileName) {
              guard let imageSession else {
                NSSound.beep()
                return
              }

              imageSession.loadImage(from: recentImage.url)
            }
            .disabled(imageSession == nil)
          }

          Divider()

          Button("Clear Menu") {
            try? RecentImagesStore.clear(in: modelContainer.mainContext)
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

  private var recentImages: [RecentImage] {
    imageSession?.recentImages ?? []
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
