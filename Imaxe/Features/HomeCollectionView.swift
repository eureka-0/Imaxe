//
//  HomeCollectionView.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/3.
//

import AppKit
import SwiftUI

struct HomeCollectionView: View {
  let title: String?
  let subtitle: String?
  let items: [HomeCollectionItem]
  let emptyTitle: String
  let emptyMessage: String
  let keepsFoldersFirst: Bool
  let clearTitle: String?
  let onBack: (() -> Void)?
  let onClear: (() -> Void)?
  let onAddFavoriteImages: (() -> Void)?
  let onAddFavoriteFolder: (() -> Void)?
  let onOpen: (HomeCollectionItem) -> Void
  let onRemove: (HomeCollectionItem) -> Void
  let onRemoveItems: ([HomeCollectionItem]) -> Void
  let onAddFavorite: (HomeCollectionItem) -> Void
  let onAddFavorites: ([HomeCollectionItem]) -> Void
  let onReveal: (HomeCollectionItem) -> Void
  let onDeleteFile: (HomeCollectionItem) -> Void
  let onRename: (HomeCollectionItem) -> Void

  @Binding var searchText: String
  @Binding var sort: HomeCollectionSort
  @Binding var sortDirection: HomeSortDirection
  @Binding var viewMode: HomeCollectionViewMode
  @Binding var isSelecting: Bool
  @Binding var selectedItemIDs: Set<String>

  private var visibleItems: [HomeCollectionItem] {
    let filteredItems = if searchText.isEmpty {
      items
    } else {
      items.filter {
        $0.displayName.localizedStandardContains(searchText)
          || $0.location.localizedStandardContains(searchText)
      }
    }

    return filteredItems.sorted { first, second in
      if keepsFoldersFirst, first.kind != second.kind {
        return first.kind == .folder
      }

      let result = comparisonResult(first, second)
      if result == .orderedSame {
        return first.displayName.localizedStandardCompare(second.displayName) == .orderedAscending
      }

      return sortDirection == .ascending ? result == .orderedAscending : result ==
        .orderedDescending
    }
  }

  private var selectedItems: [HomeCollectionItem] {
    visibleItems.filter { selectedItemIDs.contains($0.id) }
  }

  private var itemIDs: [String] {
    items.map(\.id)
  }

  var body: some View {
    VStack(spacing: 0) {
      collectionToolbar
        .zIndex(10)

      if visibleItems.isEmpty {
        emptyContent
      } else {
        ScrollView(.vertical) {
          switch viewMode {
          case .list:
            listContent
          case .grid:
            gridContent
          }
        }
        .scrollClipDisabled()
      }
    }
    .background(Color.windowBackground)
    .onChange(of: itemIDs) { _, newValue in
      selectedItemIDs.formIntersection(Set(newValue))
    }
  }

