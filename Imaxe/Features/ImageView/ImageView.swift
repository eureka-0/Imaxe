//
//  ImageView.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/17.
//

import SwiftUI
import UniformTypeIdentifiers

struct ImageView: View {
  @Bindable var imageSession: ImageSession

  @State private var isTopBarHovering = false
  @State private var isImageInfoPresented = false
  @State private var isZoomPickerPresented = false
  @State private var customZoomScaleText = ""

  @AppStorage(AppSettings.Keys.loadedImageWindowSizeMode.rawValue)
  private var loadedImageWindowSizeMode = AppSettings.Defaults.loadedImageWindowSizeMode

  @AppStorage(AppSettings.Keys.fixedLoadedImageWindowWidth.rawValue)
  private var fixedLoadedImageWindowWidth = AppSettings.Defaults.fixedLoadedImageWindowWidth

  @AppStorage(AppSettings.Keys.fixedLoadedImageWindowHeight.rawValue)
  private var fixedLoadedImageWindowHeight = AppSettings.Defaults.fixedLoadedImageWindowHeight

  @AppStorage(AppSettings.Keys.fixedLoadedImageWindowSizeUnit.rawValue)
  private var fixedLoadedImageWindowSizeUnit = AppSettings.Defaults.fixedLoadedImageWindowSizeUnit

  private var isPopoverPresented: Bool {
    isImageInfoPresented || isZoomPickerPresented
  }

  private var displayedImageInfo: ImageInfo? {
    imageSession.currentImageInfo
  }

  private var fixedLoadedImageWindowSize: NSSize {
    NSSize(width: fixedLoadedImageWindowWidth, height: fixedLoadedImageWindowHeight)
  }

