//
//  ContentView.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/14.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @State private var imageSession = ImageSession()

  var body: some View {
    Group {
      if imageSession.currentImage != nil || imageSession.isLoading {
        ImageView(imageSession: imageSession)
      } else {
        HomeView()
      }
    }
    .focusedSceneValue(imageSession)
    .fileImporter(
      isPresented: $imageSession.isImporterPresented,
      allowedContentTypes: [.image],
      onCompletion: imageSession.onOpenImage,
    )
    .alert(item: $imageSession.alert) { alert in
      Alert(title: Text(alert.title), message: Text(alert.message))
    }
  }
}

#Preview {
  ContentView()
}
