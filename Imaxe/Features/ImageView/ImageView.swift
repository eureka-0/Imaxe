//
//  ImageView.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/17.
//

import SwiftUI

struct ImageView: View {
  @Bindable var imageSession: ImageSession
  @State private var isTopBarHovering = false
  @State private var isImageInfoPresented = false
  @State private var isScalePickerPresented = false
  @State private var customScaleText = ""

  private let commonScales: [CGFloat] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0]
  private var isPopoverPresented: Bool {
    isImageInfoPresented || isScalePickerPresented
  }

  var body: some View {
    ZStack(alignment: .top) {
      ImageScrollView(
        loadedImage: imageSession.currentImage,
        fitToWindowRequest: imageSession.fitToWindowRequest,
        fitWindowToImageRequest: imageSession.fitWindowToImageRequest,
        scale: $imageSession.imageScale,
        alwaysFitToWindow: $imageSession.alwaysFitToWindow,
      )

      topBar
        .opacity(imageSession.showTopBar ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: imageSession.showTopBar)
        .allowsHitTesting(imageSession.showTopBar)

      HoverTrackingStrip { isHovering in
        isTopBarHovering = isHovering
        updateTopBarVisibility()
      }
      .frame(maxWidth: .infinity)
      .frame(height: Constants.topBarHoverStripHeight)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      imageSession.setTopBarVisibility(to: false)

      DispatchQueue.main.async {
        imageSession.fitToWindow()
      }
    }
    .alert(item: $imageSession.alert) { alert in
      Alert(title: Text(alert.title), message: Text(alert.message))
    }
    .onChange(of: isPopoverPresented) { _, _ in
      updateTopBarVisibility()
    }
  }

  private var topBar: some View {
    HStack(spacing: Constants.topBarItemSpacing) {
      Color.clear
        .frame(width: Constants.topBarWindowButtonReservedWidth)
        .accessibilityHidden(true)

      fileNameLabel

      Spacer(minLength: Constants.topBarItemSpacing)

      topBarControls
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .padding(.leading, 6)
    .padding(.trailing, 12)
    .background(.regularMaterial.opacity(0.86))
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color(nsColor: .separatorColor).opacity(0.28))
        .frame(height: 1)
    }
    .frame(height: Constants.topBarHeight)
    .buttonStyle(TopBarButtonStyle())
    .controlSize(.small)
  }

  private var topBarControls: some View {
    HStack(spacing: Constants.topBarItemSpacing) {
      navigationButtons
      fitToWindowButton
      zoomControls
      fitWindowToImageButton
      imageInfoButton
      pinWindowButton
    }
    .fixedSize()
    .layoutPriority(1)
  }

  private var navigationButtons: some View {
    HStack(spacing: Constants.topBarControlGroupSpacing) {
      Button(action: imageSession.navigateToPreviousImage) {
        topBarIconLabel("Previous Image", systemImage: "chevron.left")
      }
      .disabled(!imageSession.folderNavigator.canNavigateToPrevious)
      .help(Text("Previous image"))

      Text(imageSession.folderNavigator.positionDescription)
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(width: Constants.topBarPositionWidth, height: Constants.topBarButtonHeight)
        .accessibilityLabel(Text("Image position \(imageSession.folderNavigator.positionDescription)"))

      Button(action: imageSession.navigateToNextImage) {
        topBarIconLabel("Next Image", systemImage: "chevron.right")
      }
      .disabled(!imageSession.folderNavigator.canNavigateToNext)
      .help(Text("Next image"))
    }
    .topBarControlGroup()
  }

  private var fitToWindowButton: some View {
    Button(action: imageSession.fitToWindow) {
      topBarIconLabel("Fit to Window", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
    }
    .keyboardShortcut("f", modifiers: .command)
    .help(Text("Fit the image to the window"))
  }

  private var zoomControls: some View {
    HStack(spacing: Constants.topBarControlGroupSpacing) {
      Button(action: imageSession.zoomOut) {
        topBarIconLabel("Zoom Out", systemImage: "minus.magnifyingglass")
      }
      .disabled(imageSession.imageScale <= Constants.imageScaleRange.lowerBound)
      .help(Text("Zoom out"))

      scaleButton

      Button(action: imageSession.zoomIn) {
        topBarIconLabel("Zoom In", systemImage: "plus.magnifyingglass")
      }
      .disabled(imageSession.imageScale >= Constants.imageScaleRange.upperBound)
      .help(Text("Zoom in"))
    }
    .topBarControlGroup()
  }

  private var scaleButton: some View {
    Button {
      customScaleText = scaleInputText(for: imageSession.imageScale)
      isScalePickerPresented.toggle()
    } label: {
      Text(scaleDescription(for: imageSession.imageScale))
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .frame(width: Constants.topBarScaleButtonWidth, height: Constants.topBarButtonHeight)
    }
    .popover(isPresented: $isScalePickerPresented, arrowEdge: .top) {
      ScalePickerPopover(
        scales: commonScales,
        currentScale: imageSession.imageScale,
        customScaleText: $customScaleText,
        isCustomScaleValid: scaleValue(from: customScaleText) != nil,
        onSelectScale: { scale in
          imageSession.setScale(scale)
          customScaleText = scaleInputText(for: scale)
          isScalePickerPresented = false
        },
        onApplyCustomScale: applyCustomScale,
      )
    }
    .help(Text("Choose image scale"))
  }

  private var fitWindowToImageButton: some View {
    Button(action: imageSession.fitWindowToImage) {
      topBarIconLabel("Fit Window to Image", systemImage: "rectangle.and.arrow.up.right.and.arrow.down.left")
    }
    .help(Text("Resize the window to fit the image"))
  }

  private var imageInfoButton: some View {
    Button {
      isImageInfoPresented.toggle()
    } label: {
      topBarIconLabel("Image Info", systemImage: "info.circle")
    }
    .popover(isPresented: $isImageInfoPresented, arrowEdge: .top) {
      ImageInfoPanel(loadedImage: imageSession.currentImage)
    }
    .help(Text("Show image info"))
  }

  private var pinWindowButton: some View {
    Button(action: imageSession.toggleWindowPinning) {
      topBarIconLabel("Pin Window", systemImage: imageSession.isWindowPinned ? "pin.slash" : "pin")
    }
    .keyboardShortcut("p", modifiers: .command)
    .help(Text("Toggle window pinning"))
  }

  private var fileNameLabel: some View {
    Text(imageSession.currentImage.info.fileName)
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(.primary)
      .lineLimit(1)
      .truncationMode(.tail)
      .frame(minWidth: 72, maxWidth: 320, alignment: .leading)
      .help(Text(imageSession.currentImage.info.fileName))
      .accessibilityLabel(Text("File name \(imageSession.currentImage.info.fileName)"))
  }

  private func topBarIconLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
    Label(title, systemImage: systemImage)
      .labelStyle(.iconOnly)
      .frame(width: Constants.topBarIconButtonWidth, height: Constants.topBarButtonHeight)
  }

  private func applyCustomScale() {
    guard let scale = scaleValue(from: customScaleText) else { return }

    imageSession.setScale(scale)
    customScaleText = scaleInputText(for: scale)
    isScalePickerPresented = false
  }

  private func updateTopBarVisibility() {
    imageSession.setTopBarVisibility(to: isTopBarHovering || isPopoverPresented)
  }
}

