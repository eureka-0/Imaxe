//
//  HomeView.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/17.
//

import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private struct HomeOperationAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}

struct HomeView: View {
  @Bindable var imageSession: ImageSession
  let recentImages: [RecentImageItem]

  @Environment(\.modelContext) private var modelContext
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
    VStack(spacing: 48) {
      homeHero
      recentImagesCollection
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

  private var homeHero: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Drop images anywhere")
        .font(.title.weight(.semibold))
        .lineLimit(1)

      HStack(spacing: 5) {
        ForEach(ImageLoader.supportedImageTypes, id: \.self) { utType in
          Text(utType.preferredFilenameExtension?.uppercased() ?? utType.identifier)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }

        Spacer()
      }

      HStack(spacing: 12) {
        SettingsLink {
          Label("Settings", systemImage: "gearshape")
        }
        .help("Open Settings")

        Button {
          imageSession.isImporterPresented = true
        } label: {
          Label("Open Image", systemImage: "photo.badge.plus")
        }
        .help("Open Image")
      }
      .buttonStyle(.borderedProminent)
    }
    .padding(.horizontal, 32)
    .padding(.top, 80)
    .frame(maxWidth: .infinity)
  }

  private var recentImagesCollection: some View {
    ImageCollectionView(recentItems, onOpen: open) {
      emptyRecentImagesView
    } listRow: { context in
      HomeRecentImageListRow(context: context, actions: recentImageActions)
    } gridItem: { context in
      HomeRecentImageGridItem(context: context)
    }
    .collectionTitle("Recent Images")
    .searchableText(\.searchableText)
    .sortOptions(recentSortOptions, default: "lastOpenedAt", direction: .descending)
    .defaultViewMode(.grid)
    .tieBreaker { first, second in
      first.displayName.localizedStandardCompare(second.displayName)
    }
    .clearAction("Clear Recent Images", clearRecentImages)
    .contextMenu { item in
      HomeRecentImageActionsContent(item: item, actions: recentImageActions)
    }
    .selectionActions { selectedItems in
      Button {
        remove(selectedItems)
      } label: {
        Label("Remove Selected", systemImage: "minus.circle")
      }
    }
    .background(.controlBackground.opacity(0.5))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color(.separatorColor), lineWidth: 0.5),
    )
    .padding([.horizontal, .bottom], 8)
  }

  private var emptyRecentImagesView: some View {
    VStack(spacing: 15) {
      Image(systemName: "photo.on.rectangle.angled")
        .resizable()
        .scaledToFit()
        .foregroundStyle(.secondary)
        .frame(width: 64, height: 64)

      Text("No recent images yet")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var recentSortOptions: [ImageCollectionSortOption<HomeRecentImageItem>] {
    [
      ImageCollectionSortOption("name", title: "Name", systemImage: "textformat") { first, second in
        first.displayName.localizedStandardCompare(second.displayName)
      },
      ImageCollectionSortOption(
        "lastOpenedAt",
        title: "Last Opened",
        systemImage: "clock",
        value: \.lastOpenedAt,
      ),
      ImageCollectionSortOption(
        "modifiedAt",
        title: "Modified",
        systemImage: "calendar",
        optionalValue: \.contentModificationDate,
      ),
      ImageCollectionSortOption(
        "fileSize",
        title: "Size",
        systemImage: "externaldrive",
        value: \.fileSize,
      ),
    ]
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
