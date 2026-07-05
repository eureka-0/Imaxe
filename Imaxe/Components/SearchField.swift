//
//  SearchField.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/4.
//

import SwiftUI

// MARK: - SearchField

struct SearchField: View {
  var placeholder: LocalizedStringKey = "Search"
  @Binding var text: String

  @FocusState private var isFocused: Bool
  @State private var isFolded: Bool = true
  @State private var isHoveringFoldedButton = false

  private var cornerRadius: CGFloat = 8
  private var externalFocus: FocusState<Bool>.Binding?
  private var foldable: Bool = false
  private var submitAction: (() -> Void) = {}

  private var minWidth: CGFloat = 80
  private var idealWidth: CGFloat = 180
  private var maxWidth: CGFloat = 300
  private var fieldHeight: CGFloat = 26
  private let iconLength: CGFloat = 16

  init(_ placeholder: LocalizedStringKey = "Search", text: Binding<String>) {
    self.placeholder = placeholder
    _text = text
  }

  private var isShowingFolded: Bool {
    foldable && isFolded && text.isEmpty
  }

  private var effectiveFocus: FocusState<Bool>.Binding {
    externalFocus ?? $isFocused
  }

  private var isTextFocused: Bool {
    externalFocus?.wrappedValue ?? isFocused
  }

  private var foldedButtonBackground: some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .fill(isHoveringFoldedButton ? .controlBackground.opacity(0.85) : .clear)
      .animation(.easeOut(duration: 0.12), value: isHoveringFoldedButton)
  }

  var body: some View {
    ZStack(alignment: .trailing) {
      foldedField
        .opacity(isShowingFolded ? 1.0 : 0.0)

      expandedField
        .opacity(isShowingFolded ? 0.0 : 1.0)
        .allowsHitTesting(!isShowingFolded)
    }
    .frame(height: fieldHeight)
    .fixedSize(horizontal: false, vertical: true)
    .preservesTextFocusOnClick()
    .animation(.interactiveSpring(response: 0.22), value: isFolded)
    .animation(.easeOut(duration: 0.12), value: isTextFocused)
    .onChange(of: isTextFocused) { _, newValue in
      isFocused = newValue
      if newValue, foldable {
        isFolded = false
      } else if text.isEmpty, foldable {
        isFolded = true
      }
    }
    .onChange(of: text) { _, newValue in
      if !newValue.isEmpty, foldable {
        isFolded = false
      }
    }
  }

  private var foldedField: some View {
    Button(action: expandAndFocus) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: iconLength, height: iconLength)
        .frame(width: fieldHeight, height: fieldHeight)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .background(foldedButtonBackground)
    }
    .buttonStyle(.plain)
    .help("Search")
    .onHover { isHoveringFoldedButton = $0 }
  }

  private var expandedField: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: iconLength, height: iconLength)
        .onTapGesture {
          expandAndFocus()
        }

      TextField(placeholder, text: $text)
        .textFieldStyle(.plain)
        .onSubmit(submitAction)
        .focused(effectiveFocus)

      if !text.isEmpty {
        Button {
          text = ""
          setTextFocused(true)
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: iconLength, height: iconLength)
        }
        .buttonStyle(.plain)
        .help("Clear Search")
      }
    }
    .padding(.horizontal, 8)
    .frame(height: fieldHeight)
    .frame(minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth)
    .background {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(.textBackground)
    }
    .overlay {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(
          isTextFocused ? .keyboardFocusIndicator : .separator.opacity(0.6),
          lineWidth: isTextFocused ? 2.0 : 0.5,
        )
    }
    .shadow(
      color: isTextFocused ? .keyboardFocusIndicator.opacity(0.45) : .clear,
      radius: 2.0,
    )
    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .onTapGesture {
      expandAndFocus()
    }
  }

  private func expandAndFocus() {
    if foldable {
      isFolded = false
    }
    setTextFocused(true)
  }

  private func setTextFocused(_ isFocused: Bool) {
    if let externalFocus {
      externalFocus.wrappedValue = isFocused
    } else {
      self.isFocused = isFocused
    }
  }
}

// MARK: - Modifiers

extension SearchField {
  func focused(_ condition: FocusState<Bool>.Binding) -> Self {
    var view = self
    view.externalFocus = condition
    return view
  }

  func foldable(_ foldable: Bool) -> Self {
    var view = self
    view.foldable = foldable
    return view
  }

  func frame(
    minWidth: CGFloat? = nil,
    idealWidth: CGFloat? = nil,
    maxWidth: CGFloat? = nil,
    fieldHeight: CGFloat? = nil,
  ) -> Self {
    var view = self
    if let minWidth {
      view.minWidth = minWidth
    }
    if let idealWidth {
      view.idealWidth = idealWidth
    }
    if let maxWidth {
      view.maxWidth = maxWidth
    }
    if let fieldHeight {
      view.fieldHeight = fieldHeight
    }
    return view
  }

  func onSubmit(_ action: @escaping () -> Void) -> Self {
    var view = self
    view.submitAction = action
    return view
  }
}
