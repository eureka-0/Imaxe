//
//  Utilities.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/18.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Functions

func fileSizeDescription(for fileSize: Int) -> String {
  ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
}

// MARK: - IntSize

nonisolated struct IntSize: Hashable {
  let width: Int
  let height: Int

  var isValid: Bool {
    width > 0 && height > 0
  }

  var nsSize: NSSize {
    NSSize(width: width, height: height)
  }

  init(width: Int = 0, height: Int = 0) {
    self.width = width
    self.height = height
  }

  init(nsSize: NSSize) {
    if !nsSize.isApproximatelyInt {
      debugPrint("Warning: NSSize \(nsSize) is not approximately integer.")
    }

    width = Int(nsSize.width.rounded())
    height = Int(nsSize.height.rounded())
  }
}

// MARK: - Color extensions.

extension Color {
  init(hex: String) {
    let (r, g, b, a) = rgbaValueFromHex(hex)
    self.init(red: r, green: g, blue: b, opacity: a)
  }

  var hex: String {
    guard let cgColor, let color = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else {
      return "#00000000"
    }

    return hexStringFromRGBA(
      red: color.redComponent,
      green: color.greenComponent,
      blue: color.blueComponent,
      alpha: color.alphaComponent,
    )
  }

  /// Creates a context-dependent color with different values for light and dark appearances.
  /// - Parameters:
  ///   - light: The light appearance color value.
  ///   - dark: The dark appearance color value.
  init(light: @escaping @autoclosure () -> Color, dark: @escaping @autoclosure () -> Color) {
    #if os(watchOS)
      self = dark()
    #elseif canImport(UIKit)
      self.init(
        uiColor: .init { traitCollection in
          switch traitCollection.userInterfaceStyle {
          case .unspecified, .light:
            return UIColor(light())
          case .dark:
            return UIColor(dark())
          @unknown default:
            return UIColor(light())
          }
        },
      )
    #elseif canImport(AppKit)
      self.init(
        nsColor: .init(name: nil) { appearance in
          if appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua {
            NSColor(light())
          } else {
            NSColor(dark())
          }
        },
      )
    #endif
  }
}

extension NSColor {
  convenience init(hex: String) {
    let (r, g, b, a) = rgbaValueFromHex(hex)
    self.init(red: r, green: g, blue: b, alpha: a)
  }
}

extension ShapeStyle where Self == Color {
  static var windowBackground: Color {
    Color(nsColor: .windowBackgroundColor)
  }

  static var controlBackground: Color {
    Color(
      light: Color(white: 0.9),
      dark: Color(nsColor: .controlBackgroundColor),
    )
  }

  static var controlAccent: Color {
    Color(nsColor: .controlAccentColor)
  }

  static var selectedControl: Color {
    Color(nsColor: .selectedControlColor)
  }

  static var controlText: Color {
    Color(nsColor: .controlTextColor)
  }

  static var keyboardFocusIndicator: Color {
    Color(nsColor: .keyboardFocusIndicatorColor)
  }

  static var separator: Color {
    Color(nsColor: .separatorColor)
  }

  static var textBackground: Color {
    Color(nsColor: .textBackgroundColor)
  }
}

private func rgbaByte(_ component: CGFloat) -> Int {
  Int((component.clamped(to: 0 ... 1) * 255).rounded())
}

private func hexStringFromRGBA(
  red: CGFloat,
  green: CGFloat,
  blue: CGFloat,
  alpha: CGFloat,
) -> String {
  String(
    format: "#%02X%02X%02X%02X",
    rgbaByte(red),
    rgbaByte(green),
    rgbaByte(blue),
    rgbaByte(alpha),
  )
}

private func rgbaValueFromHex(_ hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
  var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
  hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "").uppercased()
  if hexSanitized.count == 6 {
    hexSanitized += "FF"
  }
  if hexSanitized.count != 8 {
    return (0, 0, 0, 0)
  }

  var rgba: UInt64 = 0
  Scanner(string: hexSanitized).scanHexInt64(&rgba)

  let r = CGFloat((rgba & 0xFF00_0000) >> 24) / 255.0
  let g = CGFloat((rgba & 0x00FF_0000) >> 16) / 255.0
  let b = CGFloat((rgba & 0x0000_FF00) >> 8) / 255.0
  let a = CGFloat(rgba & 0x0000_00FF) / 255.0

  return (r, g, b, a)
}

// MARK: - Comparable extensions.

extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}

// MARK: - Date extensions.

extension Date {
  var relativeDateDescription: String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: self, relativeTo: .now)
  }
}

// MARK: - FileManager extensions.

