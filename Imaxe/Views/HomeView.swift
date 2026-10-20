// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - HomeView

struct HomeView: View {
  @AppStorage("recentImagesViewMode") private var recentImagesViewModeRawValue =
    ImageCollectionViewMode.grid.rawValue
  @AppStorage("recentImagesGridItemSize") private var recentImagesGridItemSize = 120.0

  @Environment(\.dismissWindow) private var dismissWindow
  @Environment(\.openWindow) private var openWindow
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \RecentImage.lastOpenedAt, order: .reverse) private var recentImages: [RecentImage]

  @State private var viewModel = HomeViewModel()

  // UI layout constants
  private let heroHeightRatio: CGFloat = 0.45
  private let recentImageGridItemSizeRange: ClosedRange<CGFloat> = 72 ... 260
  private let recentImageCollectionPadding: CGFloat = 4

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
        .clamped(to: recentImageGridItemSizeRange)
    } set: { newValue in
      recentImagesGridItemSize = Double(
        newValue.clamped(to: recentImageGridItemSizeRange),
      )
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      homeHero
      recentImagesCollection
    }
    .onAppear {
      viewModel.modelContext = modelContext
      viewModel.openWindow = openWindow
      viewModel.dismissWindow = dismissWindow
    }
    .dismissTextFocusOnClickOutside()
    .sheet(item: $viewModel.renameTarget) { item in
      fileRenameSheet(for: item)
    }
    .confirmationDialog(
      "Move to Trash?",
      isPresented: viewModel.isDeleteConfirmationPresented,
      titleVisibility: .visible,
    ) {
      Button("Move to Trash", role: .destructive) {
        viewModel.moveToTrash()
      }

      Button("Cancel", role: .cancel) {
        viewModel.cancelDelete()
      }
    } message: {
      Text(viewModel.deleteTargetURL?.filePath ?? "")
    }
    .alert(viewModel.alertTitle, isPresented: viewModel.isAlertPresented) {
      Button("OK") {}
    } message: {
      Text(viewModel.alertMessage ?? "")
    }
    .fileImporter(
      isPresented: $viewModel.isImporterPresented,
      allowedContentTypes: ImageLoader.supportedImageTypes,
      allowsMultipleSelection: true,
      onCompletion: viewModel.openImportedImages,
    )
    .overlay(
      ContainerRelativeShape()
        .strokeBorder(
          viewModel.isTargetedForDrop ? Color.accentColor : .clear,
          lineWidth: 3,
        ),
    )
    .dropDestination(for: URL.self) { urls, _ in
      viewModel.openImages(at: urls)
      return !urls.isEmpty
    } isTargeted: { isTargeted in
      viewModel.isTargetedForDrop = isTargeted
    }
    .focusedSceneValue(viewModel)
    .focusedSceneValue(\.recentImages, recentImages)
    .task(id: recentImages.map(\.path)) {
      await viewModel.prefetchRecentImages(recentImages)
    }
  }

  private var homeHero: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Drop images here to open")
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
          viewModel.isImporterPresented = true
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
      length * heroHeightRatio
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
    configuration.onClear = viewModel.clearRecentImages
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
    .viewMode(recentImagesViewMode)
    .gridItemLayout(size: recentImagesGridItemSizeBinding, sizeRange: recentImageGridItemSizeRange)
    .background(.controlBackground.opacity(0.5))
    .clipShape(ContainerRelativeShape())
    .overlay(
      ContainerRelativeShape()
        .strokeBorder(Color.separator, lineWidth: 0.5),
    )
    .padding([.horizontal, .bottom], recentImageCollectionPadding)
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
      viewModel.openRecentImage(item)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text(item.fileName))
    .accessibilityHint(Text("Open image"))
    .accessibilityAction {
      viewModel.openRecentImage(item)
    }
  }

  private func recentImageGridItem(
    _ item: RecentImage,
    state: ImageCollectionItemState,
  ) -> some View {
    Button {
      viewModel.openRecentImage(item)
    } label: {
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
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(item.fileName))
    .accessibilityHint(Text("Open image"))
    .help(item.path)
  }

  @ViewBuilder
  private func recentImageActionsMenu(_ item: RecentImage) -> some View {
    Button("Open", systemImage: "photo") {
      viewModel.openRecentImage(item)
    }

    Button("Rename", systemImage: "pencil") {
      viewModel.beginRename(item)
    }

    Button("Move to Trash", systemImage: "trash", role: .destructive) {
      viewModel.confirmDelete(item.url)
    }

    Divider()

    Button("Remove from Recents", systemImage: "minus.circle") {
      viewModel.remove(path: item.path)
    }

    Button("Reveal in Finder", systemImage: "folder") {
      NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
  }

  private func fileRenameSheet(for item: RecentImage) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Rename")
        .font(.headline)

      TextField("Name", text: $viewModel.renameText)
        .textFieldStyle(.roundedBorder)
        .frame(width: 320)

      HStack {
        Spacer()

        Button("Cancel") {
          viewModel.cancelRename()
        }
        .keyboardShortcut(.cancelAction)

        Button("Rename") {
          viewModel.rename(item.url)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(viewModel.trimmedRenameText.isEmpty)
      }
    }
    .padding(20)
    .frame(width: 380)
  }
}

// MARK: - HomeViewModel

