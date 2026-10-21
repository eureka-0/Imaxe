// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import Foundation
import SwiftUI

// MARK: - AppSettings

enum AppSettings {
  static let userDefaults: UserDefaults = {
    #if DEBUG
      if let storage = TestStorage.current {
        return storage.makeDefaults()
      }
    #endif
    return .standard
  }()

  enum Keys: String, CaseIterable, Identifiable {
    case appearance
    case backgroundColor
    case topBarHideDelay
    case enableLoopBrowsing
    case actionOnImageFileChange
    case recentImagesCountLimit

    case imageActualSizeStrategy
    case loadedImageWindowSizeMode
    case fixedLoadedImageWindowWidth
    case fixedLoadedImageWindowHeight
    case fixedLoadedImageWindowSizeUnit
    case imageInterpolationStrategy

    var id: String {
      rawValue
    }
  }

  enum Defaults {
    static let appearance: Appearance = .system
    static let backgroundColor = BackgroundColor()
    static let topBarHideDelay = 1.5
    static let enableLoopBrowsing = true
    static let actionOnImageFileChange: ActionOnImageFileChange = .reload
    static let recentImagesCountLimit = 100

    static let imageActualSizeStrategy: ImageActualSizeStrategy = .pixelSize
    static let loadedImageWindowSizeMode: LoadedImageWindowSizeMode = .actualSizeLimitedToScreen
    static let fixedLoadedImageWindowWidth = 680.0
    static let fixedLoadedImageWindowHeight = 520.0
    static let fixedLoadedImageWindowSizeUnit: LoadedImageWindowSizeUnit = .points
    static let imageInterpolationStrategy: ImageInterpolationStrategy = .high

    static var fixedLoadedImageWindowSize: NSSize {
      NSSize(
        width: fixedLoadedImageWindowWidth,
        height: fixedLoadedImageWindowHeight,
      )
    }
  }

  static func normalizedFixedLoadedImageWindowDimension(
    _ value: Double,
    minimum: CGFloat,
  ) -> Double {
    guard value.isFinite else { return Double(minimum) }

    return value.clamped(to: Double(minimum) ... 10000)
  }
}

// MARK: - Appearance

enum Appearance: String, CaseIterable, Identifiable {
  case system, light, dark

  var id: String {
    rawValue
  }

  var description: LocalizedStringResource {
    switch self {
    case .system: "System"
    case .light: "Light"
    case .dark: "Dark"
    }
  }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

// MARK: - BackgroundColor

struct BackgroundColor: Codable, Equatable, RawRepresentable {
  let hex: String

  init(rawValue: String = "") {
    hex = rawValue
  }

  var rawValue: String {
    hex
  }

  var color: Color {
    hex.count == 0 ? .clear : Color(hex: hex)
  }

  var nsColor: NSColor {
    hex.count == 0 ? .clear : NSColor(hex: hex)
  }
}

enum ActionOnImageFileChange: String, CaseIterable, Identifiable {
  case reload, ignore

  var id: String {
    rawValue
  }

  var description: LocalizedStringResource {
    switch self {
    case .reload: "Reload"
    case .ignore: "Ignore"
    }
  }
}

// MARK: - ImageActualSizeStrategy

enum ImageActualSizeStrategy: String, CaseIterable, Identifiable {
  case pixelSize, pointSize, printSize

  var id: String {
    rawValue
  }

  var description: LocalizedStringResource {
    switch self {
    case .pixelSize: "1 image pixel corresponds to 1 screen pixel"
    case .pointSize: "1 image pixel corresponds to 1 screen point"
    case .printSize: "Actual print size based on image DPI and screen PPI"
    }
  }
}

// MARK: - LoadedImageWindowSizeMode

enum LoadedImageWindowSizeMode: String, CaseIterable, Identifiable {
  case actualSizeLimitedToScreen, zoomToFitScreen, fillScreen, actualSize, fixedSize

  var id: String {
    rawValue
  }

  var description: LocalizedStringResource {
    switch self {
    case .actualSizeLimitedToScreen: "Actual size (limited to screen)"
    case .zoomToFitScreen: "Fit to screen"
    case .fillScreen: "Fill screen"
    case .actualSize: "Actual size"
    case .fixedSize: "Fixed size"
    }
  }
}

// MARK: - LoadedImageWindowSizeUnit

enum LoadedImageWindowSizeUnit: String, CaseIterable, Identifiable {
  case points, pixels

  var id: String {
    rawValue
  }

  var description: LocalizedStringResource {
    switch self {
    case .points: "Points"
    case .pixels: "Pixels"
    }
  }
}

// MARK: - ImageInterpolationStrategy

enum ImageInterpolationStrategy: String, CaseIterable, Identifiable {
  case none, low, medium, high

  var id: String {
    rawValue
  }

  var description: LocalizedStringResource {
    switch self {
    case .none: "None"
    case .low: "Low"
    case .medium: "Medium"
    case .high: "High"
    }
  }
}
