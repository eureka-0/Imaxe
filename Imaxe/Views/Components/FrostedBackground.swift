// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import AppKit
import SwiftUI

enum FrostedBackgroundStyle {
  case material
  case toolbar
  case floating
}

private struct FrostedVisualEffect: NSViewRepresentable {
  let material: NSVisualEffectView.Material

  func makeNSView(context _: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.blendingMode = .withinWindow
    view.state = .followsWindowActiveState
    view.material = material
    return view
  }

  func updateNSView(_ view: NSVisualEffectView, context _: Context) {
    view.material = material
  }
}

private struct FrostedBackground<BackgroundShape: Shape>: ViewModifier {
  let shape: BackgroundShape
  let style: FrostedBackgroundStyle
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  func body(content: Content) -> some View {
    Group {
      if reduceTransparency {
        content.background(Color(nsColor: .windowBackgroundColor), in: shape)
      } else if style == .toolbar {
        content.background(.bar, in: shape)
      } else if #available(macOS 26, *), style == .floating {
        content.glassEffect(.regular, in: shape)
      } else {
        content.background {
          FrostedVisualEffect(material: style == .floating ? .hudWindow : .headerView)
            .clipShape(shape)
            .allowsHitTesting(false)
        }
      }
    }
    .overlay(alignment: .bottom) {
      if style == .toolbar {
        Divider()
      }
    }
  }
}

extension View {
  func frostedBackground(
    in shape: some Shape = Rectangle(),
    style: FrostedBackgroundStyle = .material,
  ) -> some View {
    modifier(FrostedBackground(shape: shape, style: style))
  }
}
