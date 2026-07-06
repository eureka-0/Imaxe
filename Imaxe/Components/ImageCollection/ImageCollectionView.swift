//
//  ImageCollectionView.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/4.
//

import Observation
import SwiftUI

// MARK: - ImageCollectionViewMode

enum ImageCollectionViewMode: String, CaseIterable, Identifiable {
  case list, grid

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

// MARK: - ImageCollectionView

struct ImageCollectionView<EmptyContent: View, ListRowContent: View, GridItemContent: View>: View {
  private let items: [ImageCollectionItem]
  private let onOpen: (ImageCollectionItem) -> Void
  private let emptyContent: () -> EmptyContent
  private let listRow: (ImageCollectionItem) -> ListRowContent
  private let gridItem: (ImageCollectionItem) -> GridItemContent

  @State private var viewModel = ImageCollectionViewModel()

  private let collectionToolBarHeight: CGFloat = 32
  private let collectionToolBarButtonHeight: CGFloat = 26

  private var visibleItems: [ImageCollectionItem] {
    viewModel.visibleItems(from: items)
  }

  init(
    _ items: [ImageCollectionItem],
    onOpen: @escaping (ImageCollectionItem) -> Void,
    @ViewBuilder emptyContent: @escaping () -> EmptyContent,
    @ViewBuilder listRow: @escaping (ImageCollectionItem) -> ListRowContent,
    @ViewBuilder gridItem: @escaping (ImageCollectionItem) -> GridItemContent,
  ) {
    self.items = items
    self.onOpen = onOpen
    self.emptyContent = emptyContent
    self.listRow = listRow
    self.gridItem = gridItem
  }

  var body: some View {
    VStack(spacing: 0) {
      collectionToolbar

      if visibleItems.isEmpty {
        emptyContent()
      } else {
        ScrollView(.vertical) {
          switch viewModel.viewMode {
          case .list:
            listContent
          case .grid:
            gridContent
          }
        }
      }
    }
  }

