//
//  ImageCollectionView.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/4.
//

import SwiftUI

enum ImageCollectionViewMode: String, CaseIterable, Identifiable {
  case list
  case grid

  var id: Self { self }

  var title: String {
    switch self {
    case .list: "List"
    case .grid: "Grid"
    }
  }

  var systemImage: String {
    switch self {
    case .list: "list.bullet"
    case .grid: "square.grid.2x2"
    }
  }
}

enum ImageCollectionSort: String, CaseIterable, Identifiable {
  case name
  case lastOpenedAt
  case modifiedAt
  case fileSize

  var id: Self { self }

  var title: String {
    switch self {
    case .name: "Name"
    case .lastOpenedAt: "Last Opened"
    case .modifiedAt: "Modified"
    case .fileSize: "Size"
    }
  }

  var systemImage: String {
    switch self {
    case .name: "textformat"
    case .lastOpenedAt: "clock"
    case .modifiedAt: "calendar"
    case .fileSize: "externaldrive"
    }
  }
}

enum ImageCollectionSortDirection {
  case ascending
  case descending

  mutating func toggle() {
    self = self == .ascending ? .descending : .ascending
  }

  var systemImage: String {
    switch self {
    case .ascending: "arrow.up"
    case .descending: "arrow.down"
    }
  }

  var title: String {
    switch self {
    case .ascending: "Ascending"
    case .descending: "Descending"
    }
  }
}

struct ImageCollectionItemContext<Item> {
  let item: Item
  let isSelected: Bool
  let isSelecting: Bool
  let isHovered: Bool
  let viewMode: ImageCollectionViewMode
}

struct ImageCollectionView<
  Item: Identifiable & Hashable,
  EmptyContent: View,
  ListRowContent: View,
  GridItemContent: View,
  ContextMenuContent: View,
  SelectionActionsContent: View
