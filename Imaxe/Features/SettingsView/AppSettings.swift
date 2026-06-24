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

enum AppSettings {
  enum Keys: String, CaseIterable, Identifiable {
    case appearance

    var id: String {
      rawValue
    }
  }

  enum Defaults {
    static let appearance: Appearance = .system
  }
}
