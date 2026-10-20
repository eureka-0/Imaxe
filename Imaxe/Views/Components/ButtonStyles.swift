// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import SwiftUI

struct BorderedOnHoverButtonStyle: ButtonStyle {
  var cornerRadius: CGFloat = 8
  var applyPressedEffect: Bool = true
  var isActive: Bool = false

  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
  @State private var isHovering = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(
        isEnabled
          ? AnyShapeStyle(configuration.role == .destructive ? .red : .primary)
          : AnyShapeStyle(.tertiary),
      )
      .background(
        configuration.isPressed && applyPressedEffect
          ? Color.primary.opacity(0.17)
          : ((isHovering || isActive) && isEnabled ? .primary.opacity(0.1) : .clear),
      )
      .clipShape(.rect(cornerRadius: cornerRadius))
      .contentShape(.rect(cornerRadius: cornerRadius))
      .animation(
        accessibilityReduceMotion ? nil : .easeOut(duration: 0.12),
        value: isHovering,
      )
      .animation(
        accessibilityReduceMotion ? nil : .easeOut(duration: 0.08),
        value: configuration.isPressed && applyPressedEffect,
      )
      .onHover { isHovering in
        self.isHovering = isHovering
      }
  }
}

extension ButtonStyle where Self == BorderedOnHoverButtonStyle {
  static var borderedOnHover: Self {
    BorderedOnHoverButtonStyle()
  }

  static func borderedOnHover(
    cornerRadius: CGFloat = 8,
    applyPressedEffect: Bool = true,
    isActive: Bool = false,
  ) -> Self {
    BorderedOnHoverButtonStyle(
      cornerRadius: cornerRadius,
      applyPressedEffect: applyPressedEffect,
      isActive: isActive,
    )
  }
}