>: View where Item.ID: Hashable {
  let title: String?
  let subtitle: String?
  let items: [Item]
  let keepsFoldersFirst: Bool
  let listRowHeight: CGFloat
  let gridMinimumItemWidth: CGFloat
  let gridMaximumItemWidth: CGFloat
  let gridSpacing: CGFloat
  let clearTitle: String?
  let onClear: (() -> Void)?
  let onOpen: (Item) -> Void
  let searchableText: (Item) -> String
  let name: (Item) -> String
  let lastOpenedAt: (Item) -> Date?
  let modifiedAt: (Item) -> Date?
  let fileSize: (Item) -> Int
  let isFolder: (Item) -> Bool
  let emptyView: () -> EmptyContent
  let listRow: (ImageCollectionItemContext<Item>) -> ListRowContent
  let gridItem: (ImageCollectionItemContext<Item>) -> GridItemContent
  let contextMenu: (Item) -> ContextMenuContent
  let selectionActions: ([Item]) -> SelectionActionsContent

  @State private var searchText = ""
  @State private var isSearchExpanded = false
  @State private var sort: ImageCollectionSort
  @State private var sortDirection: ImageCollectionSortDirection
  @State private var viewMode: ImageCollectionViewMode
  @State private var isSelecting = false
  @State private var selectedItemIDs = Set<Item.ID>()
  @FocusState private var isSearchFocused: Bool

  private var visibleItems: [Item] {
    let filteredItems = if searchText.isEmpty {
      items
    } else {
      items.filter {
        searchableText($0).localizedStandardContains(searchText)
      }
    }

    return filteredItems.sorted { first, second in
      if keepsFoldersFirst, isFolder(first) != isFolder(second) {
        return isFolder(first)
      }

      let result = comparisonResult(first, second)
      if result == .orderedSame {
        return name(first).localizedStandardCompare(name(second)) == .orderedAscending
      }

      return sortDirection == .ascending ? result == .orderedAscending : result == .orderedDescending
    }
  }

  private var selectedItems: [Item] {
    visibleItems.filter { selectedItemIDs.contains($0.id) }
  }

  private var itemIDs: [Item.ID] {
    items.map(\.id)
  }

  init(
    title: String? = nil,
    subtitle: String? = nil,
    items: [Item],
    defaultSort: ImageCollectionSort = .lastOpenedAt,
    defaultSortDirection: ImageCollectionSortDirection = .descending,
    defaultViewMode: ImageCollectionViewMode = .list,
    keepsFoldersFirst: Bool = false,
    listRowHeight: CGFloat = 76,
    gridMinimumItemWidth: CGFloat = 132,
    gridMaximumItemWidth: CGFloat = 180,
    gridSpacing: CGFloat = 16,
    clearTitle: String? = nil,
    onClear: (() -> Void)? = nil,
    onOpen: @escaping (Item) -> Void,
    searchableText: @escaping (Item) -> String,
    name: @escaping (Item) -> String,
    lastOpenedAt: @escaping (Item) -> Date?,
    modifiedAt: @escaping (Item) -> Date?,
    fileSize: @escaping (Item) -> Int,
    isFolder: @escaping (Item) -> Bool = { _ in false },
    @ViewBuilder emptyView: @escaping () -> EmptyContent,
    @ViewBuilder listRow: @escaping (ImageCollectionItemContext<Item>) -> ListRowContent,
    @ViewBuilder gridItem: @escaping (ImageCollectionItemContext<Item>) -> GridItemContent,
    @ViewBuilder contextMenu: @escaping (Item) -> ContextMenuContent,
    @ViewBuilder selectionActions: @escaping ([Item]) -> SelectionActionsContent,
  ) {
    self.title = title
    self.subtitle = subtitle
    self.items = items
    self.keepsFoldersFirst = keepsFoldersFirst
    self.listRowHeight = listRowHeight
    self.gridMinimumItemWidth = gridMinimumItemWidth
    self.gridMaximumItemWidth = gridMaximumItemWidth
    self.gridSpacing = gridSpacing
    self.clearTitle = clearTitle
    self.onClear = onClear
    self.onOpen = onOpen
    self.searchableText = searchableText
    self.name = name
    self.lastOpenedAt = lastOpenedAt
    self.modifiedAt = modifiedAt
    self.fileSize = fileSize
    self.isFolder = isFolder
    self.emptyView = emptyView
    self.listRow = listRow
    self.gridItem = gridItem
    self.contextMenu = contextMenu
    self.selectionActions = selectionActions
    _sort = State(initialValue: defaultSort)
    _sortDirection = State(initialValue: defaultSortDirection)
    _viewMode = State(initialValue: defaultViewMode)
  }

  var body: some View {
    VStack(spacing: 0) {
      collectionToolbar
        .zIndex(10)

      if visibleItems.isEmpty {
        emptyView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
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
      titleBlock

      Spacer(minLength: 8)

      searchControl
        .animation(.easeInOut(duration: 0.16), value: isSearchExpanded)

      sortMenu

      Picker("View", selection: $viewMode) {
        ForEach(ImageCollectionViewMode.allCases) { mode in
          Label(mode.title, systemImage: mode.systemImage)
            .labelStyle(.iconOnly)
            .tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .labelStyle(.iconOnly)
      .labelsHidden()
      .frame(width: 72)
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
          selectionActions(selectedItems)
        } label: {
          Label("Batch Actions", systemImage: "ellipsis.circle")
        }
        .menuStyle(.button)
        .labelStyle(.iconOnly)
        .help("Batch Actions")
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
    .buttonStyle(.borderless)
    .controlSize(.small)
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .background(.regularMaterial)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color.separator.opacity(0.65))
        .frame(height: 1)
    }
  }

  @ViewBuilder
  private var titleBlock: some View {
    if title != nil || subtitle != nil {
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
      .frame(minWidth: 70, maxWidth: 220, alignment: .leading)
    }
  }

  @ViewBuilder
  private var searchControl: some View {
    if isSearchExpanded {
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)

        TextField("Search", text: $searchText)
          .textFieldStyle(.plain)
          .focused($isSearchFocused)

        Button {
          if searchText.isEmpty {
            isSearchExpanded = false
            isSearchFocused = false
          } else {
            searchText = ""
          }
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(searchText.isEmpty ? "Close Search" : "Clear Search")
      }
      .font(.callout)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .frame(width: 180)
      .background(Color.controlBackground.opacity(0.9))
      .clipShape(RoundedRectangle(cornerRadius: 7))
      .transition(.opacity.combined(with: .move(edge: .trailing)))
      .onAppear {
        isSearchFocused = true
      }
    } else {
      Button {
        isSearchExpanded = true
      } label: {
        Label("Search", systemImage: "magnifyingglass")
      }
      .labelStyle(.iconOnly)
      .help("Search")
    }
  }

  private var sortMenu: some View {
    Menu {
      Button {
        sortDirection.toggle()
      } label: {
        Label(sortDirection.title, systemImage: sortDirection.systemImage)
      }

      Divider()

      ForEach(ImageCollectionSort.allCases) { sortOption in
        Button {
          sort = sortOption
        } label: {
          Label(sortOption.title, systemImage: sortOption.systemImage)
        }
      }
    } label: {
      Label("Sort", systemImage: sort.systemImage)
    }
    .menuStyle(.button)
    .labelStyle(.iconOnly)
    .help("Sort by \(sort.title), \(sortDirection.title)")
  }

  private var listContent: some View {
    LazyVStack(spacing: 2) {
      ForEach(visibleItems) { item in
        ImageCollectionListRowContainer(
          item: item,
          isSelected: selectedItemIDs.contains(item.id),
          isSelecting: isSelecting,
          viewMode: viewMode,
          rowHeight: listRowHeight,
          listRow: listRow,
          contextMenu: contextMenu,
          onSelect: { select(item) },
          onOpen: { onOpen(item) },
        )
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 10)
  }

  private var gridContent: some View {
    LazyVGrid(
      columns: [
        GridItem(
          .adaptive(minimum: gridMinimumItemWidth, maximum: gridMaximumItemWidth),
          spacing: gridSpacing,
          alignment: .top,
        ),
      ],
      alignment: .center,
      spacing: gridSpacing,
    ) {
      ForEach(visibleItems) { item in
        ImageCollectionGridItemContainer(
          item: item,
          isSelected: selectedItemIDs.contains(item.id),
          isSelecting: isSelecting,
          viewMode: viewMode,
          gridItem: gridItem,
          contextMenu: contextMenu,
          onSelect: { select(item) },
          onOpen: { onOpen(item) },
        )
      }
    }
    .padding(gridSpacing)
  }

  private func select(_ item: Item) {
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

  private func comparisonResult(_ first: Item, _ second: Item) -> ComparisonResult {
    switch sort {
    case .name:
      name(first).localizedStandardCompare(name(second))
    case .lastOpenedAt:
      compare(lastOpenedAt(first) ?? .distantPast, lastOpenedAt(second) ?? .distantPast)
    case .modifiedAt:
      compare(modifiedAt(first) ?? .distantPast, modifiedAt(second) ?? .distantPast)
    case .fileSize:
      compare(fileSize(first), fileSize(second))
    }
  }

  private func compare<T: Comparable>(_ first: T, _ second: T) -> ComparisonResult {
    if first < second { return .orderedAscending }
    if first > second { return .orderedDescending }
    return .orderedSame
  }
}

private struct ImageCollectionListRowContainer<
  Item,
  Content: View,
  ContextMenuContent: View
>: View {
  let item: Item
  let isSelected: Bool
  let isSelecting: Bool
  let viewMode: ImageCollectionViewMode
  let rowHeight: CGFloat
  let listRow: (ImageCollectionItemContext<Item>) -> Content
  let contextMenu: (Item) -> ContextMenuContent
  let onSelect: () -> Void
  let onOpen: () -> Void

  @State private var isHovered = false

  var body: some View {
    listRow(context)
      .frame(maxWidth: .infinity)
      .frame(height: rowHeight)
      .contentShape(Rectangle())
      .background(rowBackground)
      .clipShape(RoundedRectangle(cornerRadius: 7))
      .onHover { isHovered = $0 }
      .onTapGesture(count: 2, perform: onOpen)
      .simultaneousGesture(TapGesture(count: 1).onEnded { onSelect() })
      .contextMenu {
        contextMenu(item)
      }
  }

  private var context: ImageCollectionItemContext<Item> {
    ImageCollectionItemContext(
      item: item,
      isSelected: isSelected,
      isSelecting: isSelecting,
      isHovered: isHovered,
      viewMode: viewMode,
    )
  }

  private var rowBackground: Color {
    if isSelected {
      return Color.accentColor.opacity(0.18)
    }

    if isHovered {
      return Color.primary.opacity(0.06)
    }

    return .clear
  }
}

private struct ImageCollectionGridItemContainer<
  Item,
  Content: View,
  ContextMenuContent: View
>: View {
  let item: Item
  let isSelected: Bool
  let isSelecting: Bool
  let viewMode: ImageCollectionViewMode
  let gridItem: (ImageCollectionItemContext<Item>) -> Content
  let contextMenu: (Item) -> ContextMenuContent
  let onSelect: () -> Void
  let onOpen: () -> Void

  @State private var isHovered = false

  var body: some View {
    gridItem(context)
      .frame(maxWidth: .infinity)
      .aspectRatio(1, contentMode: .fit)
      .contentShape(Rectangle())
      .onHover { isHovered = $0 }
      .onTapGesture(count: 2, perform: onOpen)
      .simultaneousGesture(TapGesture(count: 1).onEnded { onSelect() })
      .contextMenu {
        contextMenu(item)
      }
  }

  private var context: ImageCollectionItemContext<Item> {
    ImageCollectionItemContext(
      item: item,
      isSelected: isSelected,
      isSelecting: isSelecting,
      isHovered: isHovered,
      viewMode: viewMode,
    )
  }
}
