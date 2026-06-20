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
      if let imageSession = viewModel.imageSession {
        ImageView(imageSession: imageSession)
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
    .alert(item: $viewModel.alert) { alert in
      Alert(title: Text(alert.title), message: Text(alert.message))
    }
  }
}

@Observable
final class ContentViewModel {
  var isImporterPresented = false
  private(set) var imageSession: ImageSession?
  var alert: ImageAlert?

  func openImage() {
    isImporterPresented = true
  }

  func onOpenImage(result: Result<URL, Error>) {
    switch result {
    case let .success(url):
      do {
        let loadedImage = try ImageLoader.shared.load(from: url)
        imageSession = ImageSession(loadedImage: loadedImage)
      } catch {
        alert = ImageAlert(title: "Failed to Open Image", message: error.localizedDescription)
      }

    case let .failure(error):
      print("Failed to open file: \(error.localizedDescription)")
    }
  }
}

#Preview {
  ContentView()
}
