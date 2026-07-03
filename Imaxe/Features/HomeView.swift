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
  case recent
  case favorites
}

private struct HomeOperationAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}

struct HomeView: View {
  @Bindable var imageSession: ImageSession
  let recentImages: [RecentImageItem]
  let favoriteItems: [FavoriteItemSnapshot]

  @Environment(\.modelContext) private var modelContext
  @State private var selectedTab = HomeTab.recent
  @State private var searchText = ""
  @State private var sort = HomeCollectionSort.lastOpenedAt
  @State private var sortDirection = HomeSortDirection.descending
  @State private var viewMode = HomeCollectionViewMode.list
  @State private var isSelecting = false
  @State private var selectedItemIDs = Set<String>()
  @State private var favoriteFolder: HomeCollectionItem?
  @State private var favoriteFolderItems: [HomeCollectionItem] = []
  @State private var isFavoriteImageImporterPresented = false
  @State private var deleteTarget: HomeCollectionItem?
  @State private var renameTarget: HomeCollectionItem?
  @State private var renameText = ""
  @State private var operationAlert: HomeOperationAlert?

  private var recentCollectionItems: [HomeCollectionItem] {
    recentImages.map(HomeCollectionItem.init)
  }

  private var favoriteCollectionItems: [HomeCollectionItem] {
    favoriteItems.map(HomeCollectionItem.init)
  }

