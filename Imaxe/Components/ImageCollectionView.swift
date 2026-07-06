//
//  ImageCollectionView.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/4.
//

import SwiftUI

// MARK: - Enums and Structs

enum ImageCollectionViewMode: String, CaseIterable, Identifiable {
  case list
  case grid

  var id: Self {
    self
  }

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

struct ImageCollectionSortOption<Item>: Identifiable, Equatable {
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

  init(
    _ id: String,
    title: String,
    systemImage: String,
    value: @escaping (Item) -> some Comparable,
  ) {
    self.init(id, title: title, systemImage: systemImage) { first, second in
      compareValues(value(first), value(second))
    }
  }

  init(
    _ id: String,
    title: String,
    systemImage: String,
    optionalValue: @escaping (Item) -> (some Comparable)?,
  ) {
    self.init(id, title: title, systemImage: systemImage) { first, second in
      compareOptionalValues(optionalValue(first), optionalValue(second))
    }
  }

  static func == (
    lhs: ImageCollectionSortOption<Item>,
    rhs: ImageCollectionSortOption<Item>,
  ) -> Bool {
    lhs.id == rhs.id
  }
}

struct ImageCollectionItemContext<Item> {
  let item: Item
  let isHovered: Bool
  let viewMode: ImageCollectionViewMode
}

// MARK: - ImageCollectionView

struct ImageCollectionView<
  Item: Identifiable & Hashable,
  EmptyContent: View,
  ListRowContent: View,
  GridItemContent: View,
  ContextMenuContent: View,
  SelectionActionsContent: View,
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
      if configuration.keepsFoldersFirst,
         configuration.isFolder(first) != configuration.isFolder(second)
      {
        return configuration.isFolder(first)
      }

      let result = currentSortOption.compare(first, second)
      if result == .orderedSame {
        let tieBreakerResult = configuration.tieBreaker(first, second)
        return tieBreakerResult == .orderedAscending
      }

      return currentSortDirection == .ascending ? result == .orderedAscending : result ==
        .orderedDescending
    }
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

  private var viewModeBinding: Binding<ImageCollectionViewMode> {
    Binding {
      currentViewMode
    } set: { newMode in
      viewMode = newMode
    }
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

      if visibleItems.isEmpty {
        emptyContent()
      } else {
        ScrollView(.vertical) {
          switch currentViewMode {
          case .list:
            listContent
          case .grid:
            gridContent
          }
        }
      }
    }
  }

  private let collectionToolBarHeight: CGFloat = 32
  private let collectionToolBarButtonHeight: CGFloat = 26

  private var collectionToolbar: some View {
    HStack(spacing: 2) {
      titleBlock

      Spacer()

      if configuration.searchableText != nil {
        SearchField("Search", text: $searchText)
          .foldable(true)
          .frame(maxWidth: 220, fieldHeight: collectionToolBarButtonHeight)
      }

      sortMenu

      MaterialSegmentedPicker(
        selection: viewModeBinding,
        items: ImageCollectionViewMode.allCases,
      ) { mode in
        Label(mode.title, systemImage: mode.systemImage)
          .labelStyle(.iconOnly)
          .font(.system(size: 13, weight: .medium))
      }
      .frame(height: collectionToolBarHeight - 4)

      clearButton
    }
    .padding(.horizontal, 12)
    .frame(height: collectionToolBarHeight, alignment: .center)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(.separator.opacity(0.5))
        .frame(height: 1)
    }
  }

  @ViewBuilder
  private var titleBlock: some View {
    if let title = configuration.title {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
          .lineLimit(1)
          .truncationMode(.middle)

        if let subtitle = configuration.subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
    }
  }

  @ViewBuilder
  private var sortMenu: some View {
    if let currentSortOption {
      Menu {
        ForEach(configuration.sortOptions) { sortOption in
          Button {
            selectedSortID = sortOption.id
          } label: {
            Label(sortOption.title, systemImage: currentSortOption == sortOption ? "checkmark" : "")
          }
        }

        Divider()

        Button {
          sortDirection = .ascending
        } label: {
          Label(
            ImageCollectionSortDirection.ascending.title,
            systemImage: currentSortDirection == .ascending ? "checkmark" : "",
          )
        }

        Button {
          sortDirection = .descending
        } label: {
          Label(
            ImageCollectionSortDirection.descending.title,
            systemImage: currentSortDirection == .descending ? "checkmark" : "",
          )
        }
      } label: {
        Label("Sort", systemImage: "arrow.up.arrow.down")
          .labelStyle(.iconOnly)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.secondary)
          .frame(width: collectionToolBarButtonHeight, height: collectionToolBarButtonHeight)
      }
      .menuStyle(.button)
      .buttonStyle(.borderedOnHover(applyPressedEffect: false))
      .help("Sort by \(currentSortOption.title), \(currentSortDirection.title)")
    }
  }

  @ViewBuilder
  private var clearButton: some View {
    if let clearTitle = configuration.clearTitle, let onClear = configuration.onClear {
      Button(role: .destructive) {
        onClear()
      } label: {
        Label(clearTitle, systemImage: "trash")
          .labelStyle(.iconOnly)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.secondary)
          .frame(width: collectionToolBarButtonHeight, height: collectionToolBarButtonHeight)
      }
      .buttonStyle(.borderedOnHover)
      .disabled(items.isEmpty)
      .help(clearTitle)
    }
  }

  private var listContent: some View {
    LazyVStack(spacing: 0) {
      ForEach(visibleItems) { item in
        ImageCollectionListRowContainer(
          item: item,
          hasContextMenu: configuration.hasContextMenu,
          viewMode: currentViewMode,
          listRow: listRow,
          contextMenuContent: contextMenuContent,
          onOpen: { onOpen(item) },
        )
      }
    }
    .padding(3)
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
          hasContextMenu: configuration.hasContextMenu,
          viewMode: currentViewMode,
          gridItem: gridItem,
          contextMenuContent: contextMenuContent,
          onOpen: { onOpen(item) },
        )
      }
    }
    .padding(3)
  }
}

