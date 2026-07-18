//
//  AdaptiveToolbar.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/16.
//

import SwiftUI

// MARK: - Enums and Structs

enum AdaptiveToolbarOverflowEdge: Hashable, Sendable {
  case top
  case bottom
  case left
  case right

  static func normalized(
    _ edge: AdaptiveToolbarOverflowEdge?,
    for axis: Axis,
    reportFailure: Bool = true,
  ) -> AdaptiveToolbarOverflowEdge {
    let defaultEdge: AdaptiveToolbarOverflowEdge = axis == .horizontal ? .right : .bottom
    guard let edge else { return defaultEdge }

    let isValid = switch (axis, edge) {
    case (.horizontal, .left), (.horizontal, .right), (.vertical, .top), (.vertical, .bottom):
      true
    default:
      false
    }
    if !isValid, reportFailure {
      assertionFailure("AdaptiveToolbar overflow edge \(edge) is invalid for axis \(axis)")
    }
    return isValid ? edge : defaultEdge
  }
}

enum AdaptiveToolbarMoreVisibility: Hashable, Sendable {
  case automatic
  case always
}

enum AdaptiveToolbarLabelMode: Hashable, Sendable {
  case iconOnly
  case iconAndLabel
}

enum AdaptiveToolbarItemBehavior: Hashable, Sendable {
  case automatic
  case alwaysVisible
}

struct AdaptiveToolbarGroupID: Hashable, Sendable, ExpressibleByStringLiteral {
  let rawValue: String

  init(stringLiteral value: String) {
    rawValue = value
  }
}

private struct AdaptiveToolbarOverflowContent {
  let view: AnyView
}

private struct AdaptiveToolbarSubviewMetadata: Equatable {
  let id: Subview.ID
  let sourceIndex: Int
  let priority: Int
  let behavior: AdaptiveToolbarItemBehavior
  let groupID: AdaptiveToolbarGroupID?
}

private struct AdaptiveToolbarStructureSignature: Equatable {
  let items: [AdaptiveToolbarSubviewMetadata]
  let axis: Axis
  let overflowEdge: AdaptiveToolbarOverflowEdge
  let moreVisibility: AdaptiveToolbarMoreVisibility
  let labelMode: AdaptiveToolbarLabelMode
  let spacing: CGFloat
  let hysteresis: CGFloat
}

// MARK: - Container Values

private extension ContainerValues {
  @Entry var adaptiveToolbarPriority = 0
  @Entry var adaptiveToolbarBehavior = AdaptiveToolbarItemBehavior.automatic
  @Entry var adaptiveToolbarGroupID: AdaptiveToolbarGroupID?
  @Entry var adaptiveToolbarOverflowContent: AdaptiveToolbarOverflowContent?
}

extension View {
  func adaptiveToolbarPriority(_ priority: Int) -> some View {
    containerValue(\.adaptiveToolbarPriority, priority)
  }

  func adaptiveToolbarBehavior(_ behavior: AdaptiveToolbarItemBehavior) -> some View {
    containerValue(\.adaptiveToolbarBehavior, behavior)
  }

  func adaptiveToolbarGroup(_ groupID: AdaptiveToolbarGroupID) -> some View {
    containerValue(\.adaptiveToolbarGroupID, groupID)
  }
}

// MARK: - AdaptiveToolbarItem

struct AdaptiveToolbarItem<InlineContent: View, OverflowContent: View>: View {
  private let content: InlineContent
  private let overflowContent: AdaptiveToolbarOverflowContent

  init(@ViewBuilder content: () -> InlineContent) where OverflowContent == InlineContent {
    let resolvedContent = content()
    self.content = resolvedContent
    overflowContent = AdaptiveToolbarOverflowContent(view: AnyView(resolvedContent))
  }

  init(
    @ViewBuilder content: () -> InlineContent,
    @ViewBuilder overflow: () -> OverflowContent,
  ) {
    self.content = content()
    overflowContent = AdaptiveToolbarOverflowContent(view: AnyView(overflow()))
  }

  var body: some View {
    content
      .containerValue(\.adaptiveToolbarOverflowContent, overflowContent)
  }
}

// MARK: - AdaptiveToolbarConfiguration