private struct TopBarButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    TopBarButton(configuration: configuration)
  }

  private struct TopBarButton: View {
    let configuration: Configuration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
      configuration.label
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(isEnabled ? .primary : .tertiary)
        .background(background)
        .clipShape(.rect(cornerRadius: 7))
        .contentShape(.rect(cornerRadius: 7))
        .opacity(configuration.isPressed ? 0.72 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        .onHover { isHovering in
          self.isHovering = isHovering
        }
    }

    private var background: some ShapeStyle {
      if configuration.isPressed {
        return Color.primary.opacity(0.16)
      }
      if isHovering, isEnabled {
        return Color.primary.opacity(0.10)
      }
      return Color.clear
    }
  }
}

private struct ScalePickerPopover: View {
  let scales: [CGFloat]
  let currentScale: CGFloat
  @Binding var customScaleText: String
  let isCustomScaleValid: Bool
  let onSelectScale: (CGFloat) -> Void
  let onApplyCustomScale: () -> Void

  private let columns = [
    GridItem(.adaptive(minimum: 58), spacing: 6),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Scale")
        .font(.headline)

      LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
        ForEach(scales, id: \.self) { scale in
          scalePresetButton(for: scale)
        }
      }

      Divider()

      HStack(spacing: 8) {
        TextField("100", text: $customScaleText)
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .monospacedDigit()
          .textFieldStyle(.roundedBorder)
          .frame(width: 72)
          .onSubmit(onApplyCustomScale)

        Text("%")
          .foregroundStyle(.secondary)

        Spacer(minLength: 0)

        Button("Apply", action: onApplyCustomScale)
          .buttonStyle(.bordered)
          .disabled(!isCustomScaleValid)
      }
    }
    .padding(14)
    .frame(width: 242)
  }

  private func scalePresetButton(for scale: CGFloat) -> some View {
    let isSelected = abs(currentScale - scale) < 0.005

    return Button {
      onSelectScale(scale)
    } label: {
      Text(scaleDescription(for: scale))
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background {
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .stroke(
              isSelected ? Color.accentColor.opacity(0.38) : Color(nsColor: .separatorColor).opacity(0.3),
              lineWidth: 0.5,
            )
        }
    }
    .buttonStyle(.plain)
  }
}

