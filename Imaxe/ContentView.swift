//
//  ContentView.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/14.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @State private var viewModel = ContentViewModel()

  var body: some View {
    Group {
      if let image = viewModel.importedImage {
        ImageView(image: image)
      } else {
        HomeView()
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
        importedImage = image
      }

      // Stop accessing once finished
      if gotAccess {
        url.stopAccessingSecurityScopedResource()
      }

    case let .failure(error):
      print("Failed to open file: \(error.localizedDescription)")
    }
  }
}

#Preview {
  ContentView()
}
