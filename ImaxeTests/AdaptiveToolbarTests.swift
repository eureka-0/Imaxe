//
//  AdaptiveToolbarTests.swift
//  ImaxeTests
//

@testable import Imaxe
import SwiftUI
import Testing

@Suite("Adaptive Toolbar")
struct AdaptiveToolbarTests {
  @Test(arguments: [
    (AdaptiveToolbarOverflowEdge.left, [0, 1, 2]),
    (.right, [2, 1, 0]),
    (.top, [0, 1, 2]),
    (.bottom, [2, 1, 0]),
  ])
  func `equal priority units collapse from configured edge`(
    edge: AdaptiveToolbarOverflowEdge,
    expectedOrder: [Int],
  ) {
    #expect(AdaptiveToolbarLayout.collapseOrder(for: units(), edge: edge) == expectedOrder)
  }

  @Test func `higher priority and always visible units remain inline longer`() {
    let items = [
      item(0, priority: 100),
      item(1),
      item(2, behavior: .alwaysVisible),
    ]
    let resolved = AdaptiveToolbarLayout.resolveUnits(from: items)

    #expect(AdaptiveToolbarLayout.collapseOrder(for: resolved, edge: .right) == [1, 0])

    var state = AdaptiveToolbarLayoutState()
    AdaptiveToolbarLayout.reduce(
      state: &state,
      input: input(units: resolved, availableLength: 35),
      structuralReset: true,
    )
    #expect(state.visibleUnitIDs == [2])
  }

  @Test func `always visible group member keeps the atomic group inline`() {
    let resolved = AdaptiveToolbarLayout.resolveUnits(from: [
      item(0, groupID: "group"),
      item(1, behavior: .alwaysVisible, groupID: "group"),
      item(2),
    ])

    #expect(resolved[0].memberIDs == [0, 1])
    #expect(resolved[0].behavior == .alwaysVisible)
    #expect(AdaptiveToolbarLayout.collapseOrder(for: resolved, edge: .right) == [2])
  }

