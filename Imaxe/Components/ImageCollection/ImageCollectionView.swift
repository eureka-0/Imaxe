//
//  ImageCollectionView.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/4.
//

import Observation
import SwiftUI

// MARK: - Enums and Models

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

@Observable
final class ImageCollectionItemState {
  var isHovered = false
}

struct ImageCollectionConfiguration<Item: Identifiable> where Item.ID: Hashable {
  var title: String?
  var subtitle: String?
  var useDefaultSubtitle: Bool = true
  var emptyDescription: String?
  var searchableText: ((Item) -> String)?
  var sortOptions: [ImageCollectionSortOption<Item>] = []
  var defaultSortOptionID: ImageCollectionSortOption<Item>.ID?

  var defaultSortOption: ImageCollectionSortOption<Item>? {
    set {
      defaultSortOptionID = newValue?.id
    }
    get {
      guard let defaultSortOptionID else { return nil }
      return sortOptions.first { $0.id == defaultSortOptionID }
    }
  }

  var clearHelpText: String?
  var onClear: (() -> Void)?

  var defaultViewMode: ImageCollectionViewMode = .grid
  var defaultSortAscending: Bool = false
  var defaultGridItemSize: CGFloat = 120
  var gridSpacing: CGFloat = 2
  var gridMagnificationSensitivity: CGFloat = 0.3
}

@Observable
private final class ImageCollectionViewModel<Item: Identifiable> where Item.ID: Hashable {
  var gridItemSize: CGFloat = 120
  var gridSpacing: CGFloat = 2

  var searchText = ""
  var selectedSortOption: ImageCollectionSortOption<Item>?
  var sortAscending: Bool = false
  var viewMode: ImageCollectionViewMode = .grid

  var itemStates: [Item.ID: ImageCollectionItemState] = [:]

  @ObservationIgnored var searchableText: ((Item) -> String)?

  func update(from configuration: ImageCollectionConfiguration<Item>) {
    selectedSortOption = configuration.defaultSortOption
    viewMode = configuration.defaultViewMode
    sortAscending = configuration.defaultSortAscending
    gridItemSize = configuration.defaultGridItemSize
    gridSpacing = configuration.gridSpacing
    searchableText = configuration.searchableText
  }

  func visibleItems(from items: [Item]) -> [Item] {
    let filteredItems = if let searchableText, !searchText.isEmpty {
      items.filter {
        searchableText($0).localizedStandardContains(searchText)
      }
    } else {
      items
    }

    guard let selectedSortOption else {
      return filteredItems
    }

    if let sortValue = selectedSortOption.sortValue {
      return filteredItems
        .map { item in
          (
            item: item,
            sortValue: sortValue(item),
            tieBreaker: String(describing: item.id),
          )
        }
        .sorted { first, second in
          let result = compareSortValues(first.sortValue, second.sortValue)
          if result == .orderedSame {
            return first.tieBreaker.localizedCompare(second.tieBreaker) == .orderedAscending
          }

          return sortAscending ? result == .orderedAscending : result == .orderedDescending
        }
        .map(\.item)
    }

    return filteredItems
      .map { item in
        (
          item: item,
          tieBreaker: String(describing: item.id),
        )
      }
      .sorted { first, second in
        let result = selectedSortOption.compare(first.item, second.item)
        if result == .orderedSame {
          return first.tieBreaker.localizedCompare(second.tieBreaker) == .orderedAscending
        }

        return sortAscending ? result == .orderedAscending : result == .orderedDescending
      }
      .map(\.item)
  }

  private func compareSortValues(
    _ first: ImageCollectionSortValue?,
    _ second: ImageCollectionSortValue?,
  ) -> ComparisonResult {
    switch (first, second) {
    case let (first?, second?):
      first.compare(to: second)
    case (nil, nil):
      .orderedSame
    case (nil, _):
      .orderedAscending
    case (_, nil):
      .orderedDescending
    }
  }

  func state(for item: Item) -> ImageCollectionItemState {
    if let state = itemStates[item.id] {
      return state
    } else {
      let newState = ImageCollectionItemState()
      itemStates[item.id] = newState
      return newState
    }
  }

  func pruneItemStates(from itemIDs: [Item.ID]) {
    let validIDs = Set(itemIDs)
    itemStates = itemStates.filter { validIDs.contains($0.key) }
  }
}

// MARK: - ImageCollectionView

struct ImageCollectionView<
  Item: Identifiable,
  ListRowContent: View,
  GridItemContent: View,
  ContextMenuContent: View,
