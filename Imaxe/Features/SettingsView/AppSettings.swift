//
//  AppSettings.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/24.
//

import Foundation
import SwiftUI

enum Appearance: String, CaseIterable, Identifiable {
  case system, light, dark

  var id: String {
    rawValue
  }

  var description: LocalizedStringKey {
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

enum ImageActualSizeStrategy: String, CaseIterable, Identifiable {
  case pixelSize, pointSize, printSize

  var id: String {
    rawValue
  }

  var description: LocalizedStringKey {
    switch self {
    case .pixelSize: "1 image pixel corresponds to 1 screen pixel"
    case .pointSize: "1 image pixel corresponds to 1 screen point"
    case .printSize: "Actual print size based on image DPI and screen PPI"
    }
  }
}

enum LoadedImageWindowSizeMode: String, CaseIterable, Identifiable {
  case actualSizeLimitedToScreen, scaleToFitScreen, fillScreen, actualSize, fixedSize

  var id: String {
    rawValue
  }

  var description: LocalizedStringKey {
    switch self {
    case .actualSizeLimitedToScreen: "Actual size (limited to screen)"
    case .scaleToFitScreen: "Scale to fit screen"
    case .fillScreen: "Fill screen"
    case .actualSize: "Actual size"
    case .fixedSize: "Fixed size"
    }
  }
}

enum LoadedImageWindowSizeUnit: String, CaseIterable, Identifiable {
  case points, pixels

  var id: String {
    rawValue
  }

  var description: LocalizedStringKey {
    switch self {
    case .points: "Points"
    case .pixels: "Pixels"
    }
  }
}

enum AppSettings {
  enum Keys: String, CaseIterable, Identifiable {
    case appearance
    case topBarHideDelay
    case enableLoopBrowsing

    case imageActualSizeStrategy
    case loadedImageWindowSizeMode
    case fixedLoadedImageWindowWidth
    case fixedLoadedImageWindowHeight
    case fixedLoadedImageWindowSizeUnit

    var id: String {
      rawValue
    }
  }

  enum Defaults {
    static let appearance: Appearance = .system
    static let topBarHideDelay = 1.5
    static let enableLoopBrowsing = true

    static let imageActualSizeStrategy: ImageActualSizeStrategy = .pixelSize
    static let loadedImageWindowSizeMode: LoadedImageWindowSizeMode = .actualSizeLimitedToScreen
    static let fixedLoadedImageWindowWidth = 680.0
    static let fixedLoadedImageWindowHeight = 520.0
    static let fixedLoadedImageWindowSizeUnit: LoadedImageWindowSizeUnit = .points

    static var fixedLoadedImageWindowSize: NSSize {
      NSSize(
        width: fixedLoadedImageWindowWidth,
        height: fixedLoadedImageWindowHeight,
      )
    }
  }
}