@Observable
final class HomeViewModel {
  var deleteTargetURL: URL?
  var isImporterPresented = false
  var isTargetedForDrop = false
  var renameTarget: RecentImage?
  var renameText = ""
  var alertTitle: LocalizedStringResource = ""
  var alertMessage: String?

  @ObservationIgnored var modelContext: ModelContext?
  @ObservationIgnored var openWindow: OpenWindowAction?
  @ObservationIgnored var dismissWindow: DismissWindowAction?

  var isDeleteConfirmationPresented: Binding<Bool> {
    Binding {
      self.deleteTargetURL != nil
    } set: { isPresented in
      if !isPresented {
        self.deleteTargetURL = nil
      }
    }
  }

  var isAlertPresented: Binding<Bool> {
    Binding {
      self.alertMessage != nil
    } set: { isPresented in
      if !isPresented {
        self.alertTitle = ""
        self.alertMessage = nil
      }
    }
  }

  var trimmedRenameText: String {
    renameText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func openRecentImage(_ item: RecentImage) {
    openWindow?(
      id: "image",
      value: ImageWindowRequest(url: item.url, recentImagePath: item.path),
    )
    dismissWindow?(id: "home")
  }

  func openImportedImages(_ result: Result<[URL], Error>) {
    switch result {
    case let .success(urls):
      openImages(at: urls)
    case let .failure(error):
      alertTitle = "Failed to Open Images"
      alertMessage = error.localizedDescription
    }
  }

  func openImages(at urls: [URL]) {
    guard !urls.isEmpty else { return }

    for url in urls {
      openWindow?(id: "image", value: ImageWindowRequest(url: url))
    }
    DispatchQueue.main.async {
      self.dismissWindow?(id: "home")
    }
  }

  func remove(path: String) {
    do {
      if let modelContext {
        try RecentImagesStore.remove(path: path, in: modelContext)
      }
    } catch {
      alertTitle = "Failed to Remove Item"
      alertMessage = error.localizedDescription
    }
  }

  func confirmDelete(_ url: URL) {
    deleteTargetURL = url
  }

  func moveToTrash() {
    defer { cancelDelete() }

    do {
      if let url = deleteTargetURL {
        var trashedURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
        if let modelContext {
          try RecentImagesStore.remove(path: url.filePath, in: modelContext)
        }
      }
    } catch {
      alertTitle = "Failed to Move Item to Trash"
      alertMessage = error.localizedDescription
    }
  }

  func cancelDelete() {
    deleteTargetURL = nil
  }

  func beginRename(_ item: RecentImage) {
    renameText = item.url.lastPathComponent
    renameTarget = item
  }

  func rename(_ url: URL) {
    defer { cancelRename() }

    guard !trimmedRenameText.isEmpty, trimmedRenameText != url.lastPathComponent else { return }

    let newURL: URL
    do {
      newURL = try ImageSession.renameFile(at: url, to: trimmedRenameText)
    } catch {
      alertTitle = "Failed to Rename Item"
      alertMessage = error.localizedDescription
      return
    }

    Task {
      do {
        if let modelContext {
          try await RecentImagesStore.updateLocation(
            from: url.filePath,
            to: newURL,
            in: modelContext,
          )
        }
      } catch {
        alertTitle = "Failed to Update Recent Images"
        alertMessage = error.localizedDescription
      }
    }
  }

  func cancelRename() {
    renameTarget = nil
  }

  func clearRecentImages() {
    do {
      if let modelContext {
        try RecentImagesStore.clear(in: modelContext)
      }
    } catch {
      alertTitle = "Failed to Clear Recent Images"
      alertMessage = error.localizedDescription
    }
  }

  func openImageFromPasteboard() {
    do {
      guard let image = try extractImageFromPasteboard() else { return }
      openWindow?(
        id: "image",
        value: ImageWindowRequest(
          url: image.url,
          addsToRecent: false,
          temporaryURL: image.temporaryURL,
        ),
      )
      dismissWindow?(id: "home")
    } catch {
      alertTitle = "Failed to Load Image from Pasteboard"
      alertMessage = error.localizedDescription
    }
  }

  func prefetchRecentImages(_ recentImages: [RecentImage]) async {
    var didChange = false

    for recentImage in recentImages {
      guard !Task.isCancelled else { return }

      let path = recentImage.path
      let url = recentImage.url
      let existingThumbnailCacheKey = recentImage.thumbnailCacheKey
      async let fileSnapshot = Self.loadFileSnapshot(for: url)
      async let thumbnailCacheKey = ImageThumbnailCache.thumbnailKey(
        for: url,
        preferredKey: existingThumbnailCacheKey,
      )
      let (snapshot, key) = await (fileSnapshot, thumbnailCacheKey)

      guard !Task.isCancelled else { return }
      guard recentImage.path == path else { continue }
      didChange = recentImage.updatePrefetchedValues(
        fileSnapshot: snapshot,
        thumbnailCacheKey: key,
      ) || didChange
    }

    guard didChange, let modelContext else { return }
    do {
      try modelContext.save()
    } catch {
      alertTitle = "Failed to Update Recent Images"
      alertMessage = error.localizedDescription
    }
  }

  private static func loadFileSnapshot(for url: URL) async -> FileSnapshot? {
    let task = Task.detached(priority: .utility) {
      FileSnapshot(url: url)
    }
    return await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
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

#Preview {
  HomeView()
    .modelContainer(for: [RecentImage.self], inMemory: true)
}