private struct ImageInfoPanel: View {
  let loadedImage: LoadedImage

  private var info: ImageInfo {
    loadedImage.info
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Image Info")
        .font(.headline)

      VStack(alignment: .leading, spacing: 8) {
        ImageInfoRow(title: "Name", value: info.fileName)
        ImageInfoRow(title: "Kind", value: kindDescription)
        ImageInfoRow(title: "Format", value: formatDescription)
        ImageInfoRow(title: "Dimensions", value: "\(info.pixelWidth) x \(info.pixelHeight) px")
        ImageInfoRow(title: "File Size", value: info.fileSizeDescription)
        ImageInfoRow(title: "Location", value: info.sourceURL.deletingLastPathComponent().path)
      }
    }
    .padding(14)
    .frame(width: 340, alignment: .leading)
  }

  private var kindDescription: String {
    switch loadedImage.kind {
    case .bitmap:
      "Bitmap"
    case .vector:
      "Vector"
    }
  }

  private var formatDescription: String {
    let pathExtension = info.sourceURL.pathExtension
    return pathExtension.isEmpty ? "Unknown" : pathExtension.uppercased()
  }
}

private struct ImageInfoRow: View {
  let title: String
  let value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 72, alignment: .trailing)

      Text(value)
        .font(.caption)
        .foregroundStyle(.primary)
        .lineLimit(2)
        .truncationMode(.middle)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private extension View {
  func topBarControlGroup() -> some View {
    fixedSize()
      .padding(Constants.topBarControlGroupPadding)
      .frame(height: Constants.topBarButtonHeight + Constants.topBarControlGroupPadding * 2)
      .background {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(Color(nsColor: .controlBackgroundColor).opacity(0.42))
      }
      .overlay {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .stroke(Color(nsColor: .separatorColor).opacity(0.24), lineWidth: 0.5)
      }
  }
}

private func scaleDescription(for scale: CGFloat) -> String {
  "\(Int((scale * 100).rounded()))%"
}

private func scaleInputText(for scale: CGFloat) -> String {
  "\(Int((scale * 100).rounded()))"
}

private func scaleValue(from input: String) -> CGFloat? {
  let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
  let percentText = trimmedInput.hasSuffix("%") ? String(trimmedInput.dropLast()) : trimmedInput
  guard let percent = Double(percentText), percent.isFinite, percent > 0 else { return nil }

  return CGFloat(percent / 100.0).clamped(to: Constants.imageScaleRange)
}