  private var collectionToolbar: some View {
    HStack(spacing: 2) {
      titleBlock

      Spacer()

      if viewModel.searchableText != nil {
        SearchField("Search", text: $viewModel.searchText)
          .foldable(true)
          .frame(maxWidth: 220, fieldHeight: collectionToolBarButtonHeight)
      }

      sortMenu

      MaterialSegmentedPicker(
        selection: $viewModel.viewMode,
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
    if let title = viewModel.title {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
          .lineLimit(1)
          .truncationMode(.middle)

        if let subtitle = viewModel.subtitle {
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
    if let currentSortOption = viewModel.currentSortOption {
      Menu {
        ForEach(viewModel.sortOptions) { sortOption in
          Button {
            viewModel.selectedSortOption = sortOption
          } label: {
            Label(sortOption.title, systemImage: currentSortOption == sortOption ? "checkmark" : "")
          }
        }

        Divider()

        Button {
          viewModel.sortAscending = true
        } label: {
          Label(
            "Ascending",
            systemImage: viewModel.sortAscending ? "checkmark" : "",
          )
        }

        Button {
          viewModel.sortAscending = false
        } label: {
          Label(
            "Descending",
            systemImage: !viewModel.sortAscending ? "checkmark" : "",
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
      .help(
        "Sort by \(currentSortOption.title), \(viewModel.sortAscending ? "ascending" : "descending")",
      )
    }
  }

  @ViewBuilder
  private var clearButton: some View {
    if let clearTitle = viewModel.clearTitle, let onClear = viewModel.onClear {
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
        listRowContent(for: item)
      }
    }
    .padding(3)
  }

  @ViewBuilder
  private func listRowContent(for item: ImageCollectionItem) -> some View {
    let row = listRow(item)
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
      .background(item.isHovered ? Color.primary.opacity(0.055) : .clear)
      .clipShape(RoundedRectangle(cornerRadius: 9))
      .onHover { item.isHovered = $0 }
      .onTapGesture(count: 2) {
        onOpen(item)
      }

    if viewModel.hasContextMenu {
      row.contextMenu {
        viewModel.contextMenuContent(item)
      }
    } else {
      row
    }
  }

  private var gridContent: some View {
    LazyVGrid(
      columns: [
        GridItem(
          .adaptive(
            minimum: viewModel.gridMinimumItemWidth,
            maximum: viewModel.gridMaximumItemWidth,
          ),
          spacing: viewModel.gridSpacing,
          alignment: .top,
        ),
      ],
      alignment: .center,
      spacing: viewModel.gridSpacing,
    ) {
      ForEach(visibleItems) { item in
        gridItemContent(for: item)
      }
    }
    .padding(3)
  }

  @ViewBuilder
  private func gridItemContent(for item: ImageCollectionItem) -> some View {
    let itemView = gridItem(item)
      .frame(maxWidth: .infinity)
      .aspectRatio(1, contentMode: .fit)
      .contentShape(Rectangle())
      .onHover { item.isHovered = $0 }
      .onTapGesture(count: 2) {
        onOpen(item)
      }

    if viewModel.hasContextMenu {
      itemView.contextMenu {
        viewModel.contextMenuContent(item)
      }
    } else {
      itemView
    }
  }
}

// MARK: - ImageCollectionViewModel

@Observable
private final class ImageCollectionViewModel {
  var title: String?
  var subtitle: String?
  var searchableText: ((ImageCollectionItem) -> String)?
  var sortOptions: [ImageCollectionSortOption] = []
  var defaultSortOption: ImageCollectionSortOption?

  var gridMinimumItemWidth: CGFloat = 82
  var gridMaximumItemWidth: CGFloat = 120
  var gridSpacing: CGFloat = 2
  var clearTitle: String?
  var onClear: (() -> Void)?
  var hasContextMenu = false
  var contextMenuContent: (ImageCollectionItem) -> AnyView = { _ in AnyView(EmptyView()) }

  var searchText = ""
  var selectedSortOption: ImageCollectionSortOption?
  var sortAscending: Bool = false
  var viewMode: ImageCollectionViewMode = .grid

  var currentSortOption: ImageCollectionSortOption? {
    guard !sortOptions.isEmpty else { return nil }

    if let selectedSortOption {
      return selectedSortOption
    }
    return defaultSortOption
  }

  func visibleItems(from items: [ImageCollectionItem]) -> [ImageCollectionItem] {
    let filteredItems = if let searchableText, !searchText.isEmpty {
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
      let result = currentSortOption.compare(first, second)
      if result == .orderedSame {
        return first.fileName.localizedCompare(second.fileName) == .orderedAscending
      }

      return sortAscending ? result == .orderedAscending : result == .orderedDescending
    }
  }
}

// MARK: - Modifiers

extension ImageCollectionView {
  func collectionTitle(_ title: String, subtitle: String? = nil) -> Self {
    viewModel.title = title
    viewModel.subtitle = subtitle
    return self
  }

  func searchableText(_ searchableText: @escaping (ImageCollectionItem) -> String) -> Self {
    viewModel.searchableText = searchableText
    return self
  }

  func sortOptions(
    _ options: [ImageCollectionSortOption],
    default defaultSortOption: ImageCollectionSortOption? = nil,
  ) -> Self {
    viewModel.sortOptions = options
    viewModel.defaultSortOption = defaultSortOption
    return self
  }

  func sortOptions(
    _ options: [ImageCollectionSortOption],
    default defaultSortOptionID: ImageCollectionSortOption.ID,
  ) -> Self {
    sortOptions(
      options,
      default: options.first { $0.id == defaultSortOptionID },
    )
  }

  func defaultViewMode(_ mode: ImageCollectionViewMode) -> Self {
    viewModel.viewMode = mode
    return self
  }

  func gridItemSize(minimum: CGFloat, maximum: CGFloat? = nil, spacing: CGFloat = 16) -> Self {
    viewModel.gridMinimumItemWidth = minimum
    viewModel.gridMaximumItemWidth = maximum ?? minimum
    viewModel.gridSpacing = spacing
    return self
  }

  func clearAction(_ title: String, _ action: @escaping () -> Void) -> Self {
    viewModel.clearTitle = title
    viewModel.onClear = action
    return self
  }

  func contextMenu(
    @ViewBuilder _ content: @escaping (ImageCollectionItem) -> some View,
  ) -> Self {
    viewModel.hasContextMenu = true
    viewModel.contextMenuContent = { item in
      AnyView(content(item))
    }
    return self
  }
}
