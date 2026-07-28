// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import AppKit
import SwiftUI

// MARK: - TopBar

struct TopBar: View {
  struct PopoverState: Equatable {
    var isFileEditorPresented: Bool = false
    var isImageInfoPresented: Bool = false
    var isZoomPickerPresented: Bool = false

    var isAnyPopoverPresented: Bool {
      isFileEditorPresented
        || isImageInfoPresented
        || isZoomPickerPresented
    }
  }

  @Bindable var imageSession: ImageSession
  @Binding var isPopoverPresented: Bool

  @State private var popoverState = PopoverState()
  @State private var newFileName: String = ""
  @State private var customZoomScaleText = ""

  // UI layout constants
  private let standardWindowButtonReservedWidth: CGFloat = 72
  private let topBarHeight: CGFloat = 32
  private let itemSpacing: CGFloat = 6
  private let buttonWidth: CGFloat = 24
  private let buttonHeight: CGFloat = 24
  private let zoomButtonWidth: CGFloat = 48
  private let positionLabelMinWidth: CGFloat = 48
  private let positionLabelMaxWidth: CGFloat = 80
  private let controlGroupSpacing: CGFloat = 1
  private let controlGroupPadding: CGFloat = 1
  private let fileNameLabelMinWidth: CGFloat = 120

  private var displayedMetadata: ImageMetadata? {
    imageSession.currentMetadata
  }