private struct AdaptiveToolbarConfiguration {
  var axis: Axis = .horizontal
  var overflowEdge: AdaptiveToolbarOverflowEdge?
  var moreVisibility: AdaptiveToolbarMoreVisibility = .automatic
  var labelMode: AdaptiveToolbarLabelMode = .iconOnly
  var spacing: CGFloat = 6
  var hysteresis: CGFloat = 8
}

// MARK: - AdaptiveToolbar

struct AdaptiveToolbarDefaultMoreLabel: View {
  var body: some View {
    Label("More", systemImage: "ellipsis.circle")
  }
}

struct AdaptiveToolbar<
  Content: View,
  MoreContent: View,
  MoreLabel: View,
  MoreMenuStyle: MenuStyle,
  MoreButtonStyleModifier: ViewModifier,
>: View {
  private let configuration: AdaptiveToolbarConfiguration
  private let content: Content
  private let moreContent: MoreContent
  private let moreLabel: MoreLabel
  private let moreMenuStyle: MoreMenuStyle
  private let moreButtonStyleModifier: MoreButtonStyleModifier

  @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

  @State private var availableLength: CGFloat?
  @State private var itemLengths: [Subview.ID: CGFloat] = [:]
  @State private var moreLength: CGFloat?
  @State private var layoutState = AdaptiveToolbarLayoutState()

  private var axis: Axis {
    configuration.axis
  }

  private var overflowEdge: AdaptiveToolbarOverflowEdge {
    .normalized(configuration.overflowEdge, for: axis)
  }

  private var moreVisibility: AdaptiveToolbarMoreVisibility {
    configuration.moreVisibility
  }

  private var labelMode: AdaptiveToolbarLabelMode {
    configuration.labelMode
  }

  private var spacing: CGFloat {
    configuration.spacing
  }

  private var hysteresis: CGFloat {
    configuration.hysteresis
  }

  private init(
    configuration: AdaptiveToolbarConfiguration,
    content: Content,
    moreContent: MoreContent,
    moreLabel: MoreLabel,
    moreMenuStyle: MoreMenuStyle,
    moreButtonStyleModifier: MoreButtonStyleModifier,
  ) {
    self.configuration = configuration
    self.content = content
    self.moreContent = moreContent
    self.moreLabel = moreLabel
    self.moreMenuStyle = moreMenuStyle
    self.moreButtonStyleModifier = moreButtonStyleModifier
  }

  private func configured(configuration: AdaptiveToolbarConfiguration) -> Self {
    Self(
      configuration: configuration,
      content: content,
      moreContent: moreContent,
      moreLabel: moreLabel,
      moreMenuStyle: moreMenuStyle,
      moreButtonStyleModifier: moreButtonStyleModifier,
    )
  }

  private func configured<Modifier: ViewModifier>(
    moreButtonStyleModifier: Modifier,
  ) -> AdaptiveToolbar<Content, MoreContent, MoreLabel, MoreMenuStyle, Modifier> {
    AdaptiveToolbar<Content, MoreContent, MoreLabel, MoreMenuStyle, Modifier>(
      configuration: configuration,
      content: content,
      moreContent: moreContent,
      moreLabel: moreLabel,
      moreMenuStyle: moreMenuStyle,
      moreButtonStyleModifier: moreButtonStyleModifier,
    )
  }

  var body: some View {
    Group(subviews: content) { subviews in
      let measurementAxis = axis
      let metadata = resolvedMetadata(for: subviews)
      let signature = structureSignature(for: metadata)
      let units = resolvedUnits(for: metadata, reportSeparatedGroups: false)
      let visibleUnitIDs = layoutState.isInitialized
        ? layoutState.visibleUnitIDs
        : Set(units.map(\.id))
      let hiddenSourceIndices = Set(AdaptiveToolbarLayout.hiddenItemSourceIndices(
        units: units,
        visibleUnitIDs: visibleUnitIDs,
      ))
      let showsMore = AdaptiveToolbarLayout.isMoreVisible(
        units: units,
        visibleUnitIDs: visibleUnitIDs,
        visibility: moreVisibility,
        hasFixedMoreContent: hasFixedMoreContent,
      )
      let intrinsicLength = intrinsicLength(for: metadata, units: units)
      let hasHiddenItems = units.contains { !visibleUnitIDs.contains($0.id) }
      let maximumLength = intrinsicLength.map {
        $0 + (hasHiddenItems ? hysteresis : 0)
      }

      GeometryReader { geometry in
        toolbarLayout(
          subviews: subviews,
          metadata: metadata,
          units: units,
          visibleUnitIDs: visibleUnitIDs,
          hiddenSourceIndices: hiddenSourceIndices,
          showsMore: showsMore,
        )
        .frame(
          width: geometry.size.width,
          height: geometry.size.height,
          alignment: contentAlignment,
        )
        .overlay(alignment: .topLeading) {
          moreMeasurementView(metadata: metadata)
        }
      }
      .onGeometryChange(for: CGFloat.self) { geometry in
        measurementAxis == .horizontal ? geometry.size.width : geometry.size.height
      } action: { newLength in
        guard newLength.isFinite, newLength >= 0 else { return }
        availableLength = newLength
        recalculate(for: metadata)
      }
      .onChange(of: signature, initial: true) { _, _ in
        resetLayout(for: metadata)
      }
      .frame(
        minWidth: nil,
        idealWidth: axis == .horizontal ? intrinsicLength : nil,
        maxWidth: axis == .horizontal ? maximumLength : nil,
        minHeight: nil,
        idealHeight: axis == .vertical ? intrinsicLength : nil,
        maxHeight: axis == .vertical ? maximumLength : nil,
        alignment: contentAlignment,
      )
    }
    .accessibilityElement(children: .contain)
  }

  private var hasFixedMoreContent: Bool {
    MoreContent.self != EmptyView.self
  }

  private var layout: AnyLayout {
    axis == .horizontal
      ? AnyLayout(HStackLayout(spacing: spacing))
      : AnyLayout(VStackLayout(spacing: spacing))
  }

  private var placesMoreFirst: Bool {
    overflowEdge == .left || overflowEdge == .top
  }

  private var contentAlignment: Alignment {
    switch overflowEdge {
    case .left:
      .leading
    case .right:
      .trailing
    case .top:
      .top
    case .bottom:
      .bottom
    }
  }

  private var itemTransition: AnyTransition {
    .opacity.combined(with: .scale(scale: 0.94))
  }

  private func toolbarLayout(
    subviews: SubviewsCollection,
    metadata: [AdaptiveToolbarSubviewMetadata],
    units: [AdaptiveToolbarResolvedUnit],
    visibleUnitIDs: Set<Int>,
    hiddenSourceIndices: Set<Int>,
    showsMore: Bool,
  ) -> some View {
    layout {
      if placesMoreFirst, showsMore {
        moreMenu(subviews: subviews, hiddenSourceIndices: hiddenSourceIndices)
          .transition(itemTransition)
      }

      ForEach(subviews) { subview in
        if let sourceIndex = subviews.firstIndex(where: { $0.id == subview.id }),
           let unit = units.first(where: { $0.memberSourceIndices.contains(sourceIndex) }),
           visibleUnitIDs.contains(unit.id)
        {
          measuredInline(subview, metadata: metadata)
            .transition(itemTransition)
        }
      }

      if !placesMoreFirst, showsMore {
        moreMenu(subviews: subviews, hiddenSourceIndices: hiddenSourceIndices)
          .transition(itemTransition)
      }
    }
  }

  @ViewBuilder
  private func inline(_ subview: Subview) -> some View {
    switch labelMode {
    case .iconOnly:
      subview.labelStyle(.iconOnly)
    case .iconAndLabel:
      subview.labelStyle(AdaptiveToolbarIconAndLabelStyle())
    }
  }

  private func measuredInline(
    _ subview: Subview,
    metadata: [AdaptiveToolbarSubviewMetadata],
  ) -> some View {
    let measurementAxis = axis

    // Measure the rendered instance so stateful modifiers have only one presentation host.
    return inline(subview)
      .fixedSize(
        horizontal: axis == .horizontal,
        vertical: axis == .vertical,
      )
      .onGeometryChange(for: CGFloat.self) { geometry in
        measurementAxis == .horizontal ? geometry.size.width : geometry.size.height
      } action: { newLength in
        updateItemLength(newLength, for: subview.id, metadata: metadata)
      }
  }

  @ViewBuilder
  private var moreMenuLabel: some View {
    switch labelMode {
    case .iconOnly:
      moreLabel
        .labelStyle(.iconOnly)
    case .iconAndLabel:
      moreLabel
        .labelStyle(AdaptiveToolbarIconAndLabelStyle())
    }
  }

  private func moreMenu(
    subviews: SubviewsCollection,
    hiddenSourceIndices: Set<Int>,
  ) -> some View {
    Menu {
      ForEach(subviews) { subview in
        if let sourceIndex = subviews.firstIndex(where: { $0.id == subview.id }),
           hiddenSourceIndices.contains(sourceIndex)
        {
          if let overflowContent = subview.containerValues.adaptiveToolbarOverflowContent {
            overflowContent.view
          } else {
            subview
          }
        }
      }

      if !hiddenSourceIndices.isEmpty, hasFixedMoreContent {
        Divider()
      }

      moreContent
    } label: {
      moreMenuLabel
    }
    .menuStyle(moreMenuStyle)
    .modifier(moreButtonStyleModifier)
    .help("More actions")
    .accessibilityLabel("More actions")
    .accessibilityValue("\(hiddenSourceIndices.count) hidden items")
  }

  private func moreMeasurementView(
    metadata: [AdaptiveToolbarSubviewMetadata],
  ) -> some View {
    let measurementAxis = axis

    return Menu {} label: { moreMenuLabel }
      .menuStyle(moreMenuStyle)
      .modifier(moreButtonStyleModifier)
      .fixedSize(
        horizontal: axis == .horizontal,
        vertical: axis == .vertical,
      )
      .onGeometryChange(for: CGFloat.self) { geometry in
        measurementAxis == .horizontal ? geometry.size.width : geometry.size.height
      } action: { newLength in
        guard AdaptiveToolbarLayout.shouldAcceptMeasurement(
          previous: moreLength,
          newValue: newLength,
        ) else { return }
        moreLength = newLength
        recalculate(for: metadata)
      }
      .opacity(0)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .transaction { transaction in
        transaction.animation = nil
      }
  }

  private func updateItemLength(
    _ newLength: CGFloat,
    for id: Subview.ID,
    metadata: [AdaptiveToolbarSubviewMetadata],
  ) {
    guard AdaptiveToolbarLayout.shouldAcceptMeasurement(
      previous: itemLengths[id],
      newValue: newLength,
    ) else { return }
    itemLengths[id] = newLength
    recalculate(for: metadata)
  }

  private func resetLayout(for metadata: [AdaptiveToolbarSubviewMetadata]) {
    _ = resolvedUnits(for: metadata, reportSeparatedGroups: true)
    let currentIDs = Set(metadata.map(\.id))
    itemLengths = itemLengths.filter { currentIDs.contains($0.key) }
    layoutState = AdaptiveToolbarLayoutState()
    recalculate(for: metadata, structuralReset: true)
  }

  private func recalculate(
    for metadata: [AdaptiveToolbarSubviewMetadata],
    structuralReset: Bool = false,
  ) {
    guard let availableLength, let moreLength else { return }
    guard metadata.allSatisfy({ itemLengths[$0.id] != nil }) else { return }

    let items = metadata.map { item in
      AdaptiveToolbarResolvedItem(
        id: item.sourceIndex,
        sourceIndex: item.sourceIndex,
        length: itemLengths[item.id] ?? 0,
        priority: item.priority,
        behavior: item.behavior,
        groupID: item.groupID,
      )
    }
    let units = AdaptiveToolbarLayout.resolveUnits(from: items, reportSeparatedGroups: false)
    let input = AdaptiveToolbarLayoutInput(
      units: units,
      availableLength: availableLength,
      moreLength: moreLength,
      spacing: spacing,
      hysteresis: hysteresis,
      overflowEdge: overflowEdge,
      moreVisibility: moreVisibility,
      hasFixedMoreContent: hasFixedMoreContent,
    )
    var nextState = layoutState
    let wasInitialized = nextState.isInitialized
    let change = AdaptiveToolbarLayout.reduce(
      state: &nextState,
      input: input,
      structuralReset: structuralReset,
    )
    guard nextState != layoutState else { return }

    var transaction = Transaction()
    if !structuralReset, wasInitialized, change.didChangePresentation, !accessibilityReduceMotion {
      transaction.animation = .easeInOut(duration: 0.18)
    } else {
      transaction.animation = nil
      transaction.disablesAnimations = true
    }
    withTransaction(transaction) {
      layoutState = nextState
    }
  }

  private func resolvedMetadata(
    for subviews: SubviewsCollection,
  ) -> [AdaptiveToolbarSubviewMetadata] {
    subviews.enumerated().map { sourceIndex, subview in
      AdaptiveToolbarSubviewMetadata(
        id: subview.id,
        sourceIndex: sourceIndex,
        priority: subview.containerValues.adaptiveToolbarPriority,
        behavior: subview.containerValues.adaptiveToolbarBehavior,
        groupID: subview.containerValues.adaptiveToolbarGroupID,
      )
    }
  }

  private func resolvedUnits(
    for metadata: [AdaptiveToolbarSubviewMetadata],
    reportSeparatedGroups: Bool,
  ) -> [AdaptiveToolbarResolvedUnit] {
    AdaptiveToolbarLayout.resolveUnits(
      from: metadata.map { item in
        AdaptiveToolbarResolvedItem(
          id: item.sourceIndex,
          sourceIndex: item.sourceIndex,
          length: itemLengths[item.id] ?? 0,
          priority: item.priority,
          behavior: item.behavior,
          groupID: item.groupID,
        )
      },
      reportSeparatedGroups: reportSeparatedGroups,
    )
  }

  private func structureSignature(
    for metadata: [AdaptiveToolbarSubviewMetadata],
  ) -> AdaptiveToolbarStructureSignature {
    AdaptiveToolbarStructureSignature(
      items: metadata,
      axis: axis,
      overflowEdge: overflowEdge,
      moreVisibility: moreVisibility,
      labelMode: labelMode,
      spacing: spacing,
      hysteresis: hysteresis,
    )
  }

  private func intrinsicLength(
    for metadata: [AdaptiveToolbarSubviewMetadata],
    units: [AdaptiveToolbarResolvedUnit],
  ) -> CGFloat? {
    guard let moreLength else { return nil }
    guard metadata.allSatisfy({ itemLengths[$0.id] != nil }) else { return nil }

    return AdaptiveToolbarLayout.requiredLength(
      units: units,
      visibleUnitIDs: Set(units.map(\.id)),
      moreLength: moreLength,
      spacing: spacing,
      moreVisibility: moreVisibility,
      hasFixedMoreContent: hasFixedMoreContent,
    )
  }
}

