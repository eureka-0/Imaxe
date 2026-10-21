// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import SwiftUI

struct MaterialSegmentedPicker<Item: Hashable, Content: View>: View {
  @Binding var selection: Item
  let items: [Item]
  let content: (Item) -> Content

  @Environment(\.appearsActive) private var appearsActive
  @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

  init(
    _ selection: Binding<Item>,
    items: [Item],
    @ViewBuilder content: @escaping (Item) -> Content,
  ) {
    _selection = selection
    self.items = items
    self.content = content
  }

  var body: some View {
    HStack(spacing: -4) {
      ForEach(items, id: \.self) { item in
        let isSelected = selection == item

        Button {
          withAnimation(selectionAnimation) {
            selection = item
          }
        } label: {
          content(item)
            .foregroundStyle(isSelected && appearsActive ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .anchorPreference(
          key: MaterialSegmentedPickerItemFrameKey.self,
          value: .bounds,
        ) { bounds in
          [AnyHashable(item): bounds]
        }
      }
    }
    .backgroundPreferenceValue(MaterialSegmentedPickerItemFrameKey.self) { itemFrames in
      GeometryReader { proxy in
        if let selectedFrameAnchor = itemFrames[AnyHashable(selection)] {
          let selectedFrame = proxy[selectedFrameAnchor]

          Capsule()
            .fill(appearsActive ? .selectedControl.opacity(0.5) : .secondary.opacity(0.1))
            .frame(width: selectedFrame.width, height: selectedFrame.height)
            .position(x: selectedFrame.midX, y: selectedFrame.midY)
            .animation(selectionAnimation, value: selection)
            .animation(
              accessibilityReduceMotion ? nil : .easeOut(duration: 0.12),
              value: appearsActive,
            )
        }
      }
      .allowsHitTesting(false)
    }
    .padding(2)
    .background(.primary.opacity(0.04), in: .capsule)
  }

  private var selectionAnimation: Animation? {
    accessibilityReduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)
  }
}

private struct MaterialSegmentedPickerItemFrameKey: PreferenceKey {
  static var defaultValue: [AnyHashable: Anchor<CGRect>] {
    [:]
  }

  static func reduce(
    value: inout [AnyHashable: Anchor<CGRect>],
    nextValue: () -> [AnyHashable: Anchor<CGRect>],
  ) {
    value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
  }
}