  var body: some View {
    HStack(spacing: itemSpacing) {
      Color.clear
        .frame(width: standardWindowButtonReservedWidth)
        .accessibilityHidden(true)

      fileNameLabel

      Spacer(minLength: 0)

      topBarControls
    }
    .padding(.leading, 6)
    .padding(.trailing, 12)
    .frame(maxWidth: .infinity, alignment: .center)
    .frame(height: topBarHeight)
    .background {
      Rectangle()
        .fill(.ultraThinMaterial)
    }
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(.separator.opacity(0.28))
        .frame(height: 1)
    }
    .onChange(of: popoverState) { _, newValue in
      isPopoverPresented = newValue.isAnyPopoverPresented
    }
  }

  private var fileNameLabel: some View {
    Button {
      newFileName = displayedMetadata?.fileName ?? ""
      popoverState.isFileEditorPresented.toggle()
    } label: {
      let baseText = Text(displayedMetadata?.fileName ?? "")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(height: buttonHeight)
        .padding(.horizontal, 8)
        .layoutPriority(-1)

      return ViewThatFits(in: .horizontal) {
        baseText
          .fixedSize(horizontal: true, vertical: false)

        baseText
          .frame(minWidth: fileNameLabelMinWidth, alignment: .leading)
      }
    }
    .buttonStyle(.borderedOnHover(isActive: popoverState.isFileEditorPresented))
    .popover(isPresented: $popoverState.isFileEditorPresented, arrowEdge: .bottom) {
      FileEditorPopover(
        imageSession: imageSession,
        fileName: $newFileName,
        onApplyFileName: {
          guard imageSession.renameCurrentImage(to: newFileName) else { return }
          popoverState.isFileEditorPresented = false
        },
      )
    }
    .disabled(imageSession.currentDocument == nil || imageSession.isLoading)
    .help(Text(displayedMetadata?.fileName ?? ""))
    .accessibilityLabel(Text("File name \(displayedMetadata?.fileName ?? "")"))
  }

  private var topBarControls: some View {
    AdaptiveToolbar(spacing: itemSpacing) {
      navigationButtons

      fitToWindowButton

      zoomControls
        .adaptiveToolbarBehavior(.alwaysVisible)

      fitWindowToImageButton

      imageInfoButton
        .adaptiveToolbarBehavior(.alwaysVisible)

      pinWindowButton
    } moreLabel: {
      Label("More", systemImage: "chevron.right.2")
        .frame(width: buttonWidth, height: buttonHeight)
    }
    .overflowFrom(.right)
    .labelMode(.iconOnly)
    .layoutPriority(1)
  }

  private var navigationButtons: some View {
    AdaptiveToolbarItem {
      HStack(spacing: controlGroupSpacing) {
        Button(action: imageSession.navigateToPreviousImage) {
          topBarIconLabel("Previous Image", systemImage: "chevron.left")
        }
        .buttonStyle(.borderedOnHover)
        .disabled(!(imageSession.folderNavigator?.canNavigateToPrevious ?? false))
        .help(Text("Previous image"))

        Text(imageSession.folderNavigator?.positionDescription ?? "1/1")
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .frame(minWidth: positionLabelMinWidth, maxWidth: positionLabelMaxWidth)
          .frame(height: buttonHeight)
          .accessibilityLabel(
            Text("Image position \(imageSession.folderNavigator?.positionDescription ?? "1/1")"),
          )

        Button(action: imageSession.navigateToNextImage) {
          topBarIconLabel("Next Image", systemImage: "chevron.right")
        }
        .buttonStyle(.borderedOnHover)
        .disabled(!(imageSession.folderNavigator?.canNavigateToNext ?? false))
        .help(Text("Next image"))
      }
      .topBarControlGroup(buttonHeight: buttonHeight, padding: controlGroupPadding)
    } overflow: {
      Menu("Navigation", systemImage: "photo.on.rectangle") {
        Button(
          "Previous Image",
          systemImage: "chevron.left",
          action: imageSession.navigateToPreviousImage,
        )
        .disabled(!(imageSession.folderNavigator?.canNavigateToPrevious ?? false))
        .help(Text("Previous image"))

        Text(imageSession.folderNavigator?.positionDescription ?? "1/1")

        Button(
          "Next Image",
          systemImage: "chevron.right",
          action: imageSession.navigateToNextImage,
        )
        .disabled(!(imageSession.folderNavigator?.canNavigateToNext ?? false))
        .help(Text("Next image"))
      }
    }
  }

  private var fitToWindowButton: some View {
    AdaptiveToolbarItem {
      Button(action: imageSession.fitToWindow) {
        topBarIconLabel(
          "Fit to Window",
          systemImage: "arrow.up.left.and.arrow.down.right.rectangle",
        )
      }
      .buttonStyle(.borderedOnHover)
      .disabled(imageSession.isLoading)
      .help(Text("Fit the image to the window"))
    } overflow: {
      Button(
        "Fit to Window",
        systemImage: "arrow.up.left.and.arrow.down.right.rectangle",
        action: imageSession.fitToWindow,
      )
      .disabled(imageSession.isLoading)
      .help(Text("Fit the image to the window"))
    }
  }

  private var zoomControls: some View {
    HStack(spacing: controlGroupSpacing) {
      Button(action: imageSession.zoomOut) {
        topBarIconLabel("Zoom Out", systemImage: "minus.magnifyingglass")
      }
      .buttonStyle(.borderedOnHover)
      .disabled(imageSession.isLoading || imageSession.zoomScale <= Constants.imageZoomScaleRange
        .lowerBound)
      .help(Text("Zoom out"))

      Button {
        customZoomScaleText = zoomInputText(for: imageSession.zoomScale)
        popoverState.isZoomPickerPresented.toggle()
      } label: {
        Text(zoomDescription(for: imageSession.zoomScale))
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .monospacedDigit()
          .lineLimit(1)
          .frame(width: zoomButtonWidth, height: buttonHeight)
      }
      .popover(isPresented: $popoverState.isZoomPickerPresented, arrowEdge: .bottom) {
        ZoomScalePickerPopover(
          currentZoomScale: imageSession.zoomScale,
          customZoomScaleText: $customZoomScaleText,
          onSelectZoomScale: { zoomScale in
            imageSession.setZoomScale(zoomScale)
            customZoomScaleText = zoomInputText(for: zoomScale)
            popoverState.isZoomPickerPresented = false
          },
          onApplyCustomZoomScale: applyCustomZoom,
        )
      }
      .buttonStyle(.borderedOnHover(isActive: popoverState.isZoomPickerPresented))
      .disabled(imageSession.isLoading)
      .help(Text("Choose zoom level"))

      Button(action: imageSession.zoomIn) {
        topBarIconLabel("Zoom In", systemImage: "plus.magnifyingglass")
      }
      .buttonStyle(.borderedOnHover)
      .disabled(imageSession.isLoading || imageSession.zoomScale >= Constants.imageZoomScaleRange
        .upperBound)
      .help(Text("Zoom in"))
    }
    .topBarControlGroup(buttonHeight: buttonHeight, padding: controlGroupPadding)
  }

  private var fitWindowToImageButton: some View {
    AdaptiveToolbarItem {
      Button(action: imageSession.fitWindowToImage) {
        topBarIconLabel(
          "Fit Window to Image",
          systemImage: "rectangle.and.arrow.up.right.and.arrow.down.left",
        )
      }
      .buttonStyle(.borderedOnHover)
      .disabled(imageSession.isLoading)
      .help(Text("Resize the window to fit the image"))
    } overflow: {
      Button(
        "Fit Window to Image",
        systemImage: "rectangle.and.arrow.up.right.and.arrow.down.left",
        action: imageSession.fitWindowToImage,
      )
      .disabled(imageSession.isLoading)
      .help(Text("Resize the window to fit the image"))
    }
  }

  private var imageInfoButton: some View {
    Button {
      popoverState.isImageInfoPresented.toggle()
    } label: {
      topBarIconLabel("Image Info", systemImage: "info.circle")
    }
    .popover(isPresented: $popoverState.isImageInfoPresented, arrowEdge: .bottom) {
      if let currentMetadata = imageSession.currentMetadata {
        ImageInfoPanel(metadata: currentMetadata)
      }
    }
    .buttonStyle(.borderedOnHover(isActive: popoverState.isImageInfoPresented))
    .disabled(imageSession.currentMetadata == nil)
    .help(Text("Show image info"))
  }

  private var pinWindowButton: some View {
    AdaptiveToolbarItem {
      Button(action: imageSession.toggleWindowPinning) {
        topBarIconLabel(
          imageSession.isWindowPinned ? "Unpin Window" : "Pin Window",
          systemImage: imageSession.isWindowPinned ? "pin.slash" : "pin",
        )
      }
      .buttonStyle(.borderedOnHover)
      .help(Text("Toggle window pinning"))
    } overflow: {
      Button(
        imageSession.isWindowPinned ? "Unpin Window" : "Pin Window",
        systemImage: imageSession.isWindowPinned ? "pin.slash" : "pin",
        action: imageSession.toggleWindowPinning,
      )
      .help(Text("Toggle window pinning"))
    }
  }

  private func topBarIconLabel(_ title: LocalizedStringResource, systemImage: String) -> some View {
    Label(title, systemImage: systemImage)
      .padding(.horizontal, 5)
      .frame(minWidth: buttonWidth, idealHeight: buttonHeight)
      .fixedSize()
  }

  private func applyCustomZoom() {
    guard let zoomScale = zoomScaleValue(from: customZoomScaleText) else { return }

    imageSession.setZoomScale(zoomScale)
    customZoomScaleText = zoomInputText(for: zoomScale)
    popoverState.isZoomPickerPresented = false
  }
}

