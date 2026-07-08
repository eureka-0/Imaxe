//
//  MaterialSegmentedPicker.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/6.
//

import SwiftUI

struct MaterialSegmentedPicker<Item: Hashable, Content: View, Background: ShapeStyle>: View {
  @Binding var selection: Item
  let items: [Item]
  let content: (Item) -> Content
  var background: Background

  @Environment(\.appearsActive) private var appearsActive

  /// Namespace for matched geometry effect, used for the sliding background animation.
  @Namespace private var pickerTransition

  init(
    _ selection: Binding<Item>,
    items: [Item],
    background: Background = .regularMaterial,
    @ViewBuilder content: @escaping (Item) -> Content,
  ) {
    _selection = selection
    self.items = items
    self.content = content
    self.background = background
  }

  var body: some View {
    HStack(spacing: -4) {
      ForEach(items, id: \.self) { item in
        let isSelected = selection == item

        Button {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selection = item
          }
        } label: {
          content(item)
            .foregroundStyle(isSelected && appearsActive ? Color.accentColor : Color.secondary)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 8)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .background(
          Group {
            if isSelected {
              Capsule()
                .fill(appearsActive ? .selectedControl.opacity(0.5) : .secondary.opacity(0.1))
                .matchedGeometryEffect(id: "pickerActiveBackground", in: pickerTransition)
            }
          },
        )
      }
    }
    .padding(2)
    .background(background, in: .capsule)
  }
}
