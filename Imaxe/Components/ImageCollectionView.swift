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

struct ImageCollectionSortOption<Item>: Identifiable {
  let id: String
  let title: String
  let systemImage: String
  let compare: (Item, Item) -> ComparisonResult

  init(
    _ id: String,
    title: String,
    systemImage: String,
    compare: @escaping (Item, Item) -> ComparisonResult,
  ) {
    self.id = id
    self.title = title
    self.systemImage = systemImage
    self.compare = compare
  }

  init<Value: Comparable>(
    _ id: String,
    title: String,
    systemImage: String,
    value: @escaping (Item) -> Value,
  ) {
    self.init(id, title: title, systemImage: systemImage) { first, second in
      compareValues(value(first), value(second))
    }
  }

  init<Value: Comparable>(
    _ id: String,
    title: String,
    systemImage: String,
    optionalValue: @escaping (Item) -> Value?,
  ) {
    self.init(id, title: title, systemImage: systemImage) { first, second in
      compareOptionalValues(optionalValue(first), optionalValue(second))
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
  private var configuration: ImageCollectionConfiguration<Item>
  private let items: [Item]
  private let onOpen: (Item) -> Void
  private let emptyContent: () -> EmptyContent
  private let listRow: (ImageCollectionItemContext<Item>) -> ListRowContent
  private let gridItem: (ImageCollectionItemContext<Item>) -> GridItemContent
  private let contextMenuContent: (Item) -> ContextMenuContent
  private let selectionActionsContent: ([Item]) -> SelectionActionsContent

  @State private var searchText = ""
  @State private var selectedSortID: String?
  @State private var sortDirection: ImageCollectionSortDirection?
  @State private var viewMode: ImageCollectionViewMode?
  @State private var isSelecting = false
  @State private var selectedItemIDs = Set<Item.ID>()
  @FocusState private var isSearchFocused: Bool

  private var visibleItems: [Item] {
    let filteredItems = if let searchableText = configuration.searchableText, !searchText.isEmpty {
      items.filter {
        searchableText($0).localizedStandardContains(searchText)
      }
    } else {
      items
    }

    guard let currentSortOption else {
      return filteredItems
    }

    return filteredItems.sorted { first, second in
      if configuration.keepsFoldersFirst, configuration.isFolder(first) != configuration.isFolder(second) {
        return configuration.isFolder(first)
      }

      let result = currentSortOption.compare(first, second)
      if result == .orderedSame {
        let tieBreakerResult = configuration.tieBreaker(first, second)
        return tieBreakerResult == .orderedAscending
      }

      return currentSortDirection == .ascending ? result == .orderedAscending : result == .orderedDescending
    }
  }

  private var selectedItems: [Item] {
    visibleItems.filter { selectedItemIDs.contains($0.id) }
  }

  private var itemIDs: [Item.ID] {
    items.map(\.id)
  }

  private var currentSortOption: ImageCollectionSortOption<Item>? {
    guard !configuration.sortOptions.isEmpty else { return nil }

    let id = selectedSortID ?? configuration.defaultSortID
    if let id, let option = configuration.sortOptions.first(where: { $0.id == id }) {
      return option
    }

    return configuration.sortOptions.first
  }

  private var currentSortDirection: ImageCollectionSortDirection {
    sortDirection ?? configuration.defaultSortDirection
  }

  private var currentViewMode: ImageCollectionViewMode {
    viewMode ?? configuration.defaultViewMode
  }

  private init(
    configuration: ImageCollectionConfiguration<Item>,
    items: [Item],
    onOpen: @escaping (Item) -> Void,
    @ViewBuilder emptyContent: @escaping () -> EmptyContent,
    @ViewBuilder listRow: @escaping (ImageCollectionItemContext<Item>) -> ListRowContent,
    @ViewBuilder gridItem: @escaping (ImageCollectionItemContext<Item>) -> GridItemContent,
    @ViewBuilder contextMenuContent: @escaping (Item) -> ContextMenuContent,
    @ViewBuilder selectionActionsContent: @escaping ([Item]) -> SelectionActionsContent,
  ) {
    self.configuration = configuration
    self.items = items
    self.onOpen = onOpen
    self.emptyContent = emptyContent
    self.listRow = listRow
    self.gridItem = gridItem
    self.contextMenuContent = contextMenuContent
    self.selectionActionsContent = selectionActionsContent
  }

  var body: some View {
    VStack(spacing: 0) {
      collectionToolbar
        .zIndex(10)

      if visibleItems.isEmpty {
        emptyContent()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView(.vertical) {
          switch currentViewMode {
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

  func collectionTitle(_ title: String, subtitle: String? = nil) -> Self {
    var view = self
    view.configuration.title = title
    view.configuration.subtitle = subtitle
    return view
  }

  func searchableText(_ searchableText: @escaping (Item) -> String) -> Self {
    var view = self
    view.configuration.searchableText = searchableText
    return view
  }

  func sortOptions(
    _ options: [ImageCollectionSortOption<Item>],
    default defaultSortID: String? = nil,
    direction: ImageCollectionSortDirection = .ascending,
  ) -> Self {
    var view = self
    view.configuration.sortOptions = options
    view.configuration.defaultSortID = defaultSortID
    view.configuration.defaultSortDirection = direction
    return view
  }

  func defaultViewMode(_ mode: ImageCollectionViewMode) -> Self {
    var view = self
    view.configuration.defaultViewMode = mode
    return view
  }

  func listRowHeight(_ height: CGFloat) -> Self {
    var view = self
    view.configuration.listRowHeight = height
    return view
  }

  func gridItemSize(minimum: CGFloat, maximum: CGFloat? = nil, spacing: CGFloat = 16) -> Self {
    var view = self
    view.configuration.gridMinimumItemWidth = minimum
    view.configuration.gridMaximumItemWidth = maximum ?? minimum
    view.configuration.gridSpacing = spacing
    return view
  }

  func keepsFoldersFirst(_ isEnabled: Bool = true, isFolder: @escaping (Item) -> Bool) -> Self {
    var view = self
    view.configuration.keepsFoldersFirst = isEnabled
    view.configuration.isFolder = isFolder
    return view
  }

  func tieBreaker(_ compare: @escaping (Item, Item) -> ComparisonResult) -> Self {
    var view = self
    view.configuration.tieBreaker = compare
    return view
  }

  func clearAction(_ title: String, _ action: @escaping () -> Void) -> Self {
    var view = self
    view.configuration.clearTitle = title
    view.configuration.onClear = action
    return view
  }

  func contextMenu<MenuContent: View>(
    @ViewBuilder _ content: @escaping (Item) -> MenuContent,
  ) -> ImageCollectionView<
    Item,
    EmptyContent,
    ListRowContent,
    GridItemContent,
    MenuContent,
    SelectionActionsContent
  > {
    var configuration = configuration
    configuration.hasContextMenu = true

    return ImageCollectionView<
      Item,
      EmptyContent,
      ListRowContent,
      GridItemContent,
      MenuContent,
      SelectionActionsContent
    >(
      configuration: configuration,
      items: items,
      onOpen: onOpen,
      emptyContent: emptyContent,
      listRow: listRow,
      gridItem: gridItem,
      contextMenuContent: content,
      selectionActionsContent: selectionActionsContent,
    )
  }

  func selectionActions<ActionsContent: View>(
    @ViewBuilder _ content: @escaping ([Item]) -> ActionsContent,
  ) -> ImageCollectionView<
    Item,
    EmptyContent,
    ListRowContent,
    GridItemContent,
    ContextMenuContent,
    ActionsContent
  > {
    var configuration = configuration
    configuration.hasSelectionActions = true

    return ImageCollectionView<
      Item,
      EmptyContent,
      ListRowContent,
      GridItemContent,
      ContextMenuContent,
      ActionsContent
    >(
      configuration: configuration,
      items: items,
      onOpen: onOpen,
      emptyContent: emptyContent,
      listRow: listRow,
      gridItem: gridItem,
      contextMenuContent: contextMenuContent,
      selectionActionsContent: content,
    )
  }

  private var collectionToolbar: some View {
    HStack(spacing: 10) {
      titleBlock

      Spacer(minLength: 12)

      searchControl

      sortMenu

      Picker("View", selection: viewModeBinding) {
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

      if configuration.hasSelectionActions, isSelecting, !selectedItems.isEmpty {
        Menu {
          selectionActionsContent(selectedItems)
        } label: {
          Label("Batch Actions", systemImage: "ellipsis.circle")
        }
        .menuStyle(.button)
        .labelStyle(.iconOnly)
        .help("Batch Actions")
      }

      if let clearTitle = configuration.clearTitle, let onClear = configuration.onClear {
        Button(role: .destructive) {
          onClear()
        } label: {
          Label(clearTitle, systemImage: "clear")
        }
        .labelStyle(.iconOnly)
        .disabled(items.isEmpty)
        .help(clearTitle)
      }
    }
    .buttonStyle(.borderless)
    .controlSize(.small)
    .padding(.horizontal, 24)
    .padding(.vertical, 12)
    .background(.regularMaterial)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(.separator.opacity(0.55))
        .frame(height: 1)
    }
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(.separator.opacity(0.5))
        .frame(height: 1)
    }
  }

  @ViewBuilder
  private var titleBlock: some View {
    if configuration.title != nil || configuration.subtitle != nil {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        if let title = configuration.title {
          Text(title)
            .font(.headline)
            .lineLimit(1)
        }

        if let subtitle = configuration.subtitle {
          Text(subtitle)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      .frame(minWidth: 120, maxWidth: 360, alignment: .leading)
    }
  }

  @ViewBuilder
  private var searchControl: some View {
    if configuration.searchableText != nil {
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass")
          .font(.caption)
          .foregroundStyle(.secondary)

        TextField("Search", text: $searchText)
          .textFieldStyle(.plain)
          .focused($isSearchFocused)

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
      .padding(.horizontal, 9)
      .padding(.vertical, 6)
      .frame(width: 180)
      .background(.controlBackground.opacity(0.65))
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .onTapGesture {
        isSearchFocused = true
      }
    }
  }

  @ViewBuilder
  private var sortMenu: some View {
    if let currentSortOption {
      Menu {
        Button {
          sortDirection = currentSortDirection == .ascending ? .descending : .ascending
        } label: {
          Label(currentSortDirection.title, systemImage: currentSortDirection.systemImage)
        }

        Divider()

        ForEach(configuration.sortOptions) { sortOption in
          Button {
            selectedSortID = sortOption.id
          } label: {
            Label(sortOption.title, systemImage: sortOption.systemImage)
          }
        }
      } label: {
        Label("Sort", systemImage: currentSortOption.systemImage)
      }
      .menuStyle(.button)
      .labelStyle(.iconOnly)
      .help("Sort by \(currentSortOption.title), \(currentSortDirection.title)")
    }
  }

  private var listContent: some View {
    LazyVStack(spacing: 2) {
      ForEach(visibleItems) { item in
        ImageCollectionListRowContainer(
          item: item,
          isSelected: selectedItemIDs.contains(item.id),
          isSelecting: isSelecting,
          hasContextMenu: configuration.hasContextMenu,
          viewMode: currentViewMode,
          rowHeight: configuration.listRowHeight,
          listRow: listRow,
          contextMenuContent: contextMenuContent,
          onSelect: { select(item) },
          onOpen: { onOpen(item) },
        )
      }
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 10)
  }

  private var gridContent: some View {
    LazyVGrid(
      columns: [
        GridItem(
          .adaptive(
            minimum: configuration.gridMinimumItemWidth,
            maximum: configuration.gridMaximumItemWidth,
          ),
          spacing: configuration.gridSpacing,
          alignment: .top,
        ),
      ],
      alignment: .center,
      spacing: configuration.gridSpacing,
    ) {
      ForEach(visibleItems) { item in
        ImageCollectionGridItemContainer(
          item: item,
          isSelected: selectedItemIDs.contains(item.id),
          isSelecting: isSelecting,
          hasContextMenu: configuration.hasContextMenu,
          viewMode: currentViewMode,
          gridItem: gridItem,
          contextMenuContent: contextMenuContent,
          onSelect: { select(item) },
          onOpen: { onOpen(item) },
        )
      }
    }
    .padding(configuration.gridSpacing)
  }

  private var viewModeBinding: Binding<ImageCollectionViewMode> {
    Binding {
      currentViewMode
    } set: { newMode in
      viewMode = newMode
    }
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
}

extension ImageCollectionView where ContextMenuContent == EmptyView, SelectionActionsContent == EmptyView {
  init(
    _ items: [Item],
    onOpen: @escaping (Item) -> Void,
    @ViewBuilder emptyContent: @escaping () -> EmptyContent,
    @ViewBuilder listRow: @escaping (ImageCollectionItemContext<Item>) -> ListRowContent,
    @ViewBuilder gridItem: @escaping (ImageCollectionItemContext<Item>) -> GridItemContent,
  ) {
    self.init(
      configuration: ImageCollectionConfiguration(),
      items: items,
      onOpen: onOpen,
      emptyContent: emptyContent,
      listRow: listRow,
      gridItem: gridItem,
      contextMenuContent: { _ in EmptyView() },
      selectionActionsContent: { _ in EmptyView() },
    )
  }
}

private struct ImageCollectionConfiguration<Item> {
  var title: String?
  var subtitle: String?
  var searchableText: ((Item) -> String)?
  var sortOptions = [ImageCollectionSortOption<Item>]()
  var defaultSortID: String?
  var defaultSortDirection = ImageCollectionSortDirection.ascending
  var defaultViewMode = ImageCollectionViewMode.list
  var keepsFoldersFirst = false
  var isFolder: (Item) -> Bool = { _ in false }
  var tieBreaker: (Item, Item) -> ComparisonResult = { _, _ in .orderedSame }
  var listRowHeight: CGFloat = 84
  var gridMinimumItemWidth: CGFloat = 132
  var gridMaximumItemWidth: CGFloat = 180
  var gridSpacing: CGFloat = 16
  var clearTitle: String?
  var onClear: (() -> Void)?
  var hasContextMenu = false
  var hasSelectionActions = false
}

private struct ImageCollectionListRowContainer<
  Item,
  Content: View,
  ContextMenuContent: View
>: View {
  let item: Item
  let isSelected: Bool
  let isSelecting: Bool
  let hasContextMenu: Bool
  let viewMode: ImageCollectionViewMode
  let rowHeight: CGFloat
  let listRow: (ImageCollectionItemContext<Item>) -> Content
  let contextMenuContent: (Item) -> ContextMenuContent
  let onSelect: () -> Void
  let onOpen: () -> Void

  @State private var isHovered = false

  var body: some View {
    let row = listRow(context)
      .frame(maxWidth: .infinity)
      .frame(height: rowHeight)
      .contentShape(Rectangle())
      .background(rowBackground)
      .clipShape(RoundedRectangle(cornerRadius: 9))
      .onHover { isHovered = $0 }
      .onTapGesture(count: 2, perform: onOpen)
      .simultaneousGesture(TapGesture(count: 1).onEnded { onSelect() })

    if hasContextMenu {
      row.contextMenu {
        contextMenuContent(item)
      }
    } else {
      row
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
      return Color.accentColor.opacity(0.16)
    }

    if isHovered {
      return Color.primary.opacity(0.055)
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
  let hasContextMenu: Bool
  let viewMode: ImageCollectionViewMode
  let gridItem: (ImageCollectionItemContext<Item>) -> Content
  let contextMenuContent: (Item) -> ContextMenuContent
  let onSelect: () -> Void
  let onOpen: () -> Void

  @State private var isHovered = false

  var body: some View {
    let itemView = gridItem(context)
      .frame(maxWidth: .infinity)
      .aspectRatio(1, contentMode: .fit)
      .contentShape(Rectangle())
      .onHover { isHovered = $0 }
      .onTapGesture(count: 2, perform: onOpen)
      .simultaneousGesture(TapGesture(count: 1).onEnded { onSelect() })

    if hasContextMenu {
      itemView.contextMenu {
        contextMenuContent(item)
      }
    } else {
      itemView
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

private func compareValues<Value: Comparable>(_ first: Value, _ second: Value) -> ComparisonResult {
  if first < second { return .orderedAscending }
  if first > second { return .orderedDescending }
  return .orderedSame
}

private func compareOptionalValues<Value: Comparable>(_ first: Value?, _ second: Value?) -> ComparisonResult {
  switch (first, second) {
  case let (first?, second?):
    return compareValues(first, second)
  case (nil, nil):
    return .orderedSame
  case (nil, _):
    return .orderedAscending
  case (_, nil):
    return .orderedDescending
  }
}