// MARK: - FileEditorPopover

private struct FileEditorPopover: View {
  private struct FileTagOption: Identifiable {
    let id: Int
    let name: String
    let color: Color

    var menuIcon: Image {
      let size = NSSize(width: 12, height: 12)
      let image = NSImage(size: size, flipped: false) { _ in
        NSColor(color).setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        return true
      }
      image.isTemplate = false
      return Image(nsImage: image)
    }

    static var systemOptions: [FileTagOption] {
      let names = NSWorkspace.shared.fileLabels
      let colors: [Color] = [
        .clear,
        .gray,
        .green,
        .purple,
        .blue,
        .yellow,
        .red,
        .orange,
      ]

      return [6, 7, 3, 2, 5, 4, 1].compactMap { index in
        guard names.indices.contains(index), colors.indices.contains(index) else { return nil }
        return FileTagOption(id: index, name: names[index], color: colors[index])
      }
    }
  }

  @Bindable var imageSession: ImageSession
  @Binding var fileName: String
  let onApplyFileName: () -> Void

  @FocusState private var isFileNameFocused: Bool
  @State private var selectedTagNames: Set<String> = []
  @State private var locationURL: URL?

  private let tagOptions = FileTagOption.systemOptions

  // UI layout constants
  private let controlWidth: CGFloat = 300
  private let controlHeight: CGFloat = 24
  private let controlBorderRadius: CGFloat = 6
  private let actionButtonSize: CGFloat = 22

