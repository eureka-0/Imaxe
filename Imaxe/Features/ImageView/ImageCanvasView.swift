//
//  ImageCanvasView.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/20.
//

import AppKit
import PocketSVG

final class ImageCanvasView: NSView {
  var loadedImage: LoadedImage {
    didSet {
      if oldValue.image !== loadedImage.image {
        stopGIFAnimation()
        currentGIFFrame = 0
      }
      frame.size = loadedImage.displaySize
      needsDisplay = true
    }
  }

  var scale: CGFloat
  private var gifTimer: Timer?
  private var gifBitmapRep: NSBitmapImageRep?
  private var currentGIFFrame = 0

  override var isFlipped: Bool {
    true
  }

  init(loadedImage: LoadedImage, scale: CGFloat) {
    self.loadedImage = loadedImage
    self.scale = scale
    super.init(frame: NSRect(origin: .zero, size: loadedImage.displaySize))
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    nil
  }

  deinit {
    MainActor.assumeIsolated {
      gifTimer?.invalidate()
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()

    if window == nil {
      stopGIFAnimation()
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

    if let vectorContent = loadedImage.vectorContent {
      stopGIFAnimation()
      drawSVG(vectorContent, in: currentContext.cgContext)
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
    switch loadedImage.kind {
    case .bitmap:
      scale > 1.0 ? .none : .high
    case .vector:
      .high
    }
  }

  private var cgInterpolationQuality: CGInterpolationQuality {
    switch loadedImage.kind {
    case .bitmap:
      scale > 1.0 ? .none : .high
    case .vector:
      .high
    }
  }

  private func drawSVG(_ vectorContent: SVGVectorContent, in context: CGContext) {
    NSGraphicsContext.saveGraphicsState()
    context.setShouldAntialias(false)
    context.clip(to: bounds)

    let viewBox = vectorContent.viewBox
    context.scaleBy(
      x: bounds.width / viewBox.width,
      y: bounds.height / viewBox.height,
    )
    context.translateBy(x: -viewBox.minX, y: -viewBox.minY)

    for path in vectorContent.paths {
      drawSVGPath(path)
    }

    NSGraphicsContext.restoreGraphicsState()
  }

  private func drawSVGPath(_ path: SVGBezierPath) {
    let fillColor = cgColor(from: path.svgAttributes["fill"]) ?? NSColor.black.cgColor
    if fillColor.alpha > 0 {
      NSColor(cgColor: fillColor)?.setFill()
      path.fill()
    }

    if let strokeColor = cgColor(from: path.svgAttributes["stroke"]),
       strokeColor.alpha > 0
    {
      NSColor(cgColor: strokeColor)?.setStroke()
      path.stroke()
    }
  }

  private func cgColor(from value: Any?) -> CGColor? {
    guard let value else { return nil }

    let object = value as AnyObject
    guard CFGetTypeID(object) == CGColor.typeID else { return nil }
    return (object as! CGColor)
  }

  private func drawNSImage(hints: [NSImageRep.HintKey: Any]?) {
    loadedImage.image.draw(
      in: bounds,
      from: NSRect(origin: .zero, size: loadedImage.image.size),
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
    loadedImage.image.representations
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
