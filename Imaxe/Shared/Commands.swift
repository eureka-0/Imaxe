//
//  Commands.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/17.
//

import SwiftUI

struct FileOperationCommands: Commands {
  @FocusedValue(ImageSession.self) private var imageSession

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

      Divider()

      Button("Reveal in Finder") {
        imageSession?.revealCurrentImageInFinder()
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
        imageSession?.setScale(1.0)
      }
      .keyboardShortcut("1", modifiers: .command)
      .disabled(imageSession?.currentImage == nil)

      Divider()
    }
  }
}
