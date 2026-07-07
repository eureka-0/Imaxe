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
  let recentImages: [RecentImage]

  @Environment(\.modelContext) private var modelContext
  @State private var deleteTargetURL: URL?
  @State private var renameTarget: RecentImage?
  @State private var renameText = ""
  @State private var operationAlert: HomeOperationAlert?

  private var isDeleteConfirmationPresented: Binding<Bool> {
    Binding {
      deleteTargetURL != nil
    } set: { isPresented in
      if !isPresented {
        deleteTargetURL = nil
      }
    }
  }

  var body: some View {
    VStack(spacing: 48) {
      homeHero
      recentImagesCollection
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .sheet(item: $renameTarget) { item in
      fileRenameSheet(for: item)
    }
    .confirmationDialog(
      "Move to Trash?",
      isPresented: isDeleteConfirmationPresented,
      titleVisibility: .visible,
    ) {
      Button("Move to Trash", role: .destructive) {
        if let deleteTargetURL {
          moveToTrash(deleteTargetURL)
        }
        deleteTargetURL = nil
      }

      Button("Cancel", role: .cancel) {
        deleteTargetURL = nil
      }
    } message: {
      Text(deleteTargetURL?.path ?? "")
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

  private var imageCollectionConfiguration: ImageCollectionConfiguration<RecentImage> {
    var configuration = ImageCollectionConfiguration<RecentImage>()
    configuration.title = "Recent Images"
    configuration.useDefaultSubtitle = true
    configuration.emptyDescription = "No recent images yet"
    configuration.searchableText = { "\($0.fileName)\n\($0.location)" }
    configuration.defaultViewMode = .grid
    configuration.sortOptions = [
      ImageCollectionSortOption("name", title: "Name", systemImage: "textformat") { first, second in
        first.fileName.localizedStandardCompare(second.fileName)
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
        optionalValue: \.url.lastModifiedAt,
      ),
      ImageCollectionSortOption(
        "fileSize",
        title: "Size",
        systemImage: "externaldrive",
        value: \.url.fileSize,
      ),
    ]
    configuration.defaultSortOptionID = "lastOpenedAt"
    configuration.clearHelpText = "Clear Recent Images"
    configuration.onClear = clearRecentImages
    return configuration
  }

  private var recentImagesCollection: some View {
    ImageCollectionView(
      recentImages,
      configuration: imageCollectionConfiguration,
      listRow: recentImageListRow,
      gridItem: recentImageGridItem,
      contextMenu: recentImageActionsMenu,
    )
    .background(.controlBackground.opacity(0.5))
    .clipShape(ContainerRelativeShape())
    .overlay(
      ContainerRelativeShape()
        .strokeBorder(Color.separator, lineWidth: 0.5),
    )
    .padding([.horizontal, .bottom], 4)
  }

  private func recentImageListRow(
    _ item: RecentImage,
    state: ImageCollectionItemState,
  ) -> some View {
    HStack(spacing: 6) {
      ImageThumbnailView(url: item.url)
        .frame(width: 28, height: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text(item.fileName)
          .font(.callout)
          .lineLimit(1)
          .truncationMode(.middle)

        Text(item.path)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)

      Text(item.lastOpenedAt.relativeDateDescription)
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(idealWidth: 116, alignment: .leading)

      Text(item.fileSizeDescription)
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 68, alignment: .trailing)

      Menu {
        recentImageActionsMenu(item)
      } label: {
        Label("More", systemImage: "ellipsis")
          .labelStyle(.iconOnly)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.secondary)
          .frame(width: 24, height: 24)
      }
      .menuStyle(.button)
      .buttonStyle(.borderedOnHover)
      .help("More")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 2)
    .background(state.isHovered ? Color.primary.opacity(0.07) : .clear)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .onTapGesture(count: 2) {
      imageSession.loadImage(from: item.url)
    }
  }

  private func recentImageGridItem(
    _ item: RecentImage,
    state: ImageCollectionItemState,
  ) -> some View {
    ImageThumbnailView(url: item.url)
      .overlay(alignment: .bottom) {
        if state.isHovered {
          Text(item.fileName)
            .font(.system(size: 10, weight: .light))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .padding(.bottom, 2)
        }
      }
      .onTapGesture(count: 1) {
        imageSession.loadImage(from: item.url)
      }
      .help(item.path)
  }

  @ViewBuilder
  private func recentImageActionsMenu(_ item: RecentImage) -> some View {
    Button("Open", systemImage: "photo") {
      imageSession.loadImage(from: item.url)
    }

    Button("Rename", systemImage: "pencil") {
      beginRename(item)
    }

    Button("Move to Trash", systemImage: "trash", role: .destructive) {
      confirmDelete(item.url)
    }

    Divider()

    Button("Remove from Recents", systemImage: "minus.circle") {
      remove(path: item.path)
    }

    Button("Reveal in Finder", systemImage: "folder") {
      imageSession.revealInFinder(for: [item.url])
    }
  }

  private func fileRenameSheet(for item: RecentImage) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Rename")
        .font(.headline)

      TextField("Name", text: $renameText)
        .textFieldStyle(.roundedBorder)
        .frame(width: 320)

      HStack {
        Spacer()

        Button("Cancel") {
          renameTarget = nil
        }
        .keyboardShortcut(.cancelAction)

        Button("Rename") {
          rename(item.url, to: renameText)
          renameTarget = nil
        }
        .keyboardShortcut(.defaultAction)
        .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 380)
  }

  private func remove(path: String) {
    do {
      try RecentImagesStore.remove(path: path, in: modelContext)
    } catch {
      operationAlert = HomeOperationAlert(
        title: "Failed to Remove Item",
        message: error.localizedDescription,
      )
    }
  }

  private func confirmDelete(_ url: URL) {
    deleteTargetURL = url
  }

  private func moveToTrash(_ url: URL) {
    do {
      var trashedURL: NSURL?
      try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
      try RecentImagesStore.remove(path: url.filePath, in: modelContext)
    } catch {
      operationAlert = HomeOperationAlert(
        title: "Failed to Move Item to Trash",
        message: error.localizedDescription,
      )
    }
  }

  private func beginRename(_ item: RecentImage) {
    renameText = item.url.lastPathComponent
    renameTarget = item
  }

  private func rename(_ url: URL, to newName: String) {
    let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty, trimmedName != url.lastPathComponent else { return }

    let newURL = url.deletingLastPathComponent().appendingPathComponent(trimmedName)
    do {
      try FileManager.default.moveItem(at: url, to: newURL)
      try RecentImagesStore.updateLocation(from: url.filePath, to: newURL, in: modelContext)
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