  var body: some View {
    Group {
      switch selectedTab {
      case .recent:
        recentImagesCollection
      case .favorites:
        favoriteCollection
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
    .fileImporter(
      isPresented: $isFavoriteImageImporterPresented,
      allowedContentTypes: ImageLoader.supportedImageTypes,
      allowsMultipleSelection: true,
    ) { result in
      addFavoriteImages(from: result)
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
    .onChange(of: selectedTab) { _, _ in
      selectedItemIDs.removeAll()
      isSelecting = false
      favoriteFolder = nil
      favoriteFolderItems = []
      searchText = ""
      sort = .lastOpenedAt
      sortDirection = .descending
    }
  }

  private var recentImagesCollection: some View {
    HomeCollectionView(
      title: nil,
      subtitle: nil,
      items: recentCollectionItems,
      emptyTitle: "No recent images",
      emptyMessage: "Drop an image here or press command + o to open an image",
      keepsFoldersFirst: false,
      clearTitle: "Clear Recent Images",
      onBack: nil,
      onClear: clearRecentImages,
      onAddFavoriteImages: nil,
      onAddFavoriteFolder: nil,
      onOpen: open,
      onRemove: remove,
      onRemoveItems: remove,
      onAddFavorite: addFavorite,
      onAddFavorites: addFavorites,
      onReveal: revealInFinder,
      onDeleteFile: confirmDelete,
      onRename: beginRename,
      searchText: $searchText,
      sort: $sort,
      sortDirection: $sortDirection,
      viewMode: $viewMode,
      isSelecting: $isSelecting,
      selectedItemIDs: $selectedItemIDs,
    )
  }

  @ViewBuilder
  private var favoriteCollection: some View {
    if let favoriteFolder {
      HomeCollectionView(
        title: favoriteFolder.displayName,
        subtitle: favoriteFolder.location,
        items: favoriteFolderItems,
        emptyTitle: "No images in this folder",
        emptyMessage: "This folder does not contain supported images",
        keepsFoldersFirst: true,
        clearTitle: nil,
        onBack: leaveFavoriteFolder,
        onClear: nil,
        onAddFavoriteImages: nil,
        onAddFavoriteFolder: nil,
        onOpen: open,
        onRemove: remove,
        onRemoveItems: remove,
        onAddFavorite: addFavorite,
        onAddFavorites: addFavorites,
        onReveal: revealInFinder,
        onDeleteFile: confirmDelete,
        onRename: beginRename,
        searchText: $searchText,
        sort: $sort,
        sortDirection: $sortDirection,
        viewMode: $viewMode,
        isSelecting: $isSelecting,
        selectedItemIDs: $selectedItemIDs,
      )
    } else {
      HomeCollectionView(
        title: nil,
        subtitle: nil,
        items: favoriteCollectionItems,
        emptyTitle: "No favorite images",
        emptyMessage: "Add images or folders to keep them close",
        keepsFoldersFirst: true,
        clearTitle: "Clear Favorites",
        onBack: nil,
        onClear: clearFavorites,
        onAddFavoriteImages: { isFavoriteImageImporterPresented = true },
        onAddFavoriteFolder: addFavoriteFolder,
        onOpen: open,
        onRemove: remove,
        onRemoveItems: remove,
        onAddFavorite: addFavorite,
        onAddFavorites: addFavorites,
        onReveal: revealInFinder,
        onDeleteFile: confirmDelete,
        onRename: beginRename,
        searchText: $searchText,
        sort: $sort,
        sortDirection: $sortDirection,
        viewMode: $viewMode,
        isSelecting: $isSelecting,
        selectedItemIDs: $selectedItemIDs,
      )
    }
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

  private func open(_ item: HomeCollectionItem) {
    if item.kind == .folder {
      showFavoriteFolder(item)
      return
    }

    guard let url = item.url else { return }
    imageSession.loadImage(from: url)
  }

  private func remove(_ item: HomeCollectionItem) {
    do {
      switch item.source {
      case .recent:
        try RecentImagesStore.remove(location: item.location, in: modelContext)
      case .favorite:
        try FavoriteItemsStore.remove(location: item.location, in: modelContext)
      case .favoriteFolderImage:
        break
      }
      selectedItemIDs.remove(item.id)
    } catch {
      operationAlert = HomeOperationAlert(
        title: "Failed to Remove Item",
        message: error.localizedDescription,
      )
    }
  }

  private func remove(_ items: [HomeCollectionItem]) {
    for item in items {
      remove(item)
    }
    selectedItemIDs.removeAll()
  }

  private func addFavorite(_ item: HomeCollectionItem) {
    guard let url = item.url else { return }

    do {
      try FavoriteItemsStore.add(url, kind: item.kind, in: modelContext)
    } catch {
      operationAlert = HomeOperationAlert(
        title: "Failed to Add Favorite",
        message: error.localizedDescription,
      )
    }
  }

  private func addFavorites(_ items: [HomeCollectionItem]) {
    for item in items where item.source != .favorite {
      addFavorite(item)
    }
  }

  private func revealInFinder(_ item: HomeCollectionItem) {
    guard let url = item.url else { return }

    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  private func confirmDelete(_ item: HomeCollectionItem) {
    deleteTarget = item
  }

  private func moveToTrash(_ item: HomeCollectionItem) {
    guard let url = item.url else { return }

    do {
      var trashedURL: NSURL?
      try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
      try removePersistentReferences(to: item.location)
      reloadFavoriteFolderIfNeeded()
    } catch {
      operationAlert = HomeOperationAlert(
        title: "Failed to Move Item to Trash",
        message: error.localizedDescription,
      )
    }
  }

  private func beginRename(_ item: HomeCollectionItem) {
    renameText = item.displayName
    renameTarget = item
  }

  private func rename(_ item: HomeCollectionItem, to newName: String) {
    guard let url = item.url else { return }

    let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty, trimmedName != item.displayName else { return }

    let newURL = url.deletingLastPathComponent().appendingPathComponent(trimmedName)
    do {
      try FileManager.default.moveItem(at: url, to: newURL)
      try RecentImagesStore.updateLocation(from: item.location, to: newURL, in: modelContext)
      try FavoriteItemsStore.updateLocation(from: item.location, to: newURL, in: modelContext)
      if favoriteFolder?.id == item.id {
        favoriteFolder = try HomeCollectionItem(
          favoriteItem: FavoriteItemSnapshot(
            favoriteItem: fetchFavoriteItem(location: LibraryFileSnapshot.location(for: newURL)),
          ),
        )
      }
      reloadFavoriteFolderIfNeeded()
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
      selectedItemIDs.removeAll()
    } catch {
      operationAlert = HomeOperationAlert(
        title: "Failed to Clear Recent Images",
        message: error.localizedDescription,
      )
    }
  }

  private func clearFavorites() {
    do {
      try FavoriteItemsStore.clear(in: modelContext)
      selectedItemIDs.removeAll()
    } catch {
      operationAlert = HomeOperationAlert(
        title: "Failed to Clear Favorites",
        message: error.localizedDescription,
      )
    }
  }

  private func addFavoriteImages(from result: Result<[URL], Error>) {
    do {
      let urls = try result.get()
      for url in urls {
        try FavoriteItemsStore.add(url, kind: .image, in: modelContext)
      }
    } catch {
      operationAlert = HomeOperationAlert(
        title: "Failed to Add Favorite Images",
        message: error.localizedDescription,
      )
    }
  }

  private func addFavoriteFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Add"

    guard panel.runModal() == .OK,
          let url = panel.url
    else { return }

    do {
      try FavoriteItemsStore.add(url, kind: .folder, in: modelContext)
    } catch {
      operationAlert = HomeOperationAlert(
        title: "Failed to Add Favorite Folder",
        message: error.localizedDescription,
      )
    }
  }

  private func showFavoriteFolder(_ item: HomeCollectionItem) {
    guard let url = item.url else { return }

    favoriteFolder = item
    favoriteFolderItems = favoriteFolderImageItems(in: url)
    selectedItemIDs.removeAll()
    isSelecting = false
  }

  private func leaveFavoriteFolder() {
    favoriteFolder = nil
    favoriteFolderItems = []
    selectedItemIDs.removeAll()
    isSelecting = false
  }

  private func reloadFavoriteFolderIfNeeded() {
    guard let url = favoriteFolder?.url else { return }

    favoriteFolderItems = favoriteFolderImageItems(in: url)
  }

  private func favoriteFolderImageItems(in folderURL: URL) -> [HomeCollectionItem] {
    guard let contents = try? FileManager.default.contentsOfDirectory(
      at: folderURL,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles],
    ) else { return [] }

    return contents
      .filter { FolderNavigator.isRegularFile($0) && ImageLoader.isSupportedImage($0) }
      .sorted { first, second in
        first.lastPathComponent
          .localizedStandardCompare(second.lastPathComponent) == .orderedAscending
      }
      .map(HomeCollectionItem.init(favoriteFolderImageURL:))
  }

  private func removePersistentReferences(to location: String) throws {
    try RecentImagesStore.remove(location: location, in: modelContext)
    try FavoriteItemsStore.remove(location: location, in: modelContext)
    selectedItemIDs.removeAll()
  }

  private func fetchFavoriteItem(location: String) throws -> FavoriteItem {
    var descriptor = FetchDescriptor<FavoriteItem>(
      predicate: #Predicate<FavoriteItem> { item in
        item.location == location
      },
    )
    descriptor.fetchLimit = 1
    if let favoriteItem = try modelContext.fetch(descriptor).first {
      return favoriteItem
    }

    throw CocoaError(.fileNoSuchFile)
  }
}