// MARK: - Convenience Initializers

extension AdaptiveToolbar where
  MoreMenuStyle == ButtonMenuStyle,
  MoreButtonStyleModifier == AdaptiveToolbarButtonStyleModifier<BorderedOnHoverButtonStyle>
{
  init(
    _ axis: Axis = .horizontal,
    spacing: CGFloat = 6,
    @ViewBuilder content: () -> Content,
    @ViewBuilder more: () -> MoreContent,
    @ViewBuilder moreLabel: () -> MoreLabel,
  ) {
    self.init(
      configuration: AdaptiveToolbarConfiguration(axis: axis, spacing: max(spacing, 0)),
      content: content(),
      moreContent: more(),
      moreLabel: moreLabel(),
      moreMenuStyle: ButtonMenuStyle(),
      moreButtonStyleModifier: AdaptiveToolbarButtonStyleModifier(
        style: BorderedOnHoverButtonStyle(),
      ),
    )
  }
}

extension AdaptiveToolbar where
  MoreLabel == AdaptiveToolbarDefaultMoreLabel,
  MoreMenuStyle == ButtonMenuStyle,
  MoreButtonStyleModifier == AdaptiveToolbarButtonStyleModifier<BorderedOnHoverButtonStyle>
{
  init(
    _ axis: Axis = .horizontal,
    spacing: CGFloat = 6,
    @ViewBuilder content: () -> Content,
    @ViewBuilder more: () -> MoreContent,
  ) {
    self.init(
      axis,
      spacing: spacing,
      content: content,
      more: more,
      moreLabel: { AdaptiveToolbarDefaultMoreLabel() },
    )
  }
}

