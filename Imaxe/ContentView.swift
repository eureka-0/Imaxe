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
  @State private var isTargetedForDrop = false

  var body: some View {
    Group {
      if imageSession.currentImage != nil || imageSession.isLoading {
        ImageView(imageSession: imageSession)
      } else {
        HomeView()
      }
    }
    .overlay(
      ContainerRelativeShape()
        .strokeBorder(
          isTargetedForDrop ? Color.accentColor : .clear,
          lineWidth: 3,
        ),
    )
    .focusedSceneValue(imageSession)
    .fileImporter(
      isPresented: $imageSession.isImporterPresented,
      allowedContentTypes: [.image],
      onCompletion: imageSession.onOpenImage,
    )
    .alert(item: $imageSession.alert) { alert in
      Alert(title: Text(alert.title), message: Text(alert.message))
    }
    .dropDestination(for: URL.self) { urls, _ in
      guard let url = urls.first else { return false }

      imageSession.loadImage(from: url)
      return true
    } isTargeted: { isTargeted in
      isTargetedForDrop = isTargeted
    }
    .onOpenURL { url in
      imageSession.loadImage(from: url)
    }
  }
}

#Preview {
  ContentView()
}
