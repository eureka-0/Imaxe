// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import AppKit

final class ImageCanvasView: NSView {
  var document: ImageDocument {
    didSet {
      if oldValue.id != document.id {
        resetGIFAnimation()
      }
      updateCanvasSize()
      updateAccessibility()
      needsDisplay = true
    }
  }

  private var lastBackingScale: CGFloat = 2.0
  private var gifTimer: Timer?
  private var gifBitmapRep: NSBitmapImageRep?
  private var gifImage: NSImage?
  private var currentGIFFrame = 0
  private var userDefaultsObservers: [NSKeyValueObservation] = []
  private var appObservers: [NSObjectProtocol] = []
  private var windowObservers: [NSObjectProtocol] = []
  private var accessibilityObserver: NSObjectProtocol?

  private var imageActualSizeStrategy: ImageActualSizeStrategy {
    UserDefaults.standard.imageActualSizeStrategyValue
  }

  private var imageInterpolationStrategy: ImageInterpolationStrategy {
    UserDefaults.standard.imageInterpolationStrategyValue
  }

  override var isFlipped: Bool {
    true
  }

  init(document: ImageDocument) {
    self.document = document
    super.init(frame: NSRect())
    updateCanvasSize()
    setupObservation()
    setupAnimationObservation()
    updateAccessibility()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    nil
  }

  private func setupObservation() {
    let actualSizeObservation = UserDefaults.standard.observe(
      \.imageActualSizeStrategy,
      options: [.initial, .new],
    ) { [weak self] _, _ in
      guard let self else { return }

      DispatchQueue.main.async {
        self.updateCanvasSize()
        self.needsDisplay = true
      }
    }

    let interpolationObservation = UserDefaults.standard.observe(
      \.imageInterpolationStrategy,
      options: [.initial, .new],
    ) { [weak self] _, _ in
      guard let self else { return }

      DispatchQueue.main.async {
        self.needsDisplay = true
      }
    }

    userDefaultsObservers = [actualSizeObservation, interpolationObservation]
  }

