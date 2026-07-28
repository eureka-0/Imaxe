// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import SwiftUI

struct AdaptiveToolbarResolvedItem: Equatable, Sendable {
  let id: Int
  let sourceIndex: Int
  let length: CGFloat
  let priority: Int
  let behavior: AdaptiveToolbarItemBehavior
  let groupID: AdaptiveToolbarGroupID?
}

struct AdaptiveToolbarResolvedUnit: Equatable, Sendable {
  let id: Int
  let sourceIndex: Int
  let memberIDs: [Int]
  let memberSourceIndices: [Int]
  let memberLengths: [CGFloat]
  let priority: Int
  let behavior: AdaptiveToolbarItemBehavior
}

struct AdaptiveToolbarLayoutInput: Equatable, Sendable {
  let units: [AdaptiveToolbarResolvedUnit]
  let availableLength: CGFloat
  let moreLength: CGFloat
  let spacing: CGFloat
  let hysteresis: CGFloat
  let overflowEdge: AdaptiveToolbarOverflowEdge
  let moreVisibility: AdaptiveToolbarMoreVisibility
  let hasFixedMoreContent: Bool
  var measurementTolerance: CGFloat = AdaptiveToolbarLayout.measurementTolerance
}

struct AdaptiveToolbarLayoutState: Equatable, Sendable {
  var visibleUnitIDs: Set<Int> = []
  var isInitialized = false
  var alwaysVisibleContentOverflows = false
}

struct AdaptiveToolbarLayoutChange: Equatable, Sendable {
  let visibleUnitIDsChanged: Bool
  let moreVisibilityChanged: Bool

  var didChangePresentation: Bool {
    visibleUnitIDsChanged || moreVisibilityChanged
  }
}

enum AdaptiveToolbarLayout {
  static let measurementTolerance: CGFloat = 0.5

  static func resolveUnits(
    from items: [AdaptiveToolbarResolvedItem],
    reportSeparatedGroups: Bool = true,
  ) -> [AdaptiveToolbarResolvedUnit] {
    var units: [AdaptiveToolbarResolvedUnit] = []
    var completedGroupIDs: Set<AdaptiveToolbarGroupID> = []
    var index = items.startIndex

    while index < items.endIndex {
      let firstItem = items[index]
      var members = [firstItem]
      var nextIndex = items.index(after: index)

      if let groupID = firstItem.groupID {
        if completedGroupIDs.contains(groupID), reportSeparatedGroups {
          assertionFailure("AdaptiveToolbar group members must be adjacent: \(groupID.rawValue)")
        }

        while nextIndex < items.endIndex, items[nextIndex].groupID == groupID {
          members.append(items[nextIndex])
          nextIndex = items.index(after: nextIndex)
        }
        completedGroupIDs.insert(groupID)
      }

      units.append(AdaptiveToolbarResolvedUnit(
        id: firstItem.sourceIndex,
        sourceIndex: firstItem.sourceIndex,
        memberIDs: members.map(\.id),
        memberSourceIndices: members.map(\.sourceIndex),
        memberLengths: members.map(\.length),
        priority: members.map(\.priority).max() ?? 0,
        behavior: members.contains(where: { $0.behavior == .alwaysVisible })
          ? .alwaysVisible
          : .automatic,
      ))
      index = nextIndex
    }

    return units
  }

  static func collapseOrder(
    for units: [AdaptiveToolbarResolvedUnit],
    edge: AdaptiveToolbarOverflowEdge,
  ) -> [Int] {
    units
      .filter { $0.behavior == .automatic }
      .sorted { lhs, rhs in
        if lhs.priority != rhs.priority {
          return lhs.priority < rhs.priority
        }

        switch edge {
        case .left, .top:
          return lhs.sourceIndex < rhs.sourceIndex
        case .right, .bottom:
          return lhs.sourceIndex > rhs.sourceIndex
        }
      }
      .map(\.id)
  }

  static func hiddenItemSourceIndices(
    units: [AdaptiveToolbarResolvedUnit],
    visibleUnitIDs: Set<Int>,
  ) -> [Int] {
    units
      .filter { !visibleUnitIDs.contains($0.id) }
      .flatMap(\.memberSourceIndices)
      .sorted()
  }

  static func isMoreVisible(
    units: [AdaptiveToolbarResolvedUnit],
    visibleUnitIDs: Set<Int>,
    visibility: AdaptiveToolbarMoreVisibility,
    hasFixedMoreContent: Bool,
  ) -> Bool {
    visibility == .always
      || hasFixedMoreContent
      || units.contains(where: { !visibleUnitIDs.contains($0.id) })
  }