extension AdaptiveToolbar where
  MoreContent == EmptyView,
  MoreMenuStyle == ButtonMenuStyle,
  MoreButtonStyleModifier == AdaptiveToolbarButtonStyleModifier<BorderedOnHoverButtonStyle>
{
  init(
    _ axis: Axis = .horizontal,
    spacing: CGFloat = 6,
    @ViewBuilder content: () -> Content,
    @ViewBuilder moreLabel: () -> MoreLabel,
  ) {
    self.init(
      axis,
      spacing: spacing,
      content: content,
      more: { EmptyView() },
      moreLabel: moreLabel,
    )
  }
}

extension AdaptiveToolbar where
  MoreContent == EmptyView,
  MoreLabel == AdaptiveToolbarDefaultMoreLabel,
  MoreMenuStyle == ButtonMenuStyle,
  MoreButtonStyleModifier == AdaptiveToolbarButtonStyleModifier<BorderedOnHoverButtonStyle>
{
  init(
    _ axis: Axis = .horizontal,
    spacing: CGFloat = 6,
    @ViewBuilder content: () -> Content,
  ) {
    self.init(
      axis,
      spacing: spacing,
      content: content,
      more: { EmptyView() },
    )
  }
}

// MARK: - Modifiers

struct AdaptiveToolbarButtonStyleModifier<Style: ButtonStyle>: ViewModifier {
  let style: Style