  private func setupAnimationObservation() {
    let notificationCenter = NotificationCenter.default
    appObservers = [
      notificationCenter.addObserver(
        forName: NSApplication.didBecomeActiveNotification,
        object: NSApp,
        queue: .main,
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.updateGIFAnimationPlayback()
        }
      },
      notificationCenter.addObserver(
        forName: NSApplication.didResignActiveNotification,
        object: NSApp,
        queue: .main,
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.updateGIFAnimationPlayback()
        }
      },
    ]

    accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: NSWorkspace.shared,
      queue: .main,
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.updateGIFAnimationPlayback()
      }
    }
  }

  deinit {
    userDefaultsObservers.forEach { $0.invalidate() }
    MainActor.assumeIsolated {
      appObservers.forEach(NotificationCenter.default.removeObserver)
      windowObservers.forEach(NotificationCenter.default.removeObserver)
      if let accessibilityObserver {
        NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
      }
      gifTimer?.invalidate()
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()

    windowObservers.forEach(NotificationCenter.default.removeObserver)
    windowObservers = []
    if let window {
      let notificationCenter = NotificationCenter.default
      windowObservers = [
        notificationCenter.addObserver(
          forName: NSWindow.didChangeOcclusionStateNotification,
          object: window,
          queue: .main,
        ) { [weak self] _ in
          Task { @MainActor [weak self] in
            self?.updateGIFAnimationPlayback()
          }
        },
        notificationCenter.addObserver(
          forName: NSWindow.didMiniaturizeNotification,
          object: window,
          queue: .main,
        ) { [weak self] _ in
          Task { @MainActor [weak self] in
            self?.updateGIFAnimationPlayback()
          }
        },
        notificationCenter.addObserver(
          forName: NSWindow.didDeminiaturizeNotification,
          object: window,
          queue: .main,
        ) { [weak self] _ in
          Task { @MainActor [weak self] in
            self?.updateGIFAnimationPlayback()
          }
        },
      ]
      updateCanvasSize()
    }
    updateGIFAnimationPlayback()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()

    let currentBackingScale = window?.backingScaleFactor ?? 2.0
    if currentBackingScale != lastBackingScale {
      lastBackingScale = currentBackingScale
      updateCanvasSize()
    }
  }

  /// Updates the canvas size based on the current image actual size strategy and the loaded image's
  /// properties.
  private func updateCanvasSize() {
    let pixelSize = document.pixelSize

    switch imageActualSizeStrategy {
    case .pixelSize:
      let pointSize = window?.convertFromBacking(pixelSize) ?? pixelSize
      guard pointSize.width > 0, pointSize.height > 0, frame.size != pointSize else { return }
      frame.size = pointSize
    case .pointSize:
      guard frame.size != pixelSize else { return }
      frame.size = pixelSize
    case .printSize:
      let inchesSize = CGSize(
        width: pixelSize.width / CGFloat(document.metadata.DPI.width),
        height: pixelSize.height / CGFloat(document.metadata.DPI.height),
      )
      let ppi = window?.screen?.getPPI() ?? Constants.fallbackScreenPPI
      let screenPixelSize = CGSize(
        width: inchesSize.width * ppi.width,
        height: inchesSize.height * ppi.height,
      )
      let pointSize = window?.convertFromBacking(screenPixelSize) ?? screenPixelSize
      guard pointSize.width > 0, pointSize.height > 0, frame.size != pointSize else { return }
      frame.size = pointSize
    }
  }

  private var imageInterpolation: NSImageInterpolation {
    switch imageInterpolationStrategy {
    case .none: .none
    case .low: .low
    case .medium: .medium
    case .high: .high
    }
  }

  private var cgInterpolationQuality: CGInterpolationQuality {
    switch imageInterpolationStrategy {
    case .none: .none
    case .low: .low
    case .medium: .medium
    case .high: .high
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.clear.setFill()
    dirtyRect.fill()

    guard let currentContext = NSGraphicsContext.current else {
      updateGIFAnimationPlayback()
      drawNSImage(hints: nil)
      return
    }

    let previousInterpolation = currentContext.imageInterpolation
    let interpolation = imageInterpolation
    let hints: [NSImageRep.HintKey: Any] = [
      .interpolation: NSNumber(value: interpolation.rawValue),
    ]

    NSGraphicsContext.saveGraphicsState()
    currentContext.imageInterpolation = interpolation
    currentContext.cgContext.setShouldAntialias(false)
    currentContext.cgContext.interpolationQuality = cgInterpolationQuality
    updateGIFAnimationPlayback()
    drawNSImage(hints: hints)
    NSGraphicsContext.restoreGraphicsState()
    currentContext.imageInterpolation = previousInterpolation
  }

  private func drawNSImage(hints: [NSImageRep.HintKey: Any]?) {
    let image = gifImage ?? document.nsImage
    image.draw(
      in: bounds,
      from: NSRect(origin: .zero, size: image.size),
      operation: .copy,
      fraction: 1.0,
      respectFlipped: true,
      hints: hints,
    )
  }

  private var isGIFAnimationPlaybackEligible: Bool {
    guard let window else { return false }

    return NSApp.isActive
      && window.isVisible
      && window.occlusionState.contains(.visible)
      && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  private func updateGIFAnimationPlayback() {
    guard isGIFAnimationPlaybackEligible else {
      pauseGIFAnimation()
      return
    }

    guard gifTimer == nil else { return }
    guard let bitmapRep = prepareGIFRepresentationIfNeeded() else {
      resetGIFAnimation()
      return
    }

    scheduleNextGIFFrame(for: bitmapRep)
  }

  private func prepareGIFRepresentationIfNeeded() -> NSBitmapImageRep? {
    if let gifBitmapRep {
      return gifBitmapRep
    }

    guard let bitmapRep = document.makeAnimatedBitmapRepresentation() else { return nil }

    let image = NSImage(size: document.nsImage.size)
    image.cacheMode = document.nsImage.cacheMode
    image.addRepresentation(bitmapRep)
    gifBitmapRep = bitmapRep
    gifImage = image
    currentGIFFrame = bitmapRep.currentGIFFrame ?? 0
    return bitmapRep
  }

  private func pauseGIFAnimation() {
    gifTimer?.invalidate()
    gifTimer = nil
  }

  private func resetGIFAnimation() {
    pauseGIFAnimation()
    gifBitmapRep = nil
    gifImage = nil
    currentGIFFrame = 0
  }

  private func scheduleNextGIFFrame(for bitmapRep: NSBitmapImageRep) {
    guard let frameCount = bitmapRep.gifFrameCount,
          frameCount > 1
    else {
      resetGIFAnimation()
      return
    }

    gifTimer?.invalidate()
    let timer = Timer(
      timeInterval: bitmapRep.currentGIFFrameDuration(),
      target: self,
      selector: #selector(advanceGIFFrame(_:)),
      userInfo: nil,
      repeats: false,
    )

    gifTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  @objc private func advanceGIFFrame(_: Timer) {
    guard isGIFAnimationPlaybackEligible else {
      pauseGIFAnimation()
      return
    }
    guard let bitmapRep = gifBitmapRep else { return }
    guard let frameCount = bitmapRep.gifFrameCount,
          frameCount > 1
    else {
      resetGIFAnimation()
      return
    }

    currentGIFFrame = (currentGIFFrame + 1) % frameCount
    bitmapRep.setProperty(.currentFrame, withValue: currentGIFFrame)
    needsDisplay = true

    scheduleNextGIFFrame(for: bitmapRep)
  }

  private func updateAccessibility() {
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    setAccessibilityLabel(document.metadata.fileName)
  }
}
