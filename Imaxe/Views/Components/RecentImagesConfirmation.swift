// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import SwiftData
import SwiftUI

private struct ClearRecentImagesConfirmationKey: FocusedValueKey {
  typealias Value = Binding<Bool>
}

extension FocusedValues {
  var clearRecentImagesConfirmation: Binding<Bool>? {
    get { self[ClearRecentImagesConfirmationKey.self] }
    set { self[ClearRecentImagesConfirmationKey.self] = newValue }
  }
}

private struct RecentImagesConfirmation: ViewModifier {
  @Binding var isPresented: Bool
  @Environment(\.modelContext) private var modelContext
  @State private var errorMessage: String?

  func body(content: Content) -> some View {
    content
      .focusedSceneValue(\.clearRecentImagesConfirmation, $isPresented)
      .background(dialogPresenter)
  }

  private var dialogPresenter: some View {
    Color.clear
      .frame(width: 0, height: 0)
      .confirmationDialog(
        "Clear Recent Images?",
        isPresented: $isPresented,
        titleVisibility: .visible,
      ) {
        Button("Clear Recent Images", role: .destructive) {
          do {
            try RecentImagesStore.clear(in: modelContext)
          } catch {
            errorMessage = error.localizedDescription
          }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("""
        This clears all recent image records, including those hidden by search. \
        Original images are kept.
        """)
      }
      .alert("Failed to Clear Recent Images", isPresented: Binding(
        get: { errorMessage != nil },
        set: {
          if !$0 {
            errorMessage = nil
          }
        },
      )) {
        Button("OK") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
  }
}

extension View {
  func confirmClearRecentImages(isPresented: Binding<Bool>) -> some View {
    modifier(RecentImagesConfirmation(isPresented: isPresented))
  }
}
