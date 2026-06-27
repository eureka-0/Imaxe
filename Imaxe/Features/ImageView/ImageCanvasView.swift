//
//  ImageCanvasView.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/20.
//

import AppKit

final class ImageCanvasView: NSView {
  var imageContainer: ImageContainer {
    didSet {
      if oldValue.nsImage !== imageContainer.nsImage {
        stopGIFAnimation()
        currentGIFFrame = 0
      }
      updateCanvasSize()
      needsDisplay = true
    }
  }

  var imageInfo: ImageInfo {
    didSet {
      updateCanvasSize()
      needsDisplay = true
    }
  }

  var scale: CGFloat {
    didSet {
      if oldValue != scale, (oldValue - 1) * (scale - 1) <= 0 {
        needsDisplay = true
      }
    }
  }

  private var lastBackingScale: CGFloat = 2.0
  private var gifTimer: Timer?
  private var gifBitmapRep: NSBitmapImageRep?
  private var currentGIFFrame = 0
  private var userDefaultsObservation: NSKeyValueObservation?

  private var imageActualSizeStrategy: ImageActualSizeStrategy {
    UserDefaults.standard.imageActualSizeStrategyValue
  }

  override var isFlipped: Bool {
    true
  }

  init(imageContainer: ImageContainer, imageInfo: ImageInfo, scale: CGFloat) {
    self.imageContainer = imageContainer
    self.imageInfo = imageInfo
    self.scale = scale
    super.init(frame: NSRect())
    updateCanvasSize()
    setupObservation()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    nil
  }

  private func setupObservation() {
    userDefaultsObservation = UserDefaults.standard.observe(
      \.imageActualSizeStrategy, options: [.initial, .new],
    ) { [weak self] _, _ in
      guard let self else { return }

      DispatchQueue.main.async {
        self.updateCanvasSize()
        self.needsDisplay = true
      }
    }
  }

  deinit {
    userDefaultsObservation?.invalidate()
    MainActor.assumeIsolated {
      gifTimer?.invalidate()
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()

    if window == nil {
      stopGIFAnimation()
    } else {
      updateCanvasSize()
    }
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
    let pixelSize = imageContainer.pixelSize

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
        width: pixelSize.width / CGFloat(imageInfo.DPI.width),
        height: pixelSize.height / CGFloat(imageInfo.DPI.height),
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

  override func draw(_ dirtyRect: NSRect) {
    NSColor.clear.setFill()
    dirtyRect.fill()

    guard let currentContext = NSGraphicsContext.current else {
      startGIFAnimationIfNeeded()
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
    startGIFAnimationIfNeeded()
    drawNSImage(hints: hints)
    NSGraphicsContext.restoreGraphicsState()
    currentContext.imageInterpolation = previousInterpolation
  }

  private var imageInterpolation: NSImageInterpolation {
    scale > 1.0 ? .none : .high
  }

  private var cgInterpolationQuality: CGInterpolationQuality {
    scale > 1.0 ? .none : .high
  }

  private func drawNSImage(hints: [NSImageRep.HintKey: Any]?) {
    imageContainer.nsImage.draw(
      in: bounds,
      from: NSRect(origin: .zero, size: imageContainer.nsImage.size),
      operation: .copy,
      fraction: 1.0,
      respectFlipped: true,
      hints: hints,
    )
  }

  private func startGIFAnimationIfNeeded() {
    guard window != nil, gifTimer == nil else { return }

    guard let bitmapRep = animatedGIFRepresentation else {
      stopGIFAnimation()
      return
    }

    gifBitmapRep = bitmapRep
    currentGIFFrame = (bitmapRep.value(forProperty: .currentFrame) as? NSNumber)?.intValue ?? 0
    scheduleNextGIFFrame(for: bitmapRep)
  }

  private func stopGIFAnimation() {
    gifTimer?.invalidate()
    gifTimer = nil
    gifBitmapRep = nil
  }

  private var animatedGIFRepresentation: NSBitmapImageRep? {
    imageContainer.nsImage.representations
      .compactMap { $0 as? NSBitmapImageRep }
      .first { bitmapRep in
        let frameCount = (bitmapRep.value(forProperty: .frameCount) as? NSNumber)?.intValue ?? 0
        return frameCount > 1
      }
  }

  private func scheduleNextGIFFrame(for bitmapRep: NSBitmapImageRep) {
    guard let frameCount = (bitmapRep.value(forProperty: .frameCount) as? NSNumber)?.intValue,
          frameCount > 1
    else {
      stopGIFAnimation()
      return
    }

    let duration = (bitmapRep.value(forProperty: .currentFrameDuration) as? NSNumber)?.doubleValue
    let frameDuration = if let duration, duration > 0 {
      duration
    } else {
      0.1
    }

    gifTimer?.invalidate()
    let timer = Timer(
      timeInterval: frameDuration,
      target: self,
      selector: #selector(advanceGIFFrame(_:)),
      userInfo: nil,
      repeats: false,
    )

    gifTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  @objc private func advanceGIFFrame(_: Timer) {
    guard let bitmapRep = gifBitmapRep else { return }
    guard let frameCount = (bitmapRep.value(forProperty: .frameCount) as? NSNumber)?.intValue,
          frameCount > 1
    else {
      stopGIFAnimation()
      return
    }

    currentGIFFrame = (currentGIFFrame + 1) % frameCount
    bitmapRep.setProperty(.currentFrame, withValue: currentGIFFrame)
    needsDisplay = true

    scheduleNextGIFFrame(for: bitmapRep)
  }
}