  var body: some View {
    Group {
      if imageSession.currentImage != nil || imageSession.isLoading {
        ZStack(alignment: .top) {
          imageContent

          topBar
            .opacity(imageSession.showTopBar ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: imageSession.showTopBar)
            .allowsHitTesting(imageSession.showTopBar)

          HoverTrackingStrip { isHovering, window in
            isTopBarHovering = isHovering
            updateTopBarVisibility(in: window)
          }
          .frame(maxWidth: .infinity)
          .frame(height: Constants.topBarHoverStripHeight)
        }
      } else {
        HomeView(imageSession: imageSession, recentImages: [])
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .alert(item: $imageSession.alert) { alert in
      Alert(title: Text(alert.title), message: Text(alert.message))
    }
    .onChange(of: isPopoverPresented) { _, _ in
      updateTopBarVisibility()
    }
    .onChange(of: imageSession.isLoading) { _, _ in
      updateTopBarVisibility()
    }
  }

  @ViewBuilder
  private var imageContent: some View {
    if let image = imageSession.currentImage, let info = imageSession.currentImageInfo {
      ImageScrollView(
        imageContainer: image,
        imageInfo: info,
        viewportController: imageSession.viewportController,
        loadedImageWindowSizeMode: loadedImageWindowSizeMode,
        fixedLoadedImageWindowSize: fixedLoadedImageWindowSize,
        fixedLoadedImageWindowSizeUnit: fixedLoadedImageWindowSizeUnit,
        shouldApplyLoadedImageWindowSize: imageSession.shouldApplyLoadedImageWindowSize,
        zoomScale: $imageSession.zoomScale,
        alwaysFitToWindow: $imageSession.alwaysFitToWindow,
      )
    } else if imageSession.isLoading {
      loadingImageView
    } else {
      HomeView(imageSession: imageSession, recentImages: [])
    }
  }

  private var loadingImageView: some View {
    VStack(spacing: 12) {
      ProgressView()
        .controlSize(.large)

      Text("Loading...")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text("Loading..."))
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
    .background(.regularMaterial.opacity(0.9))
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(.separator.opacity(0.28))
        .frame(height: 1)
    }
    .frame(height: Constants.topBarHeight)
    .controlSize(.small)
  }

  private var fileNameLabel: some View {
    Text(displayedImageInfo?.fileName ?? "")
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(.primary)
      .lineLimit(1)
      .truncationMode(.tail)
      .frame(minWidth: 72, maxWidth: 320, alignment: .leading)
      .help(Text(displayedImageInfo?.fileName ?? ""))
      .accessibilityLabel(Text("File name \(displayedImageInfo?.fileName ?? "")"))
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
      .buttonStyle(.borderedOnHover)
      .disabled(!(imageSession.folderNavigator?.canNavigateToPrevious ?? false))
      .help(Text("Previous image"))

      Text(imageSession.folderNavigator?.positionDescription ?? "1/1")
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(
          minWidth: Constants.topBarPositionMinWidth,
          maxWidth: Constants.topBarPositionMaxWidth,
        )
        .frame(height: Constants.topBarButtonHeight)
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
    .topBarControlGroup()
  }

  private var fitToWindowButton: some View {
    Button(action: imageSession.fitToWindow) {
      topBarIconLabel("Fit to Window", systemImage: "arrow.up.left.and.arrow.down.right.rectangle")
    }
    .buttonStyle(.borderedOnHover)
    .disabled(imageSession.isLoading)
    .help(Text("Fit the image to the window"))
  }

  private var zoomControls: some View {
    HStack(spacing: Constants.topBarControlGroupSpacing) {
      Button(action: imageSession.zoomOut) {
        topBarIconLabel("Zoom Out", systemImage: "minus.magnifyingglass")
      }
      .buttonStyle(.borderedOnHover)
      .disabled(imageSession.isLoading || imageSession.zoomScale <= Constants.imageZoomScaleRange
        .lowerBound)
      .help(Text("Zoom out"))

      Button {
        customZoomScaleText = zoomInputText(for: imageSession.zoomScale)
        isZoomPickerPresented.toggle()
      } label: {
        Text(zoomDescription(for: imageSession.zoomScale))
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .monospacedDigit()
          .lineLimit(1)
          .frame(width: Constants.topBarZoomButtonWidth, height: Constants.topBarButtonHeight)
      }
      .popover(isPresented: $isZoomPickerPresented, arrowEdge: .top) {
        ZoomScalePickerPopover(
          currentZoomScale: imageSession.zoomScale,
          customZoomScaleText: $customZoomScaleText,
          onSelectZoomScale: { zoomScale in
            imageSession.setZoomScale(zoomScale)
            customZoomScaleText = zoomInputText(for: zoomScale)
            isZoomPickerPresented = false
          },
          onApplyCustomZoomScale: applyCustomZoom,
        )
      }
      .buttonStyle(.borderedOnHover(isActive: isZoomPickerPresented))
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
    .topBarControlGroup()
  }

  private var fitWindowToImageButton: some View {
    Button(action: imageSession.fitWindowToImage) {
      topBarIconLabel(
        "Fit Window to Image",
        systemImage: "rectangle.and.arrow.up.right.and.arrow.down.left",
      )
    }
    .buttonStyle(.borderedOnHover)
    .disabled(imageSession.isLoading)
    .help(Text("Resize the window to fit the image"))
  }

  private var imageInfoButton: some View {
    Button {
      isImageInfoPresented.toggle()
    } label: {
      topBarIconLabel("Image Info", systemImage: "info.circle")
    }
    .popover(isPresented: $isImageInfoPresented, arrowEdge: .top) {
      if let currentImageInfo = imageSession.currentImageInfo {
        ImageInfoPanel(info: currentImageInfo)
      }
    }
    .buttonStyle(.borderedOnHover(isActive: isImageInfoPresented))
    .disabled(imageSession.currentImageInfo == nil)
    .help(Text("Show image info"))
  }

  private var pinWindowButton: some View {
    Button(action: imageSession.toggleWindowPinning) {
      topBarIconLabel("Pin Window", systemImage: imageSession.isWindowPinned ? "pin.slash" : "pin")
    }
    .buttonStyle(.borderedOnHover)
    .help(Text("Toggle window pinning"))
  }

  private func topBarIconLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
    Label(title, systemImage: systemImage)
      .labelStyle(.iconOnly)
      .frame(width: Constants.topBarIconButtonWidth, height: Constants.topBarButtonHeight)
  }

  private func applyCustomZoom() {
    guard let zoomScale = zoomScaleValue(from: customZoomScaleText) else { return }

    imageSession.setZoomScale(zoomScale)
    customZoomScaleText = zoomInputText(for: zoomScale)
    isZoomPickerPresented = false
  }

  private func updateTopBarVisibility(in window: NSWindow? = nil) {
    imageSession.setTopBarVisibility(to: isTopBarHovering || isPopoverPresented, in: window)
  }
}

private struct ZoomScalePickerPopover: View {
  let currentZoomScale: CGFloat
  @Binding var customZoomScaleText: String
  let onSelectZoomScale: (CGFloat) -> Void
  let onApplyCustomZoomScale: () -> Void

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
        ForEach(Constants.commonZoomLevels, id: \.self) { zoomScale in
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

private struct ImageInfoPanel: View {
  let info: ImageInfo

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Info")
        .font(.headline)

      VStack(alignment: .leading, spacing: 8) {
        infoRow(title: "File Name", value: info.fileName)
        infoRow(title: "Location", value: info.location)
        infoRow(title: "Format", value: info.typeDescription)
        infoRow(title: "File Size", value: info.fileSizeDescription)

        Divider()

        infoRow(title: "Pixel Width", value: String(info.pixelSize.width))
        infoRow(title: "Pixel Height", value: String(info.pixelSize.height))
        infoRow(title: "Image DPI", value: info.DPIDescription)
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

private extension View {
  func topBarControlGroup() -> some View {
    fixedSize()
      .padding(Constants.topBarControlGroupPadding)
      .frame(height: Constants.topBarButtonHeight + Constants.topBarControlGroupPadding * 2)
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
