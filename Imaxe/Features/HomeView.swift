//
//  HomeView.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/17.
//

import AppKit
import SwiftData
import SwiftUI

private enum HomeTab: Hashable {
  case home
  case recent
}

private struct HomeOperationAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}

struct HomeView: View {
  @Bindable var imageSession: ImageSession
  let recentImages: [RecentImageItem]

  @Environment(\.modelContext) private var modelContext
  @State private var selectedTab = HomeTab.home
  @State private var deleteTarget: HomeRecentImageItem?
  @State private var renameTarget: HomeRecentImageItem?
  @State private var renameText = ""
  @State private var operationAlert: HomeOperationAlert?

  private var recentItems: [HomeRecentImageItem] {
    recentImages.map(HomeRecentImageItem.init)
  }

  private var recentImageActions: HomeRecentImageActions {
    HomeRecentImageActions(
      onOpen: open,
      onRemove: remove,
      onReveal: revealInFinder,
      onDeleteFile: confirmDelete,
      onRename: beginRename,
    )
  }

  var body: some View {
    Group {
      switch selectedTab {
      case .home:
        homeContent
      case .recent:
        recentImagesCollection
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .toolbar {
      ToolbarItem(placement: .principal) {
        Picker("Home View", selection: $selectedTab) {
          Label("Home", systemImage: "house")
            .tag(HomeTab.home)

          Label("Recent", systemImage: "clock")
            .tag(HomeTab.recent)
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
    .sheet(item: $renameTarget) { item in
      RenameFileSheet(
        item: item,
        fileName: $renameText,
      ) {
        renameTarget = nil
      } onRename: { newName in
        rename(item, to: newName)
        renameTarget = nil
      }
    }
    .confirmationDialog(
      "Move to Trash?",
      isPresented: isDeleteConfirmationPresented,
      titleVisibility: .visible,
    ) {
      Button("Move to Trash", role: .destructive) {
        if let deleteTarget {
          moveToTrash(deleteTarget)
        }
        deleteTarget = nil
      }

      Button("Cancel", role: .cancel) {
        deleteTarget = nil
      }
    } message: {
      Text(deleteTarget?.displayName ?? "")
    }
    .alert(item: $operationAlert) { alert in
      Alert(title: Text(alert.title), message: Text(alert.message))
    }
  }

  private var homeContent: some View {
    VStack {
      Spacer()

      Text("Welcome to Imaxe")
        .font(.largeTitle)
        .padding()

      Text("Import an image to get started.")
        .foregroundStyle(.secondary)
        .padding()

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var recentImagesCollection: some View {
    ImageCollectionView(
      items: recentItems,
      clearTitle: "Clear Recent Images",
      onClear: clearRecentImages,
      onOpen: open,
      searchableText: \.searchableText,
      name: \.displayName,
      lastOpenedAt: \.lastOpenedAt,
      modifiedAt: \.contentModificationDate,
      fileSize: \.fileSize,
    ) {
      emptyRecentImagesView
    } listRow: { context in
      HomeRecentImageListRow(context: context, actions: recentImageActions)
    } gridItem: { context in
      HomeRecentImageGridItem(context: context)
    } contextMenu: { item in
      HomeRecentImageActionsContent(item: item, actions: recentImageActions)
    } selectionActions: { selectedItems in
      Button {
        remove(selectedItems)
      } label: {
        Label("Remove Selected", systemImage: "minus.circle")
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

  private var isDeleteConfirmationPresented: Binding<Bool> {
    Binding {
      deleteTarget != nil
    } set: { isPresented in
      if !isPresented {
        deleteTarget = nil
      }
    }
  }

  private func open(_ item: HomeRecentImageItem) {
    guard let url = item.url else { return }

    imageSession.loadImage(from: url)
  }

  private func remove(_ item: HomeRecentImageItem) {
    do {
      try RecentImagesStore.remove(location: item.location, in: modelContext)
    } catch {
      operationAlert = HomeOperationAlert(
        title: "Failed to Remove Item",
        message: error.localizedDescription,
      )
    }
  }

  private func remove(_ items: [HomeRecentImageItem]) {
    for item in items {
      remove(item)
    }
  }

  private func revealInFinder(_ item: HomeRecentImageItem) {
    guard let url = item.url else { return }

    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  private func confirmDelete(_ item: HomeRecentImageItem) {
    deleteTarget = item
  }

  private func moveToTrash(_ item: HomeRecentImageItem) {
    guard let url = item.url else { return }

    do {
      var trashedURL: NSURL?
      try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
      try RecentImagesStore.remove(location: item.location, in: modelContext)
    } catch {
      operationAlert = HomeOperationAlert(
        title: "Failed to Move Item to Trash",
        message: error.localizedDescription,
      )
    }
  }

  private func beginRename(_ item: HomeRecentImageItem) {
    renameText = item.displayName
    renameTarget = item
  }

  private func rename(_ item: HomeRecentImageItem, to newName: String) {
    guard let url = item.url else { return }

    let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty, trimmedName != item.displayName else { return }

    let newURL = url.deletingLastPathComponent().appendingPathComponent(trimmedName)
    do {
      try FileManager.default.moveItem(at: url, to: newURL)
      try RecentImagesStore.updateLocation(from: item.location, to: newURL, in: modelContext)
    } catch {
      operationAlert = HomeOperationAlert(
        title: "Failed to Rename Item",
        message: error.localizedDescription,
      )
    }
  }

  private func clearRecentImages() {
    do {
      try RecentImagesStore.clear(in: modelContext)
    } catch {
      operationAlert = HomeOperationAlert(
        title: "Failed to Clear Recent Images",
        message: error.localizedDescription,
      )
    }
  }
}
