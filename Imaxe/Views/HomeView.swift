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

  @AppStorage("recentImagesViewMode")
  private var recentImagesViewModeRawValue = ImageCollectionViewMode.grid.rawValue
  @AppStorage("recentImagesGridItemSize") private var recentImagesGridItemSize = 120.0

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

  private var recentImagesViewMode: Binding<ImageCollectionViewMode> {
    Binding {
      ImageCollectionViewMode(rawValue: recentImagesViewModeRawValue) ?? .grid
    } set: { newValue in
      recentImagesViewModeRawValue = newValue.rawValue
    }
  }

  private var recentImagesGridItemSizeBinding: Binding<CGFloat> {
    Binding {
      CGFloat(recentImagesGridItemSize)
        .clamped(to: Constants.recentImagesGridItemSizeRange)
    } set: { newValue in
      recentImagesGridItemSize = Double(
        newValue.clamped(to: Constants.recentImagesGridItemSizeRange),
      )
    }
  }

  var body: some View {
    VStack(spacing: 0) {
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
      Text(deleteTargetURL?.filePath ?? "")
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
            .padding(.vertical, 3)
        }
        .help("Open Settings")

        Button {
          imageSession.isImporterPresented = true
        } label: {
          Label("Open Image", systemImage: "photo.badge.plus")
            .padding(.vertical, 3)
        }
        .help("Open Image")
      }
      .buttonStyle(.borderedProminent)
      .buttonBorderShape(.roundedRectangle)
    }
    .padding([.horizontal, .top], 32)
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity)
    .containerRelativeFrame(.vertical, alignment: .center) { length, _ in
      length * 0.5
    }
  }

  private var imageCollectionConfiguration: ImageCollectionConfiguration<RecentImage> {
    var configuration = ImageCollectionConfiguration<RecentImage>()
    configuration.title = "Recent Images"
    configuration.useDefaultSubtitle = true
    configuration.emptyDescription = "No recent images yet"
    configuration.searchableText = { "\($0.fileName)\n\($0.location)" }
    configuration.defaultViewMode = .grid
    configuration.sortOptions = [
      ImageCollectionSortOption("name", title: "Name") { first, second in
        first.fileName.localizedStandardCompare(second.fileName)
      },
      ImageCollectionSortOption(
        "lastOpenedAt",
        title: "Last Opened",
        value: \.lastOpenedAt,
      ),
      ImageCollectionSortOption(
        "modifiedAt",
        title: "Modified",
        optionalValue: \.sourceContentModificationDate,
      ),
      ImageCollectionSortOption(
        "fileSize",
        title: "Size",
        optionalValue: \.sourceFileSize,
      ),
    ]
    configuration.defaultSortOptionID = "lastOpenedAt"
    configuration.clearHelpText = "Clear Recent Images"
    configuration.onClear = clearRecentImages
    return configuration
  }

  private var recentImagesCollection: some View {
    ImageCollectionView(
      imageSession.recentImages,
      configuration: imageCollectionConfiguration,
      listRow: recentImageListRow,
      gridItem: recentImageGridItem,
      contextMenu: recentImageActionsMenu,
    )
    .viewMode(recentImagesViewMode)
    .gridItemLayout(size: recentImagesGridItemSizeBinding)
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
      ImageThumbnailView(url: item.url, cacheKey: item.thumbnailCacheKey)
        .frame(width: 28, height: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text(item.fileName.searchHighlightedAttributedString(matching: state.searchText))
          .font(.callout)
          .lineLimit(1)
          .truncationMode(.middle)

        Text(item.path.searchHighlightedAttributedString(matching: state.searchText))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)

      Text(item.lastOpenedAt.relativeDateDescription)
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(width: 90, alignment: .leading)

      Text(item.sourceFileSize.map(fileSizeDescription(for:)) ?? "-")
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 56, alignment: .trailing)

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
    .background(state.isHovered ? Color.primary.opacity(0.1) : .clear)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .onTapGesture(count: 2) {
      openRecentImage(item)
    }
  }

  private func recentImageGridItem(
    _ item: RecentImage,
    state: ImageCollectionItemState,
  ) -> some View {
    ImageThumbnailView(url: item.url, cacheKey: item.thumbnailCacheKey)
      .overlay(alignment: .bottom) {
        if state.isHovered || !state.searchText.isEmpty {
          Text(item.fileName.searchHighlightedAttributedString(matching: state.searchText))
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
        openRecentImage(item)
      }
      .help(item.path)
  }

  @ViewBuilder
  private func recentImageActionsMenu(_ item: RecentImage) -> some View {
    Button("Open", systemImage: "photo") {
      openRecentImage(item)
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

  private func openRecentImage(_ item: RecentImage) {
    imageSession.openRecentImage(item)
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
    } catch {
      operationAlert = HomeOperationAlert(
        title: "Failed to Rename Item",
        message: error.localizedDescription,
      )
      return
    }

    Task {
      do {
        try await RecentImagesStore.updateLocation(
          from: url.filePath,
          to: newURL,
          in: modelContext,
        )
      } catch {
        operationAlert = HomeOperationAlert(
          title: "Failed to Update Recent Images",
          message: error.localizedDescription,
        )
      }
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

private extension ShapeStyle where Self == Color {
  static var searchHighlightBackground: Color {
    Color(
      light: .yellow.opacity(0.9),
      dark: .yellow.mix(with: .black, by: 0.4).opacity(0.9),
    )
  }
}

private extension String {
  func searchHighlightedAttributedString(matching searchText: String) -> AttributedString {
    var attributedString = AttributedString(self)
    let searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !isEmpty, !searchText.isEmpty else { return attributedString }

    var remainingRange = startIndex ..< endIndex
    while let matchRange = fuzzyMatch(searchText, range: remainingRange) {
      if let lowerBound = AttributedString.Index(matchRange.lowerBound, within: attributedString),
         let upperBound = AttributedString.Index(matchRange.upperBound, within: attributedString)
      {
        attributedString[lowerBound ..< upperBound].backgroundColor = .searchHighlightBackground
      }

      guard matchRange.upperBound < endIndex else { break }
      remainingRange = matchRange.upperBound ..< endIndex
    }

    return attributedString
  }
}