>: View where Item.ID: Hashable {
  private let items: [Item]
  private var configuration: ImageCollectionConfiguration<Item>
  private let listRow: (Item, ImageCollectionItemState) -> ListRowContent
  private let gridItem: (Item, ImageCollectionItemState) -> GridItemContent
  private let contextMenu: (Item) -> ContextMenuContent
  private var viewMode: Binding<ImageCollectionViewMode>?
  private var gridItemSize: Binding<CGFloat>?

  @State private var viewModel = ImageCollectionViewModel<Item>()
  @State private var magnifyBaseGridItemSize: CGFloat?

  // UI layout constants
  private let collectionToolBarHeight: CGFloat = 32
  private let collectionToolBarButtonHeight: CGFloat = 26
  private let viewModeAnimation = Animation.spring(response: 0.32, dampingFraction: 0.84)
  private let itemLayoutAnimation = Animation.spring(
    response: 0.34,
    dampingFraction: 0.86,
    blendDuration: 0.05,
  )
  private let gridItemSizeAnimation = Animation.interactiveSpring(
    response: 0.22,
    dampingFraction: 0.88,
    blendDuration: 0.08,
  )

  private var itemIDs: [Item.ID] {
    items.map(\.id)
  }

  private var effectiveViewMode: ImageCollectionViewMode {
    viewMode?.wrappedValue ?? viewModel.viewMode
  }

  private var effectiveGridItemSize: CGFloat {
    (gridItemSize?.wrappedValue ?? viewModel.gridItemSize)
      .clamped(to: Constants.recentImagesGridItemSizeRange)
  }

  private var effectiveGridItemSizeBinding: Binding<CGFloat> {
    Binding {
      effectiveGridItemSize
    } set: { newValue in
      let clampedValue = newValue.clamped(to: Constants.recentImagesGridItemSizeRange)
      if let gridItemSize {
        gridItemSize.wrappedValue = clampedValue
      } else {
        viewModel.gridItemSize = clampedValue
      }
    }
  }

  private var effectiveViewModeBinding: Binding<ImageCollectionViewMode> {
    Binding {
      effectiveViewMode
    } set: { newValue in
      guard newValue != effectiveViewMode else { return }

      withAnimation(viewModeAnimation) {
        if let viewMode {
          viewMode.wrappedValue = newValue
        } else {
          viewModel.viewMode = newValue
        }
      }
    }
  }

  private var animatedSearchText: Binding<String> {
    Binding {
      viewModel.searchText
    } set: { newValue in
      guard newValue != viewModel.searchText else { return }

      withAnimation(itemLayoutAnimation) {
        viewModel.searchText = newValue
      }
    }
  }

  private var effectiveGridItem: GridItem {
    GridItem(
      .adaptive(
        minimum: effectiveGridItemSize - 15,
        maximum: effectiveGridItemSize + 15,
      ),
      spacing: viewModel.gridSpacing,
      alignment: .center,
    )
  }

  private var viewModeTransition: AnyTransition {
    .asymmetric(
      insertion: .scale(scale: 0.98, anchor: .top).combined(with: .opacity),
      removal: .scale(scale: 1.01, anchor: .top).combined(with: .opacity),
    )
  }

  private var itemVisibilityTransition: AnyTransition {
    .asymmetric(
      insertion: .scale(scale: 0.96, anchor: .center).combined(with: .opacity),
      removal: .scale(scale: 0.92, anchor: .center).combined(with: .opacity),
    )
  }

  init(
    _ items: [Item],
    configuration: ImageCollectionConfiguration<Item> = .init(),
    @ViewBuilder listRow: @escaping (Item, ImageCollectionItemState) -> ListRowContent,
    @ViewBuilder gridItem: @escaping (Item, ImageCollectionItemState) -> GridItemContent,
    @ViewBuilder contextMenu: @escaping (Item) -> ContextMenuContent,
  ) {
    self.items = items
    self.configuration = configuration
    self.listRow = listRow
    self.gridItem = gridItem
    self.contextMenu = contextMenu
    viewMode = nil
    gridItemSize = nil
  }

  var body: some View {
    let visibleItems = viewModel.visibleItems(from: items)
    let visibleItemIDs = visibleItems.map(\.id)

    ScrollView(.vertical) {
      Group {
        if visibleItems.isEmpty {
          emptyContent
            .transition(itemVisibilityTransition)
        } else {
          collectionContent(
            visibleItems: visibleItems,
            visibleItemIDs: visibleItemIDs,
          )
          .id(effectiveViewMode)
          .transition(viewModeTransition)
        }
      }
      .animation(itemLayoutAnimation, value: visibleItemIDs)
    }
    .animation(viewModeAnimation, value: effectiveViewMode)
    .safeAreaInset(edge: .top, spacing: 0) {
      collectionToolbar(visibleItemCount: visibleItems.count)
    }
    .onAppear {
      viewModel.update(from: configuration)
      viewModel.pruneItemStates(from: itemIDs)
    }
    .onChange(of: itemIDs) { _, _ in
      viewModel.pruneItemStates(from: itemIDs)
    }
  }

  private var emptyContent: some View {
    VStack(spacing: 15) {
      Image(systemName: "photo.on.rectangle.angled")
        .resizable()
        .scaledToFit()
        .foregroundStyle(.secondary)
        .frame(width: 64, height: 64)

      Text(configuration.emptyDescription ?? "No images yet")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .containerRelativeFrame(.vertical, alignment: .center)
  }

  @ViewBuilder
  private func collectionContent(
    visibleItems: [Item],
    visibleItemIDs: [Item.ID],
  ) -> some View {
    switch effectiveViewMode {
    case .list:
      listContent(visibleItems: visibleItems, visibleItemIDs: visibleItemIDs)
    case .grid:
      gridContent(visibleItems: visibleItems, visibleItemIDs: visibleItemIDs)
    }
  }

  private func collectionToolbar(visibleItemCount: Int) -> some View {
    HStack(spacing: 2) {
      titleBlock(visibleItemCount: visibleItemCount)

      Spacer()

      searchField
      sortMenu
      viewModePicker
      clearButton
    }
    .padding(.horizontal, 12)
    .frame(height: collectionToolBarHeight, alignment: .center)
    .background(
      .regularMaterial.opacity(0.9),
    )
  }

  @ViewBuilder
  private func titleBlock(visibleItemCount: Int) -> some View {
    if let title = configuration.title {
      VStack(alignment: .leading, spacing: 0) {
        Text(title)
          .font(.headline)
          .lineLimit(1)
          .truncationMode(.middle)

        Group {
          if configuration.useDefaultSubtitle {
            Text("\(visibleItemCount) image\(visibleItemCount == 1 ? "" : "s")")
          } else if let subtitle = configuration.subtitle {
            Text(subtitle)
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
      }
    }
  }

  @ViewBuilder
  private var searchField: some View {
    if viewModel.searchableText != nil {
      SearchField("Search", text: animatedSearchText)
        .foldable(true)
        .frame(maxWidth: 220, fieldHeight: collectionToolBarButtonHeight)
    }
  }

  @ViewBuilder
  private var sortMenu: some View {
    if let currentSortOption = viewModel.selectedSortOption {
      Menu {
        ForEach(configuration.sortOptions) { sortOption in
          Button {
            setSortOption(sortOption)
          } label: {
            Label(sortOption.title, systemImage: currentSortOption == sortOption ? "checkmark" : "")
          }
        }

        Divider()

        Button {
          setSortAscending(true)
        } label: {
          Label(
            "Ascending",
            systemImage: viewModel.sortAscending ? "checkmark" : "",
          )
        }

        Button {
          setSortAscending(false)
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

  private func setSortOption(_ sortOption: ImageCollectionSortOption<Item>) {
    guard viewModel.selectedSortOption != sortOption else { return }

    withAnimation(itemLayoutAnimation) {
      viewModel.selectedSortOption = sortOption
    }
  }

  private func setSortAscending(_ sortAscending: Bool) {
    guard viewModel.sortAscending != sortAscending else { return }

    withAnimation(itemLayoutAnimation) {
      viewModel.sortAscending = sortAscending
    }
  }

  private var viewModePicker: some View {
    MaterialSegmentedPicker(
      selection: effectiveViewModeBinding,
      items: ImageCollectionViewMode.allCases,
    ) { mode in
      Label(mode.title, systemImage: mode.systemImage)
        .labelStyle(.iconOnly)
        .font(.system(size: 13, weight: .medium))
    }
    .frame(height: collectionToolBarHeight - 4)
  }

  @ViewBuilder
  private var clearButton: some View {
    if let clearHelpText = configuration.clearHelpText, let onClear = configuration.onClear {
      Button {
        withAnimation(itemLayoutAnimation) {
          onClear()
        }
      } label: {
        Label(clearHelpText, systemImage: "trash")
          .labelStyle(.iconOnly)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.secondary)
          .frame(width: collectionToolBarButtonHeight, height: collectionToolBarButtonHeight)
      }
      .buttonStyle(.borderedOnHover)
      .disabled(items.isEmpty)
      .help(clearHelpText)
    }
  }

  private func listContent(
    visibleItems: [Item],
    visibleItemIDs: [Item.ID],
  ) -> some View {
    LazyVStack(spacing: 0) {
      ForEach(visibleItems) { item in
        let itemState = viewModel.state(for: item)
        listRow(item, itemState)
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
          .onHover {
            itemState.isHovered = $0
          }
          .contextMenu {
            contextMenu(item)
          }
          .transition(itemVisibilityTransition)
      }
    }
    .padding(3)
    .animation(itemLayoutAnimation, value: visibleItemIDs)
  }

  private func gridContent(
    visibleItems: [Item],
    visibleItemIDs: [Item.ID],
  ) -> some View {
    LazyVGrid(
      columns: [effectiveGridItem],
      alignment: .center,
      spacing: viewModel.gridSpacing,
    ) {
      ForEach(visibleItems) { item in
        let itemState = viewModel.state(for: item)
        gridItem(item, itemState)
          .aspectRatio(1, contentMode: .fit)
          .contentShape(Rectangle())
          .onHover {
            itemState.isHovered = $0
          }
          .contextMenu {
            contextMenu(item)
          }
          .transition(itemVisibilityTransition)
      }
    }
    .animation(gridItemSizeAnimation, value: effectiveGridItemSize)
    .animation(itemLayoutAnimation, value: visibleItemIDs)
    .simultaneousGesture(
      MagnifyGesture()
        .onChanged { value in
          let baseSize = magnifyBaseGridItemSize ?? effectiveGridItemSize
          magnifyBaseGridItemSize = baseSize
          let adjustedMagnification = 1 + (
            (value.magnification - 1) * configuration.gridMagnificationSensitivity
          )
          effectiveGridItemSizeBinding.wrappedValue = baseSize * adjustedMagnification
        }
        .onEnded { _ in
          magnifyBaseGridItemSize = nil
        },
    )
  }
}

/// A convenience initializer for `ImageCollectionView` that provides a default empty context menu.
extension ImageCollectionView where ContextMenuContent == EmptyView {
  init(
    _ items: [Item],
    configuration: ImageCollectionConfiguration<Item> = .init(),
    @ViewBuilder listRow: @escaping (Item, ImageCollectionItemState) -> ListRowContent,
    @ViewBuilder gridItem: @escaping (Item, ImageCollectionItemState) -> GridItemContent,
  ) {
    self.init(
      items,
      configuration: configuration,
      listRow: listRow,
      gridItem: gridItem,
      contextMenu: { _ in EmptyView() },
    )
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
    default defaultSortOption: ImageCollectionSortOption<Item>? = nil,
  ) -> Self {
    var view = self
    view.configuration.sortOptions = options
    view.configuration.defaultSortOption = defaultSortOption
    return view
  }

  func sortOptions(
    _ options: [ImageCollectionSortOption<Item>],
    default defaultSortOptionID: ImageCollectionSortOption<Item>.ID,
  ) -> Self {
    sortOptions(
      options,
      default: options.first { $0.id == defaultSortOptionID },
    )
  }

  func defaultViewMode(_ mode: ImageCollectionViewMode) -> Self {
    var view = self
    view.configuration.defaultViewMode = mode
    return view
  }

  func viewMode(_ mode: Binding<ImageCollectionViewMode>) -> Self {
    var view = self
    view.viewMode = mode
    return view
  }

  func gridItemLayout(
    size: Binding<CGFloat>? = nil,
    defaultSize: CGFloat? = nil,
    spacing: CGFloat? = nil,
    magnificationSensitivity: CGFloat? = nil,
  ) -> Self {
    var view = self
    view.gridItemSize = size
    if let defaultSize {
      view.configuration.defaultGridItemSize = defaultSize
        .clamped(to: Constants.recentImagesGridItemSizeRange)
    }
    if let spacing {
      view.configuration.gridSpacing = spacing
    }
    if let magnificationSensitivity {
      view.configuration.gridMagnificationSensitivity = magnificationSensitivity
        .clamped(to: 0.05 ... 1.0)
    }
    return view
  }

  func clearAction(_ helpText: String, _ action: @escaping () -> Void) -> Self {
    var view = self
    view.configuration.clearHelpText = helpText
    view.configuration.onClear = action
    return view
  }
}