  func body(content: Content) -> some View {
    content.buttonStyle(style)
  }
}

struct AdaptiveToolbarPrimitiveButtonStyleModifier<Style: PrimitiveButtonStyle>: ViewModifier {
  let style: Style

  func body(content: Content) -> some View {
    content.buttonStyle(style)
  }
}

extension AdaptiveToolbar {
  func overflowFrom(_ edge: AdaptiveToolbarOverflowEdge?) -> Self {
    var configuration = configuration
    configuration.overflowEdge = edge
    return configured(configuration: configuration)
  }

  func moreVisibility(_ visibility: AdaptiveToolbarMoreVisibility) -> Self {
    var configuration = configuration
    configuration.moreVisibility = visibility
    return configured(configuration: configuration)
  }

  func labelMode(_ mode: AdaptiveToolbarLabelMode) -> Self {
    var configuration = configuration
    configuration.labelMode = mode
    return configured(configuration: configuration)
  }

  func hysteresis(_ length: CGFloat) -> Self {
    var configuration = configuration
    configuration.hysteresis = max(length, 0)
    return configured(configuration: configuration)
  }

  func moreMenuStyle<Style: MenuStyle>(
    _ style: Style,
  ) -> AdaptiveToolbar<Content, MoreContent, MoreLabel, Style, MoreButtonStyleModifier> {
    AdaptiveToolbar<Content, MoreContent, MoreLabel, Style, MoreButtonStyleModifier>(
      configuration: configuration,
      content: content,
      moreContent: moreContent,
      moreLabel: moreLabel,
      moreMenuStyle: style,
      moreButtonStyleModifier: moreButtonStyleModifier,
    )
  }

