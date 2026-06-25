//
//  AppSettings.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/24.
//

import Foundation
import SwiftUI

enum Appearance: String, CaseIterable, Identifiable {
  case system = "System"
  case light = "Light"
  case dark = "Dark"

  var id: String {
    rawValue
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
  case pixelSize = "Pixel Size"
  case pointSize = "Point Size"
  case printSize = "Print Size"

  var id: String {
    rawValue
  }

  var description: String {
    switch self {
    case .pixelSize: "1 image pixel corresponds to 1 screen pixel"
    case .pointSize: "1 image pixel corresponds to 1 screen point"
    case .printSize: "Actual print size based on image DPI and screen PPI"
    }
  }
}

enum AppSettings {
  enum Keys: String, CaseIterable, Identifiable {
    case appearance
    case imageActualSizeStrategy

    var id: String {
      rawValue
    }
  }

  enum Defaults {
    static let appearance: Appearance = .system
    static let imageActualSizeStrategy: ImageActualSizeStrategy = .pixelSize
  }
}