  @Test func `adjacent group members collapse and restore together`() {
    let resolved = AdaptiveToolbarLayout.resolveUnits(from: [
      item(0, priority: -1, groupID: "group"),
      item(1, priority: -1, groupID: "group"),
      item(2, priority: 1),
    ])
    var state = AdaptiveToolbarLayoutState()
    AdaptiveToolbarLayout.reduce(
      state: &state,
      input: input(units: resolved, availableLength: 50),
      structuralReset: true,
    )
    #expect(state.visibleUnitIDs == [2])
    #expect(AdaptiveToolbarLayout.hiddenItemSourceIndices(
      units: resolved,
      visibleUnitIDs: state.visibleUnitIDs,
    ) == [0, 1])

    AdaptiveToolbarLayout.reduce(
      state: &state,
      input: input(units: resolved, availableLength: 78, hysteresis: 8),
    )
    #expect(state.visibleUnitIDs == [0, 2])
  }

  @Test(arguments: [
    AdaptiveToolbarOverflowEdge.left,
    .right,
    .top,
    .bottom,
  ])
  func `hidden menu items remain in source order`(edge: AdaptiveToolbarOverflowEdge) {
    let resolved = units()
    var state = AdaptiveToolbarLayoutState()
    AdaptiveToolbarLayout.reduce(
      state: &state,
      input: input(units: resolved, availableLength: 35, edge: edge),
      structuralReset: true,
    )
    let hidden = AdaptiveToolbarLayout.hiddenItemSourceIndices(
      units: resolved,
      visibleUnitIDs: state.visibleUnitIDs,
    )
    #expect(hidden == hidden.sorted())
  }

  @Test func `first overflow introduces More and its width participates in fitting`() {
    var state = AdaptiveToolbarLayoutState()
    AdaptiveToolbarLayout.reduce(
      state: &state,
      input: input(units: units(count: 2), availableLength: 41),
      structuralReset: true,
    )

    #expect(state.visibleUnitIDs.isEmpty)
    #expect(AdaptiveToolbarLayout.isMoreVisible(
      units: units(count: 2),
      visibleUnitIDs: state.visibleUnitIDs,
      visibility: .automatic,
      hasFixedMoreContent: false,
    ))
  }

  @Test func `More can remain visible without overflow`() {
    let resolved = units(count: 1)
    let allVisible = Set(resolved.map(\.id))

    #expect(AdaptiveToolbarLayout.isMoreVisible(
      units: resolved,
      visibleUnitIDs: allVisible,
      visibility: .always,
      hasFixedMoreContent: false,
    ))
    #expect(AdaptiveToolbarLayout.isMoreVisible(
      units: resolved,
      visibleUnitIDs: allVisible,
      visibility: .automatic,
      hasFixedMoreContent: true,
    ))
  }

  @Test func `collapse is immediate and restoration waits for hysteresis reserve`() {
    let resolved = AdaptiveToolbarLayout.resolveUnits(from: [
      item(0, length: 40),
      item(1, length: 40),
    ])
    var state = AdaptiveToolbarLayoutState()
    AdaptiveToolbarLayout.reduce(
      state: &state,
      input: input(units: resolved, availableLength: 82),
      structuralReset: true,
    )
    #expect(state.visibleUnitIDs.count == 2)

    AdaptiveToolbarLayout.reduce(
      state: &state,
      input: input(units: resolved, availableLength: 81),
    )
    #expect(state.visibleUnitIDs.count == 1)

    AdaptiveToolbarLayout.reduce(
      state: &state,
      input: input(units: resolved, availableLength: 89, hysteresis: 8),
    )
    #expect(state.visibleUnitIDs.count == 1)

    AdaptiveToolbarLayout.reduce(
      state: &state,
      input: input(units: resolved, availableLength: 90, hysteresis: 8),
    )
    #expect(state.visibleUnitIDs.count == 2)
  }

  @Test func `subpoint measurement noise is ignored`() {
    #expect(!AdaptiveToolbarLayout.shouldAcceptMeasurement(previous: 24, newValue: 24.49))
    #expect(AdaptiveToolbarLayout.shouldAcceptMeasurement(previous: 24, newValue: 24.5))
    #expect(!AdaptiveToolbarLayout.shouldAcceptMeasurement(previous: nil, newValue: .nan))
  }

  @Test func `structural reset discards stale visibility`() {
    var state = AdaptiveToolbarLayoutState(visibleUnitIDs: [99], isInitialized: true)
    AdaptiveToolbarLayout.reduce(
      state: &state,
      input: input(units: units(count: 2), availableLength: 100),
      structuralReset: true,
    )
    #expect(state.visibleUnitIDs == [0, 1])
  }

  @Test func `invalid edges normalize to axis defaults`() {
    #expect(AdaptiveToolbarOverflowEdge
      .normalized(.top, for: .horizontal, reportFailure: false) == .right)
    #expect(AdaptiveToolbarOverflowEdge
      .normalized(.left, for: .vertical, reportFailure: false) == .bottom)
    #expect(AdaptiveToolbarOverflowEdge
      .normalized(.left, for: .horizontal, reportFailure: false) == .left)
    #expect(AdaptiveToolbarOverflowEdge
      .normalized(.top, for: .vertical, reportFailure: false) == .top)
  }

  private func item(
    _ id: Int,
    length: CGFloat = 20,
    priority: Int = 0,
    behavior: AdaptiveToolbarItemBehavior = .automatic,
    groupID: AdaptiveToolbarGroupID? = nil,
  ) -> AdaptiveToolbarResolvedItem {
    AdaptiveToolbarResolvedItem(
      id: id,
      sourceIndex: id,
      length: length,
      priority: priority,
      behavior: behavior,
      groupID: groupID,
    )
  }

  private func units(count: Int = 3) -> [AdaptiveToolbarResolvedUnit] {
    AdaptiveToolbarLayout.resolveUnits(from: (0 ..< count).map { item($0) })
  }

  private func input(
    units: [AdaptiveToolbarResolvedUnit],
    availableLength: CGFloat,
    hysteresis: CGFloat = 0,
    edge: AdaptiveToolbarOverflowEdge = .right,
  ) -> AdaptiveToolbarLayoutInput {
    AdaptiveToolbarLayoutInput(
      units: units,
      availableLength: availableLength,
      moreLength: 24,
      spacing: 2,
      hysteresis: hysteresis,
      overflowEdge: edge,
      moreVisibility: .automatic,
      hasFixedMoreContent: false,
    )
  }
}