  func moreButtonStyle<Style: ButtonStyle>(
    _ style: Style,
  ) -> AdaptiveToolbar<
    Content,
    MoreContent,
    MoreLabel,
    MoreMenuStyle,
    AdaptiveToolbarButtonStyleModifier<Style>,
  > {
    configured(moreButtonStyleModifier: AdaptiveToolbarButtonStyleModifier(style: style))
  }

  func moreButtonStyle<Style: PrimitiveButtonStyle>(
    _ style: Style,
  ) -> AdaptiveToolbar<
    Content,
    MoreContent,
    MoreLabel,
    MoreMenuStyle,
    AdaptiveToolbarPrimitiveButtonStyleModifier<Style>,
  > {
    configured(moreButtonStyleModifier: AdaptiveToolbarPrimitiveButtonStyleModifier(style: style))
  }
}

// MARK: - Styles

private struct AdaptiveToolbarIconAndLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(spacing: 2) {
      configuration.icon

      configuration.title
        .font(.caption2)
        .lineLimit(1)
        .truncationMode(.tail)
    }
  }
}

// MARK: - Previews

#Preview("Adaptive Toolbar") {
  AdaptiveToolbarPreviewGallery()
    .padding(16)
    .frame(width: 820, height: 520)
}

#Preview("Vertical Overflow") {
  HStack(spacing: 32) {
    AdaptiveToolbar(.vertical, spacing: 4) {
      Button("Previous", systemImage: "chevron.up") {}
      Button("Fit", systemImage: "arrow.up.left.and.arrow.down.right") {}
      Button("Next", systemImage: "chevron.down") {}
    }
    .overflowFrom(.top)
    .frame(width: 32, height: 48)

    AdaptiveToolbar(.vertical, spacing: 4) {
      Button("Previous", systemImage: "chevron.up") {}
      Button("Fit", systemImage: "arrow.up.left.and.arrow.down.right") {}
      Button("Next", systemImage: "chevron.down") {}
    }
    .overflowFrom(.bottom)
    .frame(width: 32, height: 48)
  }
  .padding(20)
  .frame(width: 180, height: 140)
}