nonisolated extension FileManager {
  func ensureExists(for directoryURL: URL) throws {
    try createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true,
      attributes: nil,
    )
  }
}

// MARK: - NSApplication extensions.

extension NSApplication {
  var appIcon: NSImage {
    if let icon = applicationIconImage {
      return icon
    }

    guard let bundleIcons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
          let primaryIcon = bundleIcons["CFBundlePrimaryIcon"] as? [String: Any],
          let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
          let iconName = iconFiles.last
    else {
      return NSImage()
    }
    return NSImage(named: iconName) ?? NSImage()
  }
}

// MARK: - NSImage extensions.

extension NSImage {
  nonisolated var pixelSize: NSSize {
    var pixelSize = NSSize.zero
    for representation in representations {
      pixelSize.width = max(pixelSize.width, CGFloat(representation.pixelsWide))
      pixelSize.height = max(pixelSize.height, CGFloat(representation.pixelsHigh))
    }

    if pixelSize.width > 0, pixelSize.height > 0 {
      return pixelSize
    }

    return size.validSize
  }

  nonisolated func pixelSize(preferred preferredSize: NSSize?) -> NSSize {
    if let preferredSize, preferredSize.width > 0, preferredSize.height > 0 {
      return preferredSize
    }

    return pixelSize
  }

  var animatedGIFRepresentation: NSBitmapImageRep? {
    representations
      .compactMap { $0 as? NSBitmapImageRep }
      .first { bitmapRep in
        let frameCount = bitmapRep.gifFrameCount ?? 0
        return frameCount > 1
      }
  }
}

extension NSBitmapImageRep {
  var gifFrameCount: Int? {
    (value(forProperty: .frameCount) as? NSNumber)?.intValue
  }

  var currentGIFFrame: Int? {
    (value(forProperty: .currentFrame) as? NSNumber)?.intValue
  }

  func currentGIFFrameDuration(fallback: Double = 0.1) -> Double {
    let duration = (value(forProperty: .currentFrameDuration) as? NSNumber)?.doubleValue
    if let duration, duration > 0 {
      return duration
    } else {
      return fallback
    }
  }
}

// MARK: - NSRect extensions.

extension NSRect {
  func constrained(to visibleFrame: NSRect) -> NSRect {
    var rect = self
    rect.size.width = min(rect.width, visibleFrame.width)
    rect.size.height = min(rect.height, visibleFrame.height)

    if rect.maxX > visibleFrame.maxX {
      rect.origin.x = visibleFrame.maxX - rect.width
    }
    if rect.minX < visibleFrame.minX {
      rect.origin.x = visibleFrame.minX
    }
    if rect.maxY > visibleFrame.maxY {
      rect.origin.y = visibleFrame.maxY - rect.height
    }
    if rect.minY < visibleFrame.minY {
      rect.origin.y = visibleFrame.minY
    }

    return rect
  }
}

// MARK: - NSScreen extensions.

extension NSScreen {
  func getPPI() -> (width: CGFloat, height: CGFloat)? {
    guard let displayID =
      deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    else {
      return nil
    }

    let physicalSize = CGDisplayScreenSize(displayID)
    let physicalSizeInInches = CGSize(
      width: physicalSize.width / 25.4,
      height: physicalSize.height / 25.4,
    )

    let ppiWidth = frame.width * backingScaleFactor / physicalSizeInInches.width
    let ppiHeight = frame.height * backingScaleFactor / physicalSizeInInches.height
    return (width: ppiWidth, height: ppiHeight)
  }
}

// MARK: - NSSize extensions.

extension NSSize {
  nonisolated var validSize: NSSize {
    if width > 0, height > 0 {
      self
    } else {
      NSSize(width: 1, height: 1)
    }
  }

  nonisolated var isApproximatelyInt: Bool {
    abs(width.rounded() - width) < 0.1 && abs(height.rounded() - height) < 0.1
  }

  nonisolated var intSize: IntSize {
    IntSize(nsSize: self)
  }

  func isApproximatelyEqual(to other: NSSize) -> Bool {
    abs(width - other.width) < 1.0 && abs(height - other.height) < 1.0
  }
}

// MARK: - NSWindow extensions.

extension NSWindow {
  var titlebarHeight: CGFloat {
    frame.height - contentLayoutRect.height
  }

  func resizeToDefaultSize() {
    setContentSize(NSSize(
      width: Constants.defaultWindowWidth,
      height: Constants.defaultWindowHeight - titlebarHeight,
    ))
  }

