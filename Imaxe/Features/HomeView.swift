//
//  HomeView.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/17.
//

import SwiftData
import SwiftUI

private enum HomeTab: Hashable {
  case recent
  case favorites
}

struct HomeView: View {
  @Bindable var imageSession: ImageSession
  let recentImages: [RecentImageItem]

  @Environment(\.modelContext) private var modelContext
  @State private var selectedTab = HomeTab.recent

  var body: some View {
    Group {
      switch selectedTab {
      case .recent:
        if recentImages.isEmpty {
          emptyRecentImagesView
        } else {
          recentImagesCollection
        }
      case .favorites:
        favoriteView
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .toolbar {
      ToolbarItem(placement: .principal) {
        Picker("Home View", selection: $selectedTab) {
          Label("Recent", systemImage: "clock")
            .tag(HomeTab.recent)

          Label("Favorites", systemImage: "star")
            .tag(HomeTab.favorites)
        }
        .pickerStyle(.segmented)
        .labelStyle(.titleOnly)
        .labelsHidden()
      }

      ToolbarItemGroup(placement: .confirmationAction) {
        Button {
          imageSession.isImporterPresented = true
        } label: {
          Label("Open Image", systemImage: "photo.badge.plus")
        }
        .help("Open Image")

        SettingsLink {
          Label("Settings", systemImage: "gearshape")
        }
        .help("Open Settings")
      }
    }
  }

  private var emptyRecentImagesView: some View {
    VStack(spacing: 12) {
      Spacer()

      Image(systemName: "photo.on.rectangle.angled")
        .resizable()
        .scaledToFit()
        .frame(width: 100, height: 100)
        .foregroundStyle(.secondary)

      Text("No recent images")
        .font(.title)

      Text("Drop an image here or press command + o to open an image")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var recentImagesCollection: some View {
    VStack(spacing: 0) {
      HStack {
        Spacer()

        Button {
          try? RecentImagesStore.clear(in: modelContext)
        } label: {
          Label("Clear", systemImage: "trash")
        }
        .help("Clear Recent Images")
      }
      .labelStyle(.iconOnly)
      .padding(.horizontal, 8)
      .padding(.bottom, 8)
      .background(Color.windowBackground)

      ScrollView(.vertical) {
        LazyVStack(spacing: 0) {
          ForEach(recentImages) { recentImage in
            Button {
              if let url = recentImage.url {
                imageSession.loadImage(from: url)
              }
            } label: {
              Text(recentImage.displayName)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .help(recentImage.location)
          }
        }
      }
    }
  }

  private var favoriteView: some View {
    VStack {
      Spacer()

      Text("No favorite images")
        .font(.title)
        .foregroundStyle(.secondary)

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
