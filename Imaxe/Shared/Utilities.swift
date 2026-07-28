// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Functions

func fileSizeDescription(for fileSize: Int) -> String {
  ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
}

struct ImageWindowRequest: Codable, Hashable {
  let url: URL
  let addsToRecent: Bool
  let recentImagePath: String?
  let temporaryURL: URL?

  init(
    url: URL,
    addsToRecent: Bool = true,
    recentImagePath: String? = nil,
    temporaryURL: URL? = nil,
  ) {
    self.url = url
    self.addsToRecent = addsToRecent
    self.recentImagePath = recentImagePath
    self.temporaryURL = temporaryURL
  }
}

enum PasteboardImage {
  case existingFile(URL)
  case temporaryFile(URL)

  var url: URL {
    switch self {
    case let .existingFile(url), let .temporaryFile(url):
      url
    }
  }

  var temporaryURL: URL? {
    guard case let .temporaryFile(url) = self else { return nil }
    return url
  }
}

func extractImageFromPasteboard() throws -> PasteboardImage? {
  let pasteboard = NSPasteboard.general
  if let imageType = pasteboard.availableType(from: [.fileURL, .URL, .png, .tiff]) {
    switch imageType {
    case .fileURL:
      if let url = pasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true],
      )?.first as? URL {
        return .existingFile(url)
      }
    case .URL:
      if let urlString = pasteboard.string(forType: .URL), let url = URL(string: urlString) {
        return .existingFile(url)
      }
    case .png, .tiff:
      if let data = pasteboard.data(forType: imageType) {
        let tempFileURL = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
          .appendingPathExtension(imageType == .png ? "png" : "tiff")
        do {
          try data.write(to: tempFileURL, options: .atomic)
          return .temporaryFile(tempFileURL)
        } catch {
          try? FileManager.default.removeItem(at: tempFileURL)
          throw error
        }
      }
    default:
      break
    }
  }
  return nil
}

// MARK: - IntSize

nonisolated struct IntSize: Hashable, Sendable {
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
      appLog("NSSize \(nsSize) is not approximately integer.", category: .general)
    }

    width = Int(nsSize.width.rounded())
    height = Int(nsSize.height.rounded())
  }
}

// MARK: - Bundle extensions

nonisolated extension Bundle {
  var identifier: String {
    bundleIdentifier ?? "com.imaxe.Imaxe"
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
    RelativeDateFormatter.shared.localizedString(for: self, relativeTo: .now)
  }
}

private enum RelativeDateFormatter {
  static let shared: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter
  }()
}

// MARK: - FileManager extensions.

nonisolated extension FileManager {
  func ensureExists(for url: URL, isDirectory: Bool = true) throws {
    if isDirectory {
      try createDirectory(
        at: url,
        withIntermediateDirectories: true,
        attributes: nil,
      )
    } else {
      if !fileExists(atPath: url.filePath) {
        createFile(atPath: url.filePath, contents: nil, attributes: nil)
      }
    }
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

// MARK: - NSEvent extensions.

extension NSEvent {
  static var leftMousePressed: Bool {
    (NSEvent.pressedMouseButtons & 1 << 0) != 0
  }

  static var rightMousePressed: Bool {
    (NSEvent.pressedMouseButtons & 1 << 1) != 0
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

  nonisolated var animatedGIFRepresentation: NSBitmapImageRep? {
    representations
      .compactMap { $0 as? NSBitmapImageRep }
      .first { bitmapRep in
        let frameCount = bitmapRep.gifFrameCount ?? 0
        return frameCount > 1
      }
  }
}

extension NSBitmapImageRep {
  nonisolated var gifFrameCount: Int? {
    (value(forProperty: .frameCount) as? NSNumber)?.intValue
  }

  nonisolated var currentGIFFrame: Int? {
    (value(forProperty: .currentFrame) as? NSNumber)?.intValue
  }

  nonisolated func currentGIFFrameDuration(fallback: Double = 0.1) -> Double {
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
  static func bestMatch(for frame: NSRect) -> NSScreen? {
    let frameCenter = NSPoint(x: frame.midX, y: frame.midY)
    if let containingScreen = screens.first(where: { $0.frame.contains(frameCenter) }) {
      return containingScreen
    }

    return screens.max { first, second in
      first.frame.intersection(frame).area < second.frame.intersection(frame).area
    }
  }

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

private extension NSRect {
  var area: CGFloat {
    guard !isNull, !isEmpty else { return 0 }
    return width * height
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

  /// Determines if the window is attached to another window (e.g., as a child, sheet, or popover).
  func isAttachedTo(_ otherWindow: NSWindow) -> Bool {
    if self === otherWindow {
      return true
    }
    guard let parent else { return false }
    if parent === otherWindow {
      return true
    }
    return parent.isAttachedTo(otherWindow)
  }

  enum FocusedTextViewSearchScope {
    case currentWindow
    case currentWindowAndChildWindows
    case windowTree
  }

  /// Finds the first focused NSTextView in the window's responder chain or its child windows.
  /// - Parameters:
  ///   - scope: The scope of the search.
  ///   - isEditable: An optional filter for whether the NSTextView should be editable. If nil, any
  /// NSTextView will be returned.
  /// - Returns: The focused NSTextView if found; otherwise, nil.
  func focusedTextView(
    scope: FocusedTextViewSearchScope = .currentWindow,
    isEditable: Bool? = true,
  ) -> NSTextView? {
    if let textView = firstResponder as? NSTextView,
       isEditable == nil || textView.isEditable == isEditable
    {
      return textView
    }

    var rootWindow = self

    switch scope {
    case .currentWindow:
      return nil
    case .currentWindowAndChildWindows:
      break
    case .windowTree:
      while let parent = rootWindow.parent {
        rootWindow = parent
      }
    }

    for childWindow in rootWindow.childWindows ?? [] {
      if let textView = childWindow.focusedTextView(
        scope: .currentWindowAndChildWindows,
        isEditable: isEditable,
      ) {
        return textView
      }
    }
    return nil
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

    return Self.applicationSupportDirectory.appendingPathComponent(
      directoryName,
      isDirectory: true,
    )
  }

  static var appCachesDirectory: URL {
    cachesDirectory.appendingPathComponent("com.imaxe.Imaxe", isDirectory: true)
  }

  static var thumbnailCachesDirectory: URL {
    appCachesDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
  }

  var utType: UTType? {
    guard isFileURL else { return nil }

    return UTType(filenameExtension: pathExtension)
  }

  var freshFileURL: URL {
    guard isFileURL else { return self }

    return URL(fileURLWithPath: filePath, isDirectory: hasDirectoryPath)
  }

  /// Returns the file path without percent encoding.
  var filePath: String {
    if isFileURL {
      return standardizedFileURL.path(percentEncoded: false)
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