  static func requiredLength(
    units: [AdaptiveToolbarResolvedUnit],
    visibleUnitIDs: Set<Int>,
    moreLength: CGFloat,
    spacing: CGFloat,
    moreVisibility: AdaptiveToolbarMoreVisibility,
    hasFixedMoreContent: Bool,
  ) -> CGFloat {
    let visibleUnits = units.filter { visibleUnitIDs.contains($0.id) }
    let itemLengths = visibleUnits.flatMap(\.memberLengths)
    let showsMore = isMoreVisible(
      units: units,
      visibleUnitIDs: visibleUnitIDs,
      visibility: moreVisibility,
      hasFixedMoreContent: hasFixedMoreContent,
    )
    let renderedElementCount = itemLengths.count + (showsMore ? 1 : 0)

    return itemLengths.reduce(0, +)
      + (showsMore ? moreLength : 0)
      + spacing * CGFloat(max(renderedElementCount - 1, 0))
  }

  @discardableResult
  static func reduce(
    state: inout AdaptiveToolbarLayoutState,
    input: AdaptiveToolbarLayoutInput,
    structuralReset: Bool = false,
  ) -> AdaptiveToolbarLayoutChange {
    let validUnitIDs = Set(input.units.map(\.id))
    let previousVisibleUnitIDs = state.isInitialized ? state.visibleUnitIDs : validUnitIDs
    let previousMoreVisibility = isMoreVisible(
      units: input.units,
      visibleUnitIDs: previousVisibleUnitIDs,
      visibility: input.moreVisibility,
      hasFixedMoreContent: input.hasFixedMoreContent,
    )

    if structuralReset || !state.isInitialized || !state.visibleUnitIDs.isSubset(of: validUnitIDs) {
      state.visibleUnitIDs = validUnitIDs
      state.isInitialized = true
    } else {
      state.visibleUnitIDs.formIntersection(validUnitIDs)
    }

    let collapseOrder = collapseOrder(for: input.units, edge: input.overflowEdge)
    while requiredLength(
      units: input.units,
      visibleUnitIDs: state.visibleUnitIDs,
      moreLength: input.moreLength,
      spacing: input.spacing,
      moreVisibility: input.moreVisibility,
      hasFixedMoreContent: input.hasFixedMoreContent,
    ) > input.availableLength + input.measurementTolerance {
      guard let unitID = collapseOrder.first(where: { state.visibleUnitIDs.contains($0) }) else {
        break
      }
      state.visibleUnitIDs.remove(unitID)
    }

    if !structuralReset {
      for unitID in collapseOrder.reversed() where !state.visibleUnitIDs.contains(unitID) {
        var restoredUnitIDs = state.visibleUnitIDs
        restoredUnitIDs.insert(unitID)
        let restoredLength = requiredLength(
          units: input.units,
          visibleUnitIDs: restoredUnitIDs,
          moreLength: input.moreLength,
          spacing: input.spacing,
          moreVisibility: input.moreVisibility,
          hasFixedMoreContent: input.hasFixedMoreContent,
        )
        guard restoredLength <= input.availableLength - input.hysteresis else { break }
        state.visibleUnitIDs = restoredUnitIDs
      }
    }

    state.alwaysVisibleContentOverflows = requiredLength(
      units: input.units,
      visibleUnitIDs: state.visibleUnitIDs,
      moreLength: input.moreLength,
      spacing: input.spacing,
      moreVisibility: input.moreVisibility,
      hasFixedMoreContent: input.hasFixedMoreContent,
    ) > input.availableLength + input.measurementTolerance

    let newMoreVisibility = isMoreVisible(
      units: input.units,
      visibleUnitIDs: state.visibleUnitIDs,
      visibility: input.moreVisibility,
      hasFixedMoreContent: input.hasFixedMoreContent,
    )
    return AdaptiveToolbarLayoutChange(
      visibleUnitIDsChanged: previousVisibleUnitIDs != state.visibleUnitIDs,
      moreVisibilityChanged: previousMoreVisibility != newMoreVisibility,
    )
  }

  static func shouldAcceptMeasurement(
    previous: CGFloat?,
    newValue: CGFloat,
    tolerance: CGFloat = measurementTolerance,
  ) -> Bool {
    guard newValue.isFinite, newValue >= 0 else { return false }
    guard let previous else { return true }
    return abs(previous - newValue) >= tolerance
  }
}