  func setStandardButtonsVisibility(to showWindowButtons: Bool) {
    standardWindowButton(.closeButton)?.isHidden = !showWindowButtons
    standardWindowButton(.miniaturizeButton)?.isHidden = !showWindowButtons
    standardWindowButton(.zoomButton)?.isHidden = !showWindowButtons
  }

  func convertFromBacking(_ size: CGSize) -> CGSize {
    convertFromBacking(NSRect(origin: .zero, size: size)).size
  }

  enum CenteringStrategy {
    case remain
    case centerOnScreen
    case custom(NSPoint)
  }

  func constrainedFrame(_ windowSize: NSSize, centeringStrategy: CenteringStrategy) -> NSRect {
    let clampedWindowSize = NSSize(
      width: max(windowSize.width, Constants.minimumWindowContentWidth),
      height: max(windowSize.height, Constants.minimumWindowContentHeight + titlebarHeight),
    )
    let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame

    var centerPoint = NSPoint(x: frame.midX, y: frame.midY)
    switch centeringStrategy {
    case .remain:
      break
    case .centerOnScreen:
      if let visibleFrame {
        centerPoint.x = visibleFrame.midX
        centerPoint.y = visibleFrame.midY
      }
    case let .custom(point):
      centerPoint = point
    }

    let frame = NSRect(
      x: centerPoint.x - clampedWindowSize.width / 2.0,
      y: centerPoint.y - clampedWindowSize.height / 2.0,
      width: clampedWindowSize.width,
      height: clampedWindowSize.height,
    )

    if let visibleFrame {
      return frame.constrained(to: visibleFrame)
    }

    return frame
  }
}

// MARK: - String extensions.

