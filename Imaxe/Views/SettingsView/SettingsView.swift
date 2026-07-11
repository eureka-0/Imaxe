//
//  SettingsView.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/23.
//

import SwiftUI

private struct CacheClearError: Identifiable {
  let id = UUID()
  let message: String
}

struct SettingsView: View {
  var body: some View {
    TabView {
      GeneralSettingsView()
        .tabItem { Label("General", systemImage: "gearshape") }

      ImageSettingsView()
        .tabItem { Label("Image", systemImage: "photo.on.rectangle") }
    }
    .lineSpacing(10)
    .scenePadding()
    .frame(width: 620)
  }
}

struct GeneralSettingsView: View {
  @AppStorage(AppSettings.Keys.appearance.rawValue)
  private var appearance = AppSettings.Defaults.appearance

  @AppStorage(AppSettings.Keys.backgroundColor.rawValue)
  private var backgroundColor = AppSettings.Defaults.backgroundColor

  @AppStorage(AppSettings.Keys.topBarHideDelay.rawValue)
  private var topBarHideDelay = AppSettings.Defaults.topBarHideDelay

  @AppStorage(AppSettings.Keys.enableLoopBrowsing.rawValue)
  private var enableLoopBrowsing = AppSettings.Defaults.enableLoopBrowsing

  @AppStorage(AppSettings.Keys.actionOnImageFileChange.rawValue)
  private var actionOnImageFileChange = AppSettings.Defaults.actionOnImageFileChange

  @AppStorage(AppSettings.Keys.recentImagesCountLimit.rawValue)
  private var recentImagesCountLimit = AppSettings.Defaults.recentImagesCountLimit

  @State private var totalCacheSize: Int = ImageThumbnailCache.totalCacheSizeInBytes()
  @State private var cacheClearError: CacheClearError?