  private var trimmedFileName: String {
    fileName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var hasFileNameChanged: Bool {
    guard let currentFileName = imageSession.currentMetadata?.fileName else { return false }
    return trimmedFileName != currentFileName
  }

  private var selectedTagOptions: [FileTagOption] {
    tagOptions.filter { selectedTagNames.contains($0.name) }
  }

  private var selectedColorTagNames: Set<String> {
    Set(selectedTagOptions.map(\.name))
  }

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 10) {
      GridRow {
        rowLabel("Name:")

        HStack(spacing: 4) {
          TextField("File Name", text: $fileName)
            .textFieldStyle(.roundedBorder)
            .focused($isFileNameFocused)
            .onSubmit(onApplyFileName)

          if hasFileNameChanged {
            Button(action: onApplyFileName) {
              Image(systemName: "return")
                .frame(width: actionButtonSize, height: actionButtonSize)
            }
            .buttonStyle(.borderedOnHover)
            .disabled(trimmedFileName.isEmpty)
            .help("Rename")
            .accessibilityLabel("Rename")
          }
        }
        .frame(width: controlWidth)
      }

      GridRow {
        rowLabel("Tags:")

        HStack(spacing: 4) {
          fileTagPicker

          if !selectedColorTagNames.isEmpty {
            Button(action: clearColorTags) {
              Image(systemName: "xmark.circle.fill")
                .frame(width: actionButtonSize, height: actionButtonSize)
            }
            .buttonStyle(.borderedOnHover)
            .help("Clear Color Tags")
            .accessibilityLabel("Clear Color Tags")
          }
        }
        .frame(width: controlWidth)
      }

      GridRow {
        rowLabel("Location:")

        FileLocationPicker(directoryURL: locationURL, onSelectDirectory: selectDirectory)
          .cornerRadius(controlBorderRadius)
          .frame(width: controlWidth)
      }
    }
    .padding()
    .onAppear {
      synchronizeWithCurrentImage()
      DispatchQueue.main.async {
        isFileNameFocused = true
      }
    }
    .onChange(of: imageSession.displayedURL) {
      synchronizeWithCurrentImage()
    }
  }

  private var fileTagPicker: some View {
    Menu {
      ForEach(tagOptions) { option in
        Toggle(isOn: tagSelection(for: option)) {
          Label { Text(option.name) } icon: { option.menuIcon }
        }
      }
    } label: {
      HStack(spacing: 4) {
        ForEach(selectedTagOptions) { option in
          option.menuIcon
        }

        if selectedTagOptions.isEmpty {
          Text("Empty")
            .font(.system(size: 13, weight: .regular, design: .rounded))
            .foregroundStyle(.controlText)
        }

        Spacer(minLength: 0)

        Image(systemName: "chevron.up.chevron.down")
          .font(.system(size: 10, weight: .bold, design: .rounded))
          .foregroundStyle(.controlText.opacity(0.83))
      }
      .padding(.leading, 8)
      .padding(.trailing, 6)
      .frame(maxWidth: .infinity)
      .frame(height: controlHeight)
      .background(.controlBackground)
      .clipShape(RoundedRectangle(cornerRadius: controlBorderRadius))
      .overlay {
        RoundedRectangle(cornerRadius: controlBorderRadius)
          .stroke(.separator.opacity(0.45), lineWidth: 0.5)
      }
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .accessibilityLabel("File Tags")
    .accessibilityValue(selectedTagOptions.map(\.name).joined(separator: ", "))
  }

  private func rowLabel(_ title: LocalizedStringResource) -> some View {
    Text(title)
      .font(.system(size: 12, weight: .medium, design: .rounded))
      .foregroundStyle(.secondary)
      .gridCellAnchor(.trailing)
  }

  private func tagSelection(for option: FileTagOption) -> Binding<Bool> {
    Binding {
      selectedTagNames.contains(option.name)
    } set: { isSelected in
      var updatedTagNames = selectedTagNames
      if isSelected {
        updatedTagNames.insert(option.name)
      } else {
        updatedTagNames.remove(option.name)
      }

      if imageSession.setCurrentImageTagNames(updatedTagNames) {
        selectedTagNames = updatedTagNames
      }
    }
  }

  private func clearColorTags() {
    let updatedTagNames = selectedTagNames.subtracting(selectedColorTagNames)
    if imageSession.setCurrentImageTagNames(updatedTagNames) {
      selectedTagNames = updatedTagNames
    }
  }

  private func selectDirectory(_ directoryURL: URL) {
    guard imageSession.moveCurrentImage(to: directoryURL) else { return }
    locationURL = imageSession.displayedURL?.deletingLastPathComponent()
  }

  private func synchronizeWithCurrentImage() {
    fileName = imageSession.currentMetadata?.fileName ?? ""
    selectedTagNames = imageSession.currentImageTagNames()
    locationURL = imageSession.displayedURL?.deletingLastPathComponent()
  }
}