  private var collectionToolbar: some View {
    HStack(spacing: 8) {
      if let onBack {
        Button {
          onBack()
        } label: {
          Label("Back", systemImage: "chevron.left")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .help("Back")
      }

      VStack(alignment: .leading, spacing: 1) {
        if let title {
          Text(title)
            .font(.headline)
            .lineLimit(1)
        }

        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      .frame(minWidth: 70, maxWidth: 180, alignment: .leading)

      Spacer(minLength: 6)

      searchField

      Menu {
        ForEach(HomeCollectionSort.allCases) { sortOption in
          Button {
            sort = sortOption
          } label: {
            Label(sortOption.title, systemImage: sortOption.systemImage)
          }
        }
      } label: {
        Label(sort.title, systemImage: sort.systemImage)
      }
      .menuStyle(.button)
      .labelStyle(.iconOnly)
      .help("Sort by \(sort.title)")

      Button {
        sortDirection.toggle()
      } label: {
        Label(sortDirection.title, systemImage: sortDirection.systemImage)
      }
      .labelStyle(.iconOnly)
      .help(sortDirection.title)

      Picker("View", selection: $viewMode) {
        ForEach(HomeCollectionViewMode.allCases) { mode in
          Label(mode.title, systemImage: mode.systemImage)
            .tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(width: 88)
      .help("View Mode")

      Button {
        if isSelecting {
          selectedItemIDs.removeAll()
        }
        isSelecting.toggle()
      } label: {
        Label("Select", systemImage: isSelecting ? "checkmark.circle.fill" : "checkmark.circle")
      }
      .labelStyle(.iconOnly)
      .help("Select Items")

      if isSelecting, !selectedItems.isEmpty {
        Menu {
          Button {
            onRemoveItems(selectedItems)
          } label: {
            Label("Remove Selected", systemImage: "minus.circle")
          }

          Button {
            onAddFavorites(selectedItems)
          } label: {
            Label("Add Selected to Favorites", systemImage: "star")
          }
          .disabled(selectedItems.allSatisfy { $0.source == .favorite })
        } label: {
          Label("Batch Actions", systemImage: "ellipsis.circle")
        }
        .menuStyle(.button)
        .labelStyle(.iconOnly)
        .help("Batch Actions")
      }

      if onAddFavoriteImages != nil || onAddFavoriteFolder != nil {
        Menu {
          if let onAddFavoriteImages {
            Button {
              onAddFavoriteImages()
            } label: {
              Label("Add Images", systemImage: "photo.badge.plus")
            }
          }

          if let onAddFavoriteFolder {
            Button {
              onAddFavoriteFolder()
            } label: {
              Label("Add Folder", systemImage: "folder.badge.plus")
            }
          }
        } label: {
          Label("Add Favorite", systemImage: "plus")
        }
        .menuStyle(.button)
        .labelStyle(.iconOnly)
        .help("Add Favorite")
      }

      if let clearTitle, let onClear {
        Button(role: .destructive) {
          onClear()
        } label: {
          Label(clearTitle, systemImage: "trash")
        }
        .labelStyle(.iconOnly)
        .disabled(items.isEmpty)
        .help(clearTitle)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(.regularMaterial)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color.separator)
        .frame(height: 1)
    }
  }

  private var searchField: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)

      TextField("Search", text: $searchText)
        .textFieldStyle(.plain)

      if !searchText.isEmpty {
        Button {
          searchText = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Clear Search")
      }
    }
    .font(.callout)
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .frame(minWidth: 96, idealWidth: 140, maxWidth: 180)
    .background(Color.controlBackground.opacity(0.85))
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }

  private var emptyContent: some View {
    VStack(spacing: 10) {
      Spacer()

      Image(systemName: "photo.on.rectangle.angled")
        .font(.system(size: 54))
        .foregroundStyle(.secondary)

      Text(emptyTitle)
        .font(.title3)

      Text(emptyMessage)
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var listContent: some View {
    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
      Section {
        ForEach(visibleItems) { item in
          HomeCollectionListRow(
            item: item,
            isSelected: selectedItemIDs.contains(item.id),
            isSelecting: isSelecting,
            actions: actions,
          ) {
            select(item)
          } onOpen: {
            onOpen(item)
          }
        }
        .padding(.horizontal, 10)
      } header: {
        HomeCollectionListHeader()
      }
    }
    .padding(.bottom, 8)
  }

  private var gridContent: some View {
    LazyVGrid(
      columns: [
        GridItem(.adaptive(minimum: 118, maximum: 160), spacing: 14, alignment: .top),
      ],
      spacing: 16,
    ) {
      ForEach(visibleItems) { item in
        HomeCollectionGridItem(
          item: item,
          isSelected: selectedItemIDs.contains(item.id),
          isSelecting: isSelecting,
          actions: actions,
        ) {
          select(item)
        } onOpen: {
          onOpen(item)
        }
      }
    }
    .padding(16)
  }

  private var actions: HomeItemActions {
    HomeItemActions(
      onOpen: onOpen,
      onRemove: onRemove,
      onAddFavorite: onAddFavorite,
      onReveal: onReveal,
      onDeleteFile: onDeleteFile,
      onRename: onRename,
    )
  }

  private func select(_ item: HomeCollectionItem) {
    if isSelecting {
      if selectedItemIDs.contains(item.id) {
        selectedItemIDs.remove(item.id)
      } else {
        selectedItemIDs.insert(item.id)
      }
    } else {
      selectedItemIDs = [item.id]
    }
  }

  private func comparisonResult(
    _ first: HomeCollectionItem,
    _ second: HomeCollectionItem,
  ) -> ComparisonResult {
    switch sort {
    case .name:
      first.displayName.localizedStandardCompare(second.displayName)
    case .lastOpenedAt:
      compare(first.sortDate ?? .distantPast, second.sortDate ?? .distantPast)
    case .modifiedAt:
      compare(
        first.contentModificationDate ?? .distantPast,
        second.contentModificationDate ?? .distantPast,
      )
    case .fileSize:
      compare(first.fileSize, second.fileSize)
    }
  }

  private func compare<T: Comparable>(_ first: T, _ second: T) -> ComparisonResult {
    if first < second { return .orderedAscending }
    if first > second { return .orderedDescending }
    return .orderedSame
  }
}

private struct HomeCollectionListHeader: View {
  var body: some View {
    HStack(spacing: 12) {
      Text("")
        .frame(width: 58)

      Text("Name")
        .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

      Text("Last Opened")
        .frame(width: 116, alignment: .leading)

      Text("Size")
        .frame(width: 88, alignment: .trailing)

      Text("")
        .frame(width: 28)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(.regularMaterial)
  }
}

private struct HomeCollectionListRow: View {
  let item: HomeCollectionItem
  let isSelected: Bool
  let isSelecting: Bool
  let actions: HomeItemActions
  let onSelect: () -> Void
  let onOpen: () -> Void

  @State private var isHovered = false

  var body: some View {
    HStack(spacing: 12) {
      HomeThumbnailView(
        item: item,
        isSelected: isSelected,
        isSelecting: isSelecting,
      )
      .frame(width: 58, height: 58)

      VStack(alignment: .leading, spacing: 3) {
        Text(item.displayName)
          .font(.callout)
          .lineLimit(1)
          .truncationMode(.middle)

        Text(item.location)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

      Text(relativeDateDescription(for: item.sortDate))
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(width: 116, alignment: .leading)

      Text(item.fileSizeDescription)
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 88, alignment: .trailing)

      HomeItemActionsMenu(item: item, actions: actions)
        .frame(width: 28)
    }
    .padding(.horizontal, 12)
    .frame(height: 76)
    .contentShape(Rectangle())
    .background(rowBackground)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .onHover { isHovered = $0 }
    .onTapGesture(count: 2, perform: onOpen)
    .simultaneousGesture(TapGesture(count: 1).onEnded { onSelect() })
    .contextMenu {
      HomeItemActionsContent(item: item, actions: actions)
    }
    .help(item.location)
  }

  private var rowBackground: some ShapeStyle {
    if isSelected {
      return Color.accentColor.opacity(0.18)
    }

    if isHovered {
      return Color.primary.opacity(0.06)
    }

    return Color.clear
  }
}

private struct HomeCollectionGridItem: View {
  let item: HomeCollectionItem
  let isSelected: Bool
  let isSelecting: Bool
  let actions: HomeItemActions
  let onSelect: () -> Void
  let onOpen: () -> Void

  @State private var isHovered = false

  var body: some View {
    HomeThumbnailView(
      item: item,
      isSelected: isSelected,
      isSelecting: isSelecting,
    )
    .aspectRatio(1, contentMode: .fit)
    .overlay(alignment: .bottom) {
      if isHovered {
        Text(item.displayName)
          .font(.caption)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 7)
          .padding(.vertical, 5)
          .background(.regularMaterial)
      }
    }
    .contentShape(Rectangle())
    .onHover { isHovered = $0 }
    .onTapGesture(count: 2, perform: onOpen)
    .simultaneousGesture(TapGesture(count: 1).onEnded { onSelect() })
    .contextMenu {
      HomeItemActionsContent(item: item, actions: actions)
    }
    .help(item.displayName)
  }
}

private struct HomeThumbnailView: View {
  let item: HomeCollectionItem
  let isSelected: Bool
  let isSelecting: Bool

  private var thumbnailImage: NSImage? {
    guard let thumbnailCacheKey = item.thumbnailCacheKey else { return nil }

    return NSImage(contentsOf: ImageThumbnailCache.thumbnailURL(for: thumbnailCacheKey))
  }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.controlBackground)

      if item.kind == .folder {
        Image(systemName: "folder.fill")
          .font(.system(size: 34))
          .foregroundStyle(.yellow)
      } else if let thumbnailImage {
        Image(nsImage: thumbnailImage)
          .resizable()
          .scaledToFill()
      } else {
        Image(systemName: "photo")
          .font(.system(size: 28))
          .foregroundStyle(.secondary)
      }

      if isSelecting, isSelected {
        VStack {
          HStack {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 18))
              .symbolRenderingMode(.palette)
              .foregroundStyle(.white, Color.accentColor)
              .padding(5)
          }
          Spacer()
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(
          isSelected ? Color.accentColor : Color.separator.opacity(0.5),
          lineWidth: isSelected ? 2 : 1,
        )
    }
  }
}