  var body: some View {
    Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 20) {
      GridRow {
        Text("Appearance:")

        Picker("", selection: $appearance) {
          ForEach(Appearance.allCases) {
            Text($0.description).tag($0)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .gridCellAnchor(.leading)
      }

      GridRow {
        Text("Background color:")

        HStack(spacing: 5) {
          ColorPicker("", selection: Binding(
            get: { backgroundColor.color },
            set: { newColor in
              backgroundColor = BackgroundColor(rawValue: newColor.hex)
            },
          ))
          .labelsHidden()

          if backgroundColor != AppSettings.Defaults.backgroundColor {
            Button("Reset", systemImage: "arrow.counterclockwise") {
              backgroundColor = AppSettings.Defaults.backgroundColor
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
          }
        }
        .gridCellAnchor(.leading)
      }

      GridRow {
        Text("Top bar hide delay:")

        Picker("", selection: $topBarHideDelay) {
          ForEach([0, 0.5, 1.0, 1.5, 2.0, 3.0, 5.0, 10.0], id: \.self) { delay in
            if delay == 1 {
              Text("\(delay, specifier: "%.1f") second").tag(delay)
            } else {
              Text("\(delay, specifier: "%.1f") seconds").tag(delay)
            }
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .gridCellAnchor(.leading)
      }

      GridRow {
        Text("Browsing:")

        Toggle("Loop browsing", isOn: $enableLoopBrowsing)
          .toggleStyle(.checkbox)
          .gridCellAnchor(.leading)
      }

      GridRow {
        Text("Action on image file change:")

        Picker("", selection: $actionOnImageFileChange) {
          ForEach(ActionOnImageFileChange.allCases) {
            Text($0.description).tag($0)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .gridCellAnchor(.leading)
      }

      GridRow(alignment: .top) {
        Text("Recent images count limit:")

        VStack(alignment: .leading, spacing: 5) {
          Picker("", selection: $recentImagesCountLimit) {
            ForEach([10, 20, 30, 40, 60, 80, 100], id: \.self) { count in
              Text("\(count)").tag(count)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)

          HStack(spacing: 5) {
            Text("Current thumbnail caches: \(fileSizeDescription(for: totalCacheSize))")
              .font(.callout)
              .foregroundStyle(.secondary)

            Button {
              do {
                try ImageThumbnailCache.removeAllThumbnails()
                refreshCacheSize()
              } catch {
                appLog(
                  "Failed to clear thumbnail caches: \(error.localizedDescription)",
                  level: .error,
                  category: .persistence,
                )
                cacheClearError = CacheClearError(message: error.localizedDescription)
              }
            } label: {
              Label("Clear", systemImage: "trash")
                .font(.callout)
                .padding(-2)
            }
            .labelStyle(.titleOnly)
            .buttonStyle(.bordered)
            .disabled(totalCacheSize == 0)
          }
          .frame(width: 275, alignment: .leading)
        }
        .gridCellAnchor(.leading)
      }
    }
    .onAppear {
      refreshCacheSize()
    }
    .onReceive(
      NotificationCenter.default.publisher(for: ImageThumbnailCache.didChangeNotification),
    ) { _ in
      refreshCacheSize()
    }
    .alert(item: $cacheClearError) { error in
      Alert(
        title: Text("Could Not Clear Thumbnail Cache"),
        message: Text(error.message),
      )
    }
  }

  private func refreshCacheSize() {
    totalCacheSize = ImageThumbnailCache.totalCacheSizeInBytes()
  }
}

struct ImageSettingsView: View {
  @AppStorage(AppSettings.Keys.imageActualSizeStrategy.rawValue)
  private var imageActualSizeStrategy = AppSettings.Defaults.imageActualSizeStrategy

  @AppStorage(AppSettings.Keys.loadedImageWindowSizeMode.rawValue)
  private var loadedImageWindowSizeMode = AppSettings.Defaults.loadedImageWindowSizeMode

  @AppStorage(AppSettings.Keys.fixedLoadedImageWindowWidth.rawValue)
  private var fixedLoadedImageWindowWidth = AppSettings.Defaults.fixedLoadedImageWindowWidth

  @AppStorage(AppSettings.Keys.fixedLoadedImageWindowHeight.rawValue)
  private var fixedLoadedImageWindowHeight = AppSettings.Defaults.fixedLoadedImageWindowHeight

  @AppStorage(AppSettings.Keys.fixedLoadedImageWindowSizeUnit.rawValue)
  private var fixedLoadedImageWindowSizeUnit = AppSettings.Defaults.fixedLoadedImageWindowSizeUnit

  @AppStorage(AppSettings.Keys.imageInterpolationStrategy.rawValue)
  private var imageInterpolationStrategy = AppSettings.Defaults.imageInterpolationStrategy

  @FocusState private var widthInputFocused: Bool
  @FocusState private var heightInputFocused: Bool

  var body: some View {
    Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 20) {
      GridRow {
        Text("Define 100% zoom as:")

        Picker("", selection: $imageActualSizeStrategy) {
          ForEach(ImageActualSizeStrategy.allCases) {
            Text($0.description).tag($0)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .gridCellAnchor(.leading)
      }

      GridRow(alignment: .top) {
        Text("Default zoom level:")

        VStack(alignment: .leading, spacing: 5) {
          Picker("", selection: $loadedImageWindowSizeMode) {
            ForEach(LoadedImageWindowSizeMode.allCases) {
              Text($0.description).tag($0)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)

          if loadedImageWindowSizeMode == .fixedSize {
            fixedLoadedImageWindowSizeField
          }
        }
        .gridCellAnchor(.leading)
      }

      GridRow {
        Text("Image interpolation:")

        Picker("", selection: $imageInterpolationStrategy) {
          ForEach(ImageInterpolationStrategy.allCases) {
            Text($0.description).tag($0)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .gridCellAnchor(.leading)
      }
    }
    .background {
      Color.clear
        .contentShape(Rectangle())
        .onTapGesture {
          DispatchQueue.main.async {
            widthInputFocused = false
            heightInputFocused = false
          }
        }
    }
    .onAppear {
      normalizeFixedLoadedImageWindowSize()
      DispatchQueue.main.async {
        widthInputFocused = false
        heightInputFocused = false
      }
    }
    .onDisappear {
      DispatchQueue.main.async {
        widthInputFocused = false
        heightInputFocused = false
      }
    }
  }

  private var fixedLoadedImageWindowSizeField: some View {
    HStack(spacing: 5) {
      Text("Width:")

      TextField(
        "Width",
        value: $fixedLoadedImageWindowWidth,
        format: .number.precision(.fractionLength(0)),
      )
      .focused($widthInputFocused)
      .onSubmit {
        fixedLoadedImageWindowWidth = sanitizedWidth(fixedLoadedImageWindowWidth)
      }
      .onChange(of: widthInputFocused) { _, newValue in
        if !newValue {
          fixedLoadedImageWindowWidth = sanitizedWidth(fixedLoadedImageWindowWidth)
        }
      }
      .labelsHidden()
      .monospacedDigit()
      .frame(width: 62)

      Text("Height:")

      TextField(
        "Height",
        value: $fixedLoadedImageWindowHeight,
        format: .number.precision(.fractionLength(0)),
      )
      .focused($heightInputFocused)
      .onSubmit {
        fixedLoadedImageWindowHeight = sanitizedHeight(fixedLoadedImageWindowHeight)
      }
      .onChange(of: heightInputFocused) { _, newValue in
        if !newValue {
          fixedLoadedImageWindowHeight = sanitizedHeight(fixedLoadedImageWindowHeight)
        }
      }
      .labelsHidden()
      .monospacedDigit()
      .frame(width: 62)

      Picker("", selection: $fixedLoadedImageWindowSizeUnit) {
        ForEach(LoadedImageWindowSizeUnit.allCases) {
          Text($0.description).tag($0)
        }
      }
      .labelsHidden()

      if fixedLoadedImageWindowWidth != AppSettings.Defaults.fixedLoadedImageWindowWidth
        || fixedLoadedImageWindowHeight != AppSettings.Defaults.fixedLoadedImageWindowHeight
        || fixedLoadedImageWindowSizeUnit != AppSettings.Defaults.fixedLoadedImageWindowSizeUnit
      {
        Button("Reset", systemImage: "arrow.counterclockwise") {
          fixedLoadedImageWindowWidth = AppSettings.Defaults.fixedLoadedImageWindowWidth
          fixedLoadedImageWindowHeight = AppSettings.Defaults.fixedLoadedImageWindowHeight
          fixedLoadedImageWindowSizeUnit = AppSettings.Defaults.fixedLoadedImageWindowSizeUnit
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
      }
    }
  }

  private func sanitizedWidth(_ value: Double) -> Double {
    AppSettings.normalizedFixedLoadedImageWindowDimension(
      value,
      minimum: Constants.minimumWindowContentWidth,
    )
  }

  private func sanitizedHeight(_ value: Double) -> Double {
    AppSettings.normalizedFixedLoadedImageWindowDimension(
      value,
      minimum: Constants.minimumWindowContentHeight,
    )
  }

  private func normalizeFixedLoadedImageWindowSize() {
    fixedLoadedImageWindowWidth = sanitizedWidth(fixedLoadedImageWindowWidth)
    fixedLoadedImageWindowHeight = sanitizedHeight(fixedLoadedImageWindowHeight)
  }
}