// MARK: - ZoomScalePicker

private struct ZoomScalePickerPopover: View {
  let currentZoomScale: CGFloat
  @Binding var customZoomScaleText: String
  let onSelectZoomScale: (CGFloat) -> Void
  let onApplyCustomZoomScale: () -> Void

  private let commonZoomLevels: [CGFloat] = [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0]

  var isCustomZoomScaleValid: Bool {
    zoomScaleValue(from: customZoomScaleText) != nil
  }

  private let columns = [
    GridItem(.adaptive(minimum: 58), spacing: 6),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Zoom")
        .font(.headline)

      LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
        ForEach(commonZoomLevels, id: \.self) { zoomScale in
          zoomPresetButton(for: zoomScale)
        }
      }

      Divider()

      HStack(spacing: 5) {
        TextField("100", text: $customZoomScaleText)
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .monospacedDigit()
          .textFieldStyle(.roundedBorder)
          .frame(width: 48)
          .onSubmit(onApplyCustomZoomScale)

        Text("%")
          .foregroundStyle(.secondary)

        Spacer(minLength: 0)

        Button("Apply", action: onApplyCustomZoomScale)
          .buttonStyle(.bordered)
          .disabled(!isCustomZoomScaleValid)
      }
    }
    .padding(14)
    .frame(width: 162)
  }

  private func zoomPresetButton(for zoomScale: CGFloat) -> some View {
    let isSelected = abs(currentZoomScale - zoomScale) < 0.001

    return Button {
      onSelectZoomScale(zoomScale)
    } label: {
      Text(zoomDescription(for: zoomScale))
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.14) : .controlBackground)
        }
        .overlay {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(
              isSelected ? Color.accentColor.opacity(0.38) : .separator.opacity(0.3),
              lineWidth: 0.5,
            )
        }
    }
    .buttonStyle(.plain)
  }
}

// MARK: - ImageInfoPanel

private struct ImageInfoPanel: View {
  let metadata: ImageMetadata

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Info")
        .font(.headline)

      VStack(alignment: .leading, spacing: 8) {
        infoRow(title: "File Name", value: metadata.fileName)
        infoRow(title: "Location", value: metadata.location)
        infoRow(title: "Format", value: metadata.typeDescription)
        infoRow(title: "File Size", value: fileSizeDescription(for: metadata.fileSize))

        Divider()

        infoRow(title: "Pixel Width", value: String(metadata.displayPixelSize.width))
        infoRow(title: "Pixel Height", value: String(metadata.displayPixelSize.height))
        infoRow(title: "Image DPI", value: metadata.DPIDescription)
        infoRow(title: "Bit Depth", value: metadata.bitDepthDescription)
        infoRow(title: "Color Space", value: metadata.colorSpaceDescription)
        infoRow(title: "Has Alpha", value: metadata.alphaDescription)
      }
    }
    .padding(14)
    .frame(width: 360, alignment: .leading)
  }

  private func infoRow(title: String, value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(title)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .frame(maxWidth: 81, alignment: .trailing)

      Text(value)
        .font(.system(size: 12))
        .foregroundStyle(.primary)
        .lineLimit(3)
        .truncationMode(.middle)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

// MARK: - Private Helpers

private extension View {
  func topBarControlGroup(buttonHeight: CGFloat, padding: CGFloat) -> some View {
    fixedSize()
      .padding(padding)
      .frame(height: buttonHeight + padding * 2)
      .background {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(.controlBackground.opacity(0.8))
      }
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(.separator.opacity(0.24), lineWidth: 0.5)
      }
  }
}

private func zoomDescription(for zoomScale: CGFloat) -> String {
  "\(Int((zoomScale * 100).rounded()))%"
}

private func zoomInputText(for zoomScale: CGFloat) -> String {
  "\(Int((zoomScale * 100).rounded()))"
}

private func zoomScaleValue(from input: String) -> CGFloat? {
  let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
  let percentText = trimmedInput.hasSuffix("%") ? String(trimmedInput.dropLast()) : trimmedInput
  guard let percent = Double(percentText), percent.isFinite, percent > 0 else { return nil }

  return CGFloat(percent / 100.0).clamped(to: Constants.imageZoomScaleRange)
}
