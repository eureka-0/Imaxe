//
//  SharedUITests.swift
//  ImaxeTests
//
//  Created by lxlong on 2026/6/14.
//

@testable import Imaxe
import SwiftUI
import Testing

@MainActor
@Suite("Shared UI")
struct SharedUITests {
  @Test func `color hex serializes grayscale colors as rgba`() {
    let color = Color(.sRGB, white: 0.5, opacity: 0.25)

    #expect(color.hex == "#80808040")
  }

  @Test func `color hex preserves rgb and alpha components`() {
    let color = Color(hex: "#33669980")

    #expect(color.hex == "#33669980")
  }

  @Test func `image collection single mode initializers compile`() {
    let items = [CollectionInitializerTestItem(id: 1)]

    _ = ImageCollectionView(
      items,
      listRow: { item, _ in
        Text("Row \(item.id)")
      },
    )

    _ = ImageCollectionView(
      items,
      gridItem: { item, _ in
        Text("Grid \(item.id)")
      },
    )

    _ = ImageCollectionView(
      items,
      listRow: { item, _ in
        Text("Row \(item.id)")
      },
      contextMenu: { _ in
        Button("Inspect") {}
      },
    )

    _ = ImageCollectionView(
      items,
      gridItem: { item, _ in
        Text("Grid \(item.id)")
      },
      contextMenu: { _ in
        Button("Inspect") {}
      },
    )
  }

  private struct CollectionInitializerTestItem: Identifiable {
    let id: Int
  }
}
