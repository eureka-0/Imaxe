//
//  ImageCollectionSortOption.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/6.
//

import Foundation

struct ImageCollectionSortOption<Item>: Identifiable, Equatable {
  let id: String
  let title: String
  let systemImage: String
  let compare: (Item, Item) -> ComparisonResult

  init(
    _ id: String,
    title: String,
    systemImage: String,
    compare: @escaping (Item, Item) -> ComparisonResult,
  ) {
    self.id = id
    self.title = title
    self.systemImage = systemImage
    self.compare = compare
  }

  init(
    _ id: String,
    title: String,
    systemImage: String,
    value: @escaping (Item) -> some Comparable,
  ) {
    self.init(id, title: title, systemImage: systemImage) { first, second in
      Self.compareValues(value(first), value(second))
    }
  }

  init(
    _ id: String,
    title: String,
    systemImage: String,
    optionalValue: @escaping (Item) -> (some Comparable)?,
  ) {
    self.init(id, title: title, systemImage: systemImage) { first, second in
      let firstValue = optionalValue(first)
      let secondValue = optionalValue(second)

      switch (firstValue, secondValue) {
      case let (first?, second?):
        return Self.compareValues(first, second)
      case (nil, nil):
        return .orderedSame
      case (nil, _):
        return .orderedAscending
      case (_, nil):
        return .orderedDescending
      }
    }
  }

  static func compareValues<Value: Comparable>(
    _ first: Value,
    _ second: Value,
  ) -> ComparisonResult {
    if first < second { return .orderedAscending }
    if first > second { return .orderedDescending }
    return .orderedSame
  }

  static func == (
    lhs: ImageCollectionSortOption<Item>,
    rhs: ImageCollectionSortOption<Item>,
  ) -> Bool {
    lhs.id == rhs.id
  }
}
