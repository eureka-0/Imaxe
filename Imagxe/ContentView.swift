//
//  ContentView.swift
//  Imagxe
//
//  Created by lxlong on 2026/6/14.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @State private var viewModel = ContentViewModel()

  var body: some View {
    Group {
      if let image = viewModel.importedImage {
        ImageView(
          image: image,
          fitToWindowRequest: viewModel.fitToWindowRequest,
          scale: viewModel.imageScale,
          onScaleChange: viewModel.setImageScale,
        )
      } else {
        Text("No image imported")
          .foregroundStyle(.secondary)
          .padding()
      }
    }
    .focusedSceneValue(viewModel)
    .fileImporter(
      isPresented: $viewModel.isImporterPresented,
      allowedContentTypes: [.image],
      onCompletion: viewModel.onOpenImage,
    )
  }
}

@Observable
final class ContentViewModel {
  var isImporterPresented = false
  private(set) var fitToWindowRequest = 0
  private(set) var imageScale: CGFloat = 1.0
  private(set) var importedImage: NSImage?

  func openImage() {
    isImporterPresented = true
  }

  func onOpenImage(result: Result<URL, Error>) {
    switch result {
    case let .success(url):
      // Start accessing the security-scoped resource if your app is Sandboxed
      let gotAccess = url.startAccessingSecurityScopedResource()

      // Initialize NSImage from the selected file URL
      if let image = NSImage(contentsOf: url) {
        // Reset state first so the next view update starts from a known scale.
        imageScale = 1.0
        importedImage = image
        // Queue a fit after the new image is attached to the scroll view.
        fitToWindow()

        #if DEBUG
          debugPrint("New image imported successfully: \(url.lastPathComponent)")
          debugPrint("Image size: \(image.size.width) x \(image.size.height)")
          debugPrint("Image scale: \(imageScale)")
        #endif
      }

      // Stop accessing once finished
      if gotAccess {
        url.stopAccessingSecurityScopedResource()
      }

    case let .failure(error):
      print("Failed to open file: \(error.localizedDescription)")
    }
  }

  func setImageScale(_ scale: CGFloat) {
    imageScale = scale
  }

  func fitToWindow() {
    fitToWindowRequest += 1
  }
}

#Preview {
  ContentView()
}
