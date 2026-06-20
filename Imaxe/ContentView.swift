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
      if let loadedImage = viewModel.importedImage {
        ImageView(loadedImage: loadedImage)
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
    .alert(isPresented: $viewModel.showErrorAlert) {
      Alert(title: Text(viewModel.alertTitle), message: Text(viewModel.errorMessage))
    }
  }
}

@Observable
final class ContentViewModel {
  var isImporterPresented = false
  private(set) var importedImage: LoadedImage?
  var showErrorAlert: Bool = false
  var alertTitle: String = "Error"
  var errorMessage: String = ""

  func openImage() {
    isImporterPresented = true
  }

  func onOpenImage(result: Result<URL, Error>) {
    switch result {
    case let .success(url):
      do {
        importedImage = try ImageLoader.shared.load(from: url)
      } catch {
        showErrorAlert = true
        alertTitle = "Failed to Open Image"
        errorMessage = error.localizedDescription
      }

    case let .failure(error):
      print("Failed to open file: \(error.localizedDescription)")
    }
  }
}

#Preview {
  ContentView()
}