nonisolated extension String {
  static var defaultFuzzyMatchOptions: String.CompareOptions {
    [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
  }

  func fuzzyMatch(
    _ other: String,
    options: String.CompareOptions = String.defaultFuzzyMatchOptions,
    range searchRange: Range<String.Index>? = nil,
  ) -> Range<String.Index>? {
    let other = other.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !other.isEmpty else { return startIndex ..< startIndex }

    return range(of: other, options: options, range: searchRange, locale: .current)
  }

  func fuzzyContains(
    _ other: String,
    options: String.CompareOptions = String.defaultFuzzyMatchOptions,
    range searchRange: Range<String.Index>? = nil,
  ) -> Bool {
    fuzzyMatch(other, options: options, range: searchRange) != nil
  }
}

// MARK: - URL extensions.

nonisolated extension URL {
  static var dataDirectory: URL {
    #if DEBUG
      let directoryName = "Imaxe Debug"
    #else
      let directoryName = "Imaxe"
    #endif

    let url = Self.applicationSupportDirectory.appendingPathComponent(
      directoryName,
      isDirectory: true,
    )

    do {
      try FileManager.default.ensureExists(for: url)
    } catch {
      fatalError("Failed to create data directory: \(error)")
    }

    return url
  }

  static var appCachesDirectory: URL {
    let url = Self.cachesDirectory.appendingPathComponent("com.imaxe.Imaxe", isDirectory: true)

    do {
      try FileManager.default.ensureExists(for: url)
    } catch {
      fatalError("Failed to create caches directory: \(error)")
    }

    return url
  }

  static var thumbnailCachesDirectory: URL {
    let url = Self.appCachesDirectory.appendingPathComponent("Thumbnails", isDirectory: true)

    do {
      try FileManager.default.ensureExists(for: url)
    } catch {
      fatalError("Failed to create thumbnail cache directory: \(error)")
    }

    return url
  }

  /// Returns the file system path without percent encoding.
  var fileSystemPath: String {
    path(percentEncoded: false)
  }

  var utType: UTType? {
    guard isFileURL else { return nil }

    return UTType(filenameExtension: pathExtension)
  }

  var freshFileURL: URL {
    guard isFileURL else { return self }

    return URL(fileURLWithPath: fileSystemPath, isDirectory: hasDirectoryPath)
  }

  var filePath: String {
    if isFileURL {
      return standardizedFileURL.fileSystemPath
    }

    return absoluteString
  }

  func freshResourceValues(forKeys keys: Set<URLResourceKey>) throws -> URLResourceValues {
    try freshFileURL.resourceValues(forKeys: keys)
  }

  var isDirectory: Bool {
    (try? freshResourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
  }

  var fileExists: Bool {
    (try? freshFileURL.checkResourceIsReachable()) == true
  }

  var fileSize: Int {
    (try? freshResourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
  }

  var contentModificationDate: Date? {
    (try? freshResourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
  }
}

// MARK: - UserDefaults extensions.

extension UserDefaults {
  @objc dynamic var imageActualSizeStrategy: String? {
    string(forKey: AppSettings.Keys.imageActualSizeStrategy.rawValue)
  }

  @objc dynamic var imageInterpolationStrategy: String? {
    string(forKey: AppSettings.Keys.imageInterpolationStrategy.rawValue)
  }

  var imageActualSizeStrategyValue: ImageActualSizeStrategy {
    imageActualSizeStrategy.flatMap { ImageActualSizeStrategy(rawValue: $0) }
      ?? AppSettings.Defaults.imageActualSizeStrategy
  }

  var imageInterpolationStrategyValue: ImageInterpolationStrategy {
    imageInterpolationStrategy.flatMap { ImageInterpolationStrategy(rawValue: $0) }
      ?? AppSettings.Defaults.imageInterpolationStrategy
  }
}

// MARK: - View extensions.

extension View {
  func dismissTextFocusOnClickOutside() -> some View {
    background(DismissTextFocusOnClickOutside().frame(width: 0, height: 0))
  }

  func preservesTextFocusOnClick() -> some View {
    overlay {
      TextFocusPreservingArea()
        .allowsHitTesting(false)
    }
  }
}

extension NSView {
  var preservesTextFocus: Bool {
    if self is TextFocusPreservingView {
      return true
    }

    return superview?.preservesTextFocus ?? false
  }

  var isInsideTextInput: Bool {
    if self is NSTextField || self is NSTextView || self is NSSearchField {
      return true
    }

    return superview?.isInsideTextInput ?? false
  }

  func backingAlignedSize(
    _ size: NSSize,
    options: AlignmentOptions = [.alignAllEdgesNearest],
  ) -> NSSize {
    backingAlignedRect(NSRect(origin: .zero, size: size), options: options).size
  }

  func backingAlignedPoint(
    _ point: NSPoint,
    options: AlignmentOptions = [.alignAllEdgesNearest],
  ) -> NSPoint {
    backingAlignedRect(NSRect(origin: point, size: .zero), options: options).origin
  }
}

private struct DismissTextFocusOnClickOutside: NSViewRepresentable {
  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> NSView {
    let view = WindowTrackingView(frame: .zero)
    view.onWindowChange = { [weak coordinator = context.coordinator] window in
      coordinator?.trackedWindow = window
    }
    context.coordinator.install()
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.trackedWindow = nsView.window
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    if let view = nsView as? WindowTrackingView {
      view.onWindowChange = nil
    }
    coordinator.trackedWindow = nil
    coordinator.uninstall()
  }

  final class Coordinator {
    private var monitor: Any?
    weak var trackedWindow: NSWindow?

    func install() {
      guard monitor == nil else { return }

      monitor = NSEvent.addLocalMonitorForEvents(matching: [
        .leftMouseDown,
        .rightMouseDown,
      ]) { [weak self] event in
        guard
          let self,
          let window = event.window,
          window === trackedWindow,
          let contentView = window.contentView
        else {
          return event
        }

        let location = contentView.convert(event.locationInWindow, from: nil)
        if let hitView = contentView.hitTest(location),
           !TextFocusPreservingRegistry.shared.contains(event.locationInWindow, in: window),
           !hitView.preservesTextFocus,
           !hitView.isInsideTextInput
        {
          window.makeFirstResponder(nil)
        }

        return event
      }
    }

    func uninstall() {
      if let monitor {
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
      }
    }
  }
}

private final class WindowTrackingView: NSView {
  var onWindowChange: ((NSWindow?) -> Void)?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    onWindowChange?(window)
  }
}

private struct TextFocusPreservingArea: NSViewRepresentable {
  func makeNSView(context _: Context) -> NSView {
    let view = TextFocusPreservingView(frame: .zero)
    view.autoresizingMask = [.width, .height]
    return view
  }

  func updateNSView(_ nsView: NSView, context _: Context) {
    nsView.needsLayout = true
  }
}

private final class TextFocusPreservingView: NSView {
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    TextFocusPreservingRegistry.shared.register(self)
  }
}

private final class TextFocusPreservingRegistry {
  static let shared = TextFocusPreservingRegistry()

  private let views = NSHashTable<TextFocusPreservingView>.weakObjects()

  func register(_ view: TextFocusPreservingView) {
    views.add(view)
  }

  func contains(_ locationInWindow: NSPoint, in window: NSWindow) -> Bool {
    views.allObjects.contains { view in
      guard view.window === window else { return false }

      let locationInView = view.convert(locationInWindow, from: nil)
      return view.bounds.contains(locationInView)
    }
  }
}