#Preview("Intrinsic Sizing") {
  HStack(spacing: 6) {
    Text(verbatim: "A file name that should use the available title space.png")
      .lineLimit(1)
      .truncationMode(.tail)
      .frame(minWidth: 72, maxWidth: 320, alignment: .leading)
      .layoutPriority(-1)
      .background(.blue.opacity(0.2))

    AdaptiveToolbar(spacing: 6) {
      Button("Previous", systemImage: "chevron.left") {}
      Button("Fit", systemImage: "arrow.up.left.and.arrow.down.right") {}
      Button("Info", systemImage: "info.circle") {}
      Button("Next", systemImage: "chevron.right") {}
    }
    .background(.orange.opacity(0.2))
  }
  .padding(16)
  .frame(width: 620, height: 64)
}

private struct AdaptiveToolbarPreviewGallery: View {
  @State private var usesLongLabels = false
  @State private var isPopoverPresented = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      previewRow("Wide", width: 620, edge: .right)
      previewRow("Medium", width: 250, edge: .right)
      previewRow("Narrow, left edge", width: 140, edge: .left)

      HStack(alignment: .top, spacing: 32) {
        previewColumn("Top", edge: .top)
        previewColumn("Bottom", edge: .bottom)

        AdaptiveToolbar {
          previewButton("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
          Button("Info", systemImage: "info.circle") {
            isPopoverPresented.toggle()
          }
          .popover(isPresented: $isPopoverPresented, arrowEdge: .top) {
            Text(verbatim: "Popover anchor")
              .padding()
          }
          .adaptiveToolbarBehavior(.alwaysVisible)
        } more: {
          Menu {
            Button {} label: { Text(verbatim: "PNG") }
            Button {} label: { Text(verbatim: "JPEG") }
          } label: {
            Text(verbatim: "Export")
          }
        } moreLabel: {
          Label {
            Text(verbatim: "Actions")
          } icon: {
            Image(systemName: "ellipsis.circle")
          }
          .font(.system(size: 11, weight: .medium))
          .frame(minWidth: 28, minHeight: 24)
        }
        .moreVisibility(.always)
        .labelMode(.iconAndLabel)
        .moreMenuStyle(.button)
        .moreButtonStyle(.automatic)
        .frame(width: 180, height: 52)
      }

      Toggle(isOn: $usesLongLabels) {
        Text(verbatim: "Long labels")
      }
      .labelsHidden()
    }
  }

  private func previewRow(
    _ title: String,
    width: CGFloat,
    edge: AdaptiveToolbarOverflowEdge,
  ) -> some View {
    HStack {
      Text(title)
        .frame(width: 100, alignment: .leading)

      AdaptiveToolbar {
        previewButton("Previous", systemImage: "chevron.left")
          .adaptiveToolbarGroup("navigation")
        Text(verbatim: "2 / 12")
          .adaptiveToolbarGroup("navigation")
        previewButton("Next", systemImage: "chevron.right")
          .adaptiveToolbarGroup("navigation")
        previewButton("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
          .adaptiveToolbarPriority(100)
        previewButton(usesLongLabels ? "Image information" : "Info", systemImage: "info.circle")
          .adaptiveToolbarBehavior(.alwaysVisible)
      }
      .overflowFrom(edge)
      .frame(width: width, height: 32)
      .border(.gray.opacity(0.35))
    }
  }

  private func previewColumn(
    _ title: String,
    edge: AdaptiveToolbarOverflowEdge,
  ) -> some View {
    VStack {
      Text(title)
      AdaptiveToolbar(.vertical, spacing: 4) {
        previewButton("Previous", systemImage: "chevron.up")
        previewButton("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
        previewButton("Next", systemImage: "chevron.down")
      }
      .overflowFrom(edge)
      .frame(width: 32, height: 48)
      .border(.gray.opacity(0.35))
    }
  }

  private func previewButton(_ title: String, systemImage: String) -> some View {
    Button(title, systemImage: systemImage) {}
  }
}