// MARK: - Modifiers

extension ImageCollectionView {
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
    SelectionActionsContent,
  > {
    var configuration = configuration
    configuration.hasContextMenu = true

    return ImageCollectionView<
      Item,
      EmptyContent,
      ListRowContent,
      GridItemContent,
      MenuContent,
      SelectionActionsContent,
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
    ActionsContent,
  > {
    var configuration = configuration
    configuration.hasSelectionActions = true

    return ImageCollectionView<
      Item,
      EmptyContent,
      ListRowContent,
      GridItemContent,
      ContextMenuContent,
      ActionsContent,
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
}

// MARK: - Convenience Initializers

extension ImageCollectionView where ContextMenuContent == EmptyView,
  SelectionActionsContent == EmptyView
{
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

// MARK: - ImageCollectionConfiguration

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
  var gridMinimumItemWidth: CGFloat = 82
  var gridMaximumItemWidth: CGFloat = 120
  var gridSpacing: CGFloat = 2
  var clearTitle: String?
  var onClear: (() -> Void)?
  var hasContextMenu = false
  var hasSelectionActions = false
}

// MARK: - ImageCollectionListRowContainer

private struct ImageCollectionListRowContainer<
  Item,
  Content: View,
  ContextMenuContent: View,
>: View {
  let item: Item
  let hasContextMenu: Bool
  let viewMode: ImageCollectionViewMode
  let listRow: (ImageCollectionItemContext<Item>) -> Content
  let contextMenuContent: (Item) -> ContextMenuContent
  let onOpen: () -> Void

  @State private var isHovered = false

  var body: some View {
    let row = listRow(context)
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
      .background(rowBackground)
      .clipShape(RoundedRectangle(cornerRadius: 9))
      .onHover { isHovered = $0 }
      .onTapGesture(count: 2, perform: onOpen)

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
      isHovered: isHovered,
      viewMode: viewMode,
    )
  }

  private var rowBackground: Color {
    if isHovered {
      return Color.primary.opacity(0.055)
    }

    return .clear
  }
}

// MARK: - ImageCollectionGridItemContainer

private struct ImageCollectionGridItemContainer<
  Item,
  Content: View,
  ContextMenuContent: View,
>: View {
  let item: Item
  let hasContextMenu: Bool
  let viewMode: ImageCollectionViewMode
  let gridItem: (ImageCollectionItemContext<Item>) -> Content
  let contextMenuContent: (Item) -> ContextMenuContent
  let onOpen: () -> Void

  @State private var isHovered = false

  var body: some View {
    let itemView = gridItem(context)
      .frame(maxWidth: .infinity)
      .aspectRatio(1, contentMode: .fit)
      .contentShape(Rectangle())
      .onHover { isHovered = $0 }
      .onTapGesture(count: 2, perform: onOpen)

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
      isHovered: isHovered,
      viewMode: viewMode,
    )
  }
}

// MARK: - Comparison Helpers

private func compareValues<Value: Comparable>(_ first: Value, _ second: Value) -> ComparisonResult {
  if first < second { return .orderedAscending }
  if first > second { return .orderedDescending }
  return .orderedSame
}

private func compareOptionalValues<Value: Comparable>(_ first: Value?,
                                                      _ second: Value?) -> ComparisonResult
{
  switch (first, second) {
  case let (first?, second?):
    compareValues(first, second)
  case (nil, nil):
    .orderedSame
  case (nil, _):
    .orderedAscending
  case (_, nil):
    .orderedDescending
  }
}