private struct HomeItemActions {
  let onOpen: (HomeCollectionItem) -> Void
  let onRemove: (HomeCollectionItem) -> Void
  let onAddFavorite: (HomeCollectionItem) -> Void
  let onReveal: (HomeCollectionItem) -> Void
  let onDeleteFile: (HomeCollectionItem) -> Void
  let onRename: (HomeCollectionItem) -> Void
}

private struct HomeItemActionsMenu: View {
  let item: HomeCollectionItem
  let actions: HomeItemActions

  var body: some View {
    Menu {
      HomeItemActionsContent(item: item, actions: actions)
    } label: {
      Label("More", systemImage: "ellipsis.circle")
    }
    .menuStyle(.button)
    .labelStyle(.iconOnly)
    .help("More")
  }
}

private struct HomeItemActionsContent: View {
  let item: HomeCollectionItem
  let actions: HomeItemActions

  var body: some View {
    Button {
      actions.onOpen(item)
    } label: {
      Label("Open", systemImage: item.kind == .folder ? "folder" : "photo")
    }

    Button {
      actions.onRename(item)
    } label: {
      Label("Rename", systemImage: "pencil")
    }
    .disabled(item.url == nil)

    Button(role: .destructive) {
      actions.onDeleteFile(item)
    } label: {
      Label("Move to Trash", systemImage: "trash")
    }
    .disabled(item.url == nil)

    Divider()

    if item.source == .recent {
      Button {
        actions.onRemove(item)
      } label: {
        Label("Remove from Recents", systemImage: "minus.circle")
      }
    }

    if item.source == .favorite {
      Button {
        actions.onRemove(item)
      } label: {
        Label("Remove from Favorites", systemImage: "minus.circle")
      }
    }

    if item.source != .favorite {
      Button {
        actions.onAddFavorite(item)
      } label: {
        Label("Add to Favorites", systemImage: "star")
      }
    }

    Button {
      actions.onReveal(item)
    } label: {
      Label("Show in Finder", systemImage: "folder")
    }
    .disabled(item.url == nil)
  }
}

struct RenameFileSheet: View {
  let item: HomeCollectionItem
  @Binding var fileName: String
  let onCancel: () -> Void
  let onRename: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Rename")
        .font(.headline)

      TextField("Name", text: $fileName)
        .textFieldStyle(.roundedBorder)
        .frame(width: 320)

      HStack {
        Spacer()

        Button("Cancel") {
          onCancel()
        }
        .keyboardShortcut(.cancelAction)

        Button("Rename") {
          onRename(fileName)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 380)
  }
}

private func relativeDateDescription(for date: Date?) -> String {
  guard let date else { return "--" }

  let formatter = RelativeDateTimeFormatter()
  formatter.unitsStyle = .full
  return formatter.localizedString(for: date, relativeTo: .now)
}
