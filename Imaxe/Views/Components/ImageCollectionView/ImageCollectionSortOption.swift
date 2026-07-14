//
//  ImageCollectionSortOption.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/6.
//

import Foundation

struct ImageCollectionSortValue {
  private let value: Any
  private let compareValue: (Any) -> ComparisonResult

  init<Value: Comparable>(_ value: Value) {
    self.value = value
    compareValue = { otherValue in
      guard let otherValue = otherValue as? Value else {
        return .orderedSame
      }
      if value < otherValue {
        return .orderedAscending
      }
      if value > otherValue {
        return .orderedDescending
      }
      return .orderedSame
    }
  }

  func compare(to other: ImageCollectionSortValue) -> ComparisonResult {
    compareValue(other.value)
  }
}

struct ImageCollectionSortOption<Item>: Identifiable, Equatable {
  let id: String
  let title: LocalizedStringResource
  let compare: (Item, Item) -> ComparisonResult
  let sortValue: ((Item) -> ImageCollectionSortValue?)?

  init(
    _ id: String,
    title: LocalizedStringResource,
    compare: @escaping (Item, Item) -> ComparisonResult,
    sortValue: ((Item) -> ImageCollectionSortValue?)? = nil,
  ) {
    self.id = id
    self.title = title
    self.compare = compare
    self.sortValue = sortValue
  }

  init(
    _ id: String,
    title: LocalizedStringResource,
    value: @escaping (Item) -> some Comparable,
  ) {
    self.init(id, title: title) { first, second in
      Self.compareValues(value(first), value(second))
    } sortValue: { item in
      ImageCollectionSortValue(value(item))
    }
  }

  init(
    _ id: String,
    title: LocalizedStringResource,
    optionalValue: @escaping (Item) -> (some Comparable)?,
  ) {
    self.init(id, title: title) { first, second in
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
    } sortValue: { item in
      guard let value = optionalValue(item) else { return nil }
      return ImageCollectionSortValue(value)
    }
  }

  static func compareValues<Value: Comparable>(
    _ first: Value,
    _ second: Value,
  ) -> ComparisonResult {
    if first < second {
      return .orderedAscending
    }
    if first > second {
      return .orderedDescending
    }
    return .orderedSame
  }

  static func == (
    lhs: ImageCollectionSortOption<Item>,
    rhs: ImageCollectionSortOption<Item>,
  ) -> Bool {
    lhs.id == rhs.id
  }
}
