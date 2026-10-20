// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import AppKit
import ImageIO
@testable import Imaxe
import SwiftUI
import Testing

@MainActor
@Suite("Image View", .serialized)
struct ImageViewTests {
  @Test func `bitmap image document uses pixel size`() async throws {
    let url = URL.temporaryDirectory
      .appending(path: "imaxe-document-size-\(UUID().uuidString).png")
    try TestSupport.pngData(width: 10, height: 20).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let document = try await ImageLoader.shared.loadDocument(from: url)

    #expect(document.pixelSize == NSSize(width: 10, height: 20))
    #expect(document.nsImage.size == NSSize(width: 10, height: 20))
  }

  @Test func `canvas occupies image pixel size in backing pixels`() async throws {
    let defaults = UserDefaults.standard
    let key = AppSettings.Keys.imageActualSizeStrategy.rawValue
    let previousValue = defaults.object(forKey: key)
    defaults.set(ImageActualSizeStrategy.pixelSize.rawValue, forKey: key)
    defer {
      if let previousValue {
        defaults.set(previousValue, forKey: key)
      } else {
        defaults.removeObject(forKey: key)
      }
    }

    let url = URL.temporaryDirectory
      .appending(path: "imaxe-canvas-size-\(UUID().uuidString).png")
    try TestSupport.pngData(width: 10, height: 20).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let document = try await ImageLoader.shared.loadDocument(from: url)

    let canvas = ImageCanvasView(document: document)
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: NSSize(width: 200, height: 200)),
      styleMask: [.titled],
      backing: .buffered,
      defer: false,
    )
    window.contentView?.addSubview(canvas)

    let backingSize = canvas.convertToBacking(canvas.bounds.size)
    #expect(backingSize.isApproximatelyEqual(to: document.pixelSize))
  }

  @Test func `downsampled proxy keeps source sized canvas`() throws {
    let defaults = UserDefaults.standard
    let key = AppSettings.Keys.imageActualSizeStrategy.rawValue
    let previousValue = defaults.object(forKey: key)
    defaults.set(ImageActualSizeStrategy.pointSize.rawValue, forKey: key)
    defer {
      if let previousValue {
        defaults.set(previousValue, forKey: key)
      } else {
        defaults.removeObject(forKey: key)
      }
    }

    let sourceSize = IntSize(width: 20, height: 10)
    let url = URL.temporaryDirectory
      .appending(path: "imaxe-proxy-canvas-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: url) }
    try TestSupport.pngData(width: sourceSize.width, height: sourceSize.height).write(to: url)

    let imageSource = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let metadata = try ImageMetadata(bitmapURL: url, imageSource: imageSource)
    let proxy = try #require(ImageLoader.downsampledBitmap(
      from: imageSource,
      metadata: metadata,
      maximumDimension: 16,
    ))
    let fileSnapshot = try #require(FileSnapshot(url: url))
    let document = ImageDocument(
      url: url,
      fileSnapshot: fileSnapshot,
      metadata: metadata,
      content: .staticBitmap(proxy.image),
      renderedPixelSize: proxy.pixelSize,
    )

    let canvas = ImageCanvasView(document: document)

    #expect(proxy.image.size == NSSize(width: 16, height: 8))
    #expect(document.pixelSize == sourceSize.nsSize)
    #expect(canvas.frame.size == sourceSize.nsSize)
  }

  @Test func `always fit to window still applies after viewport preserving image change`(
  ) async throws {
    var reportedZoomScale: CGFloat?
    let coordinator = ImageScrollView.Coordinator(
      onZoomScaleChange: { reportedZoomScale = $0 },
      onAlwaysFitToWindowChange: { _ in },
    )
    let scrollView = NSScrollView(
      frame: NSRect(origin: .zero, size: NSSize(width: 100, height: 100)),
    )
    let imageView = NSView(frame: NSRect(origin: .zero, size: NSSize(width: 200, height: 100)))
    let url = URL.temporaryDirectory
      .appending(path: "imaxe-fit-document-\(UUID().uuidString).png")
    try TestSupport.pngData(width: 200, height: 100).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let document = try await ImageLoader.shared.loadDocument(from: url)
    scrollView.allowsMagnification = true
    scrollView.minMagnification = Constants.imageZoomScaleRange.lowerBound
    scrollView.maxMagnification = Constants.imageZoomScaleRange.upperBound
    scrollView.documentView = imageView
    coordinator.updateAlwaysFitToWindowFromBinding(true)
    coordinator.prepareForImage(
      document,
      shouldApplyLoadedImageWindowSize: false,
    )

    coordinator.scrollViewDidLayout(scrollView)

    #expect(!coordinator.hasPendingCommands)
    #expect(scrollView.magnification.isApproximatelyEqual(to: 0.5))
    #expect(reportedZoomScale?.isApproximatelyEqual(to: 0.5) == true)
  }

  @Test func `double click triggers fit to screen`() throws {
    let scrollView = ImageScrollView.ImageNSScrollView()
    var didTriggerDoubleClick = false
    scrollView.onDoubleClick = {
      didTriggerDoubleClick = true
    }
    let event = try #require(NSEvent.mouseEvent(
      with: .leftMouseDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      eventNumber: 0,
      clickCount: 2,
      pressure: 1,
    ))

    scrollView.mouseDown(with: event)

    #expect(didTriggerDoubleClick)
  }

  @Test func `programmatic zoom anchors on image center`() throws {
    let coordinator = ImageScrollView.Coordinator(
      onZoomScaleChange: { _ in },
      onAlwaysFitToWindowChange: { _ in },
    )
    let scrollView = NSScrollView(
      frame: NSRect(origin: .zero, size: NSSize(width: 200, height: 100)),
    )
    scrollView.allowsMagnification = true
    scrollView.documentView = NSView(
      frame: NSRect(origin: .zero, size: NSSize(width: 800, height: 600)),
    )

    let animation = try #require(coordinator.prepareZoomAnimation(2, to: scrollView))

    #expect(animation.center == NSPoint(x: 400, y: 300))
  }

  @Test func `reduce motion applies programmatic zoom without animation`() {
    let coordinator = ImageScrollView.Coordinator(
      onZoomScaleChange: { _ in },
      onAlwaysFitToWindowChange: { _ in },
    )
    coordinator.shouldReduceMotion = { true }
    let scrollView = NSScrollView(
      frame: NSRect(origin: .zero, size: NSSize(width: 200, height: 100)),
    )
    scrollView.allowsMagnification = true
    scrollView.minMagnification = Constants.imageZoomScaleRange.lowerBound
    scrollView.maxMagnification = Constants.imageZoomScaleRange.upperBound
    scrollView.documentView = NSView(
      frame: NSRect(origin: .zero, size: NSSize(width: 800, height: 600)),
    )

    coordinator.applyZoomScale(2, to: scrollView, animated: true)

    #expect(scrollView.magnification.isApproximatelyEqual(to: 2))
    #expect(!coordinator.isProgrammaticZoomAnimating)
  }

  @Test func `direct panning moves the canvas with the pointer`() {
    let scrollView = ImageScrollView.ImageNSScrollView(
      frame: NSRect(origin: .zero, size: NSSize(width: 200, height: 100)),
    )
    let clipView = ImageScrollView.ImageClipView()
    clipView.documentView = NSView(
      frame: NSRect(origin: .zero, size: NSSize(width: 800, height: 600)),
    )
    scrollView.contentView = clipView
    scrollView.documentView = clipView.documentView
    scrollView.allowsMagnification = true
    scrollView.magnification = 1
    scrollView.contentView.scroll(to: NSPoint(x: 100, y: 100))

    scrollView.panDocument(by: NSSize(width: 40, height: 30))

    #expect(scrollView.contentView.bounds.origin == NSPoint(x: 60, y: 70))
  }

  @Test func `viewport command pans the image`() {
    let coordinator = ImageScrollView.Coordinator(
      onZoomScaleChange: { _ in },
      onAlwaysFitToWindowChange: { _ in },
    )
    let viewportController = ImageViewportController()
    let scrollView = NSScrollView(
      frame: NSRect(origin: .zero, size: NSSize(width: 200, height: 100)),
    )
    scrollView.documentView = NSView(
      frame: NSRect(origin: .zero, size: NSSize(width: 800, height: 600)),
    )
    scrollView.contentView.scroll(to: NSPoint(x: 100, y: 100))
    coordinator.observe(scrollView)
    coordinator.bind(to: viewportController)

    viewportController.pan(horizontal: 40, vertical: 30)

    #expect(scrollView.contentView.bounds.origin == NSPoint(x: 140, y: 130))
  }

  @Test func `animated image documents create independent frame state`() async throws {
    let loader = ImageLoader.shared
    let document = try await loader.loadDocument(
      from: TestSupport.sampleImageURL("sample_384×512.gif"),
    )
    let firstRepresentation = try #require(document.makeAnimatedBitmapRepresentation())
    let secondRepresentation = try #require(document.makeAnimatedBitmapRepresentation())

    #expect(firstRepresentation !== secondRepresentation)
    #expect(document.metadata.isAnimated)
    #expect(document.metadata.imageCount > 1)
    firstRepresentation.setProperty(.currentFrame, withValue: 1)
    #expect(secondRepresentation.currentGIFFrame == 0)
  }

  @Test func `fit to screen command is queued`() {
    let coordinator = ImageScrollView.Coordinator(
      onZoomScaleChange: { _ in },
      onAlwaysFitToWindowChange: { _ in },
    )
    let viewportController = ImageViewportController()
    let scrollView = NSScrollView(
      frame: NSRect(origin: .zero, size: NSSize(width: 100, height: 100)),
    )
    scrollView.documentView = NSView(
      frame: NSRect(origin: .zero, size: NSSize(width: 200, height: 100)),
    )
    coordinator.observe(scrollView)
    coordinator.bind(to: viewportController)

    viewportController.fitToScreen()

    #expect(coordinator.hasPendingCommands)
  }

  @Test func `constrained window frame preserves size at fractional origin`() throws {
    let visibleFrame = try #require(NSScreen.main?.visibleFrame)
    let requestedSize = NSSize(width: 700, height: 500)
    let requestedOrigin = NSPoint(
      x: floor(visibleFrame.minX + 20) + 0.5,
      y: floor(visibleFrame.minY + 20) + 0.5,
    )
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: requestedSize),
      styleMask: [.titled, .resizable],
      backing: .buffered,
      defer: false,
    )

    let frame = window.constrainedFrame(
      requestedSize,
      centeringStrategy: .custom(NSPoint(
        x: requestedOrigin.x + requestedSize.width / 2,
        y: requestedOrigin.y + requestedSize.height / 2,
      )),
    )

    #expect(frame.size == requestedSize)
    #expect(frame.origin == requestedOrigin)
  }

  @Test func `fit window to image matches viewport within one backing pixel`() async throws {
    let coordinator = ImageScrollView.Coordinator(
      onZoomScaleChange: { _ in },
      onAlwaysFitToWindowChange: { _ in },
    )
    let viewportController = ImageViewportController()
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: NSSize(width: 1000, height: 700)),
      styleMask: [.titled, .resizable],
      backing: .buffered,
      defer: false,
    )
    let scrollView = ImageScrollView.ImageNSScrollView(frame: window.contentView?.bounds ?? .zero)
    let imageSize = NSSize(width: 780, height: 540)
    scrollView.autoresizingMask = [.width, .height]
    scrollView.allowsMagnification = true
    scrollView.minMagnification = Constants.imageZoomScaleRange.lowerBound
    scrollView.maxMagnification = Constants.imageZoomScaleRange.upperBound
    scrollView.documentView = NSView(frame: NSRect(origin: .zero, size: imageSize))
    window.contentView = scrollView
    coordinator.observe(scrollView)
    coordinator.bind(to: viewportController)

    viewportController.fitWindowToImage()

    let pointTolerance = 1 / window.backingScaleFactor
    try await TestSupport.waitUntil {
      abs(scrollView.contentSize.width - imageSize.width) <= pointTolerance
        && abs(scrollView.contentSize.height - imageSize.height) <= pointTolerance
    }

    #expect(abs(scrollView.contentSize.width - imageSize.width) <= pointTolerance)
    #expect(abs(scrollView.contentSize.height - imageSize.height) <= pointTolerance)
  }

  @Test func `fit to screen animates zoom when window frame is unchanged`() async throws {
    let coordinator = ImageScrollView.Coordinator(
      onZoomScaleChange: { _ in },
      onAlwaysFitToWindowChange: { _ in },
    )
    coordinator.shouldReduceMotion = { false }
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: NSSize(width: 800, height: 600)),
      styleMask: [.titled, .resizable],
      backing: .buffered,
      defer: false,
    )
    let screen = try #require(window.screen ?? NSScreen.main)
    let maximumFrame = window.constrainFrameRect(screen.visibleFrame, to: screen)
    window.setFrame(maximumFrame, display: false)

    let scrollView = ImageScrollView.ImageNSScrollView(frame: window.contentView?.bounds ?? .zero)
    scrollView.autoresizingMask = [.width, .height]
    scrollView.allowsMagnification = true
    scrollView.minMagnification = Constants.imageZoomScaleRange.lowerBound
    scrollView.maxMagnification = Constants.imageZoomScaleRange.upperBound
    window.contentView = scrollView
    scrollView.layoutSubtreeIfNeeded()
    scrollView.documentView = NSView(
      frame: NSRect(origin: .zero, size: scrollView.contentSize),
    )
    scrollView.magnification = 0.5
    coordinator.observe(scrollView)

    let originalFrame = window.frame
    coordinator.handle(.fitToScreen)

    try await TestSupport.waitUntil {
      coordinator.isProgrammaticZoomAnimating
    }
    #expect(window.frame.isApproximatelyEqual(to: originalFrame))

    try await TestSupport.waitUntil {
      !coordinator.isProgrammaticZoomAnimating
        && scrollView.magnification.isApproximatelyEqual(to: 1.0)
    }
  }

  @Test func `fit to screen and restore keep image and viewport sizes synchronized`() async throws {
    let coordinator = ImageScrollView.Coordinator(
      onZoomScaleChange: { _ in },
      onAlwaysFitToWindowChange: { _ in },
    )
    coordinator.shouldReduceMotion = { false }
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: NSSize(width: 400, height: 300)),
      styleMask: [.titled, .resizable],
      backing: .buffered,
      defer: false,
    )
    let scrollView = ImageScrollView.ImageNSScrollView(frame: window.contentView?.bounds ?? .zero)
    let clipView = ImageScrollView.ImageClipView()
    let imageSize = NSSize(width: 800, height: 600)
    scrollView.contentView = clipView
    scrollView.autoresizingMask = [.width, .height]
    scrollView.allowsMagnification = true
    scrollView.minMagnification = Constants.imageZoomScaleRange.lowerBound
    scrollView.maxMagnification = Constants.imageZoomScaleRange.upperBound
    clipView.documentView = NSView(frame: NSRect(origin: .zero, size: imageSize))
    window.contentView = scrollView
    scrollView.magnification = 0.5
    scrollView.layoutSubtreeIfNeeded()
    coordinator.observe(scrollView)

    func maximumMismatchDuringAnimation() async throws -> CGFloat {
      try await TestSupport.waitUntil {
        coordinator.isProgrammaticZoomAnimating
      }

      var maximumMismatch = CGFloat.zero
      try await TestSupport.waitUntil {
        scrollView.layoutSubtreeIfNeeded()
        let imageDisplaySize = NSSize(
          width: imageSize.width * scrollView.magnification,
          height: imageSize.height * scrollView.magnification,
        )
        maximumMismatch = max(
          maximumMismatch,
          abs(imageDisplaySize.width - scrollView.contentSize.width),
          abs(imageDisplaySize.height - scrollView.contentSize.height),
        )
        return !coordinator.isProgrammaticZoomAnimating
      }
      return maximumMismatch
    }

    let pointTolerance = 1 / window.backingScaleFactor
    coordinator.handle(.fitToScreen)
    let maximumMismatch = try await maximumMismatchDuringAnimation()
    #expect(
      maximumMismatch <= pointTolerance,
      "Maximum image/viewport mismatch was \(maximumMismatch) points.",
    )

    coordinator.handle(.fitToScreen)
    let restoreMaximumMismatch = try await maximumMismatchDuringAnimation()
    #expect(
      restoreMaximumMismatch <= pointTolerance,
      "Maximum restore image/viewport mismatch was \(restoreMaximumMismatch) points.",
    )
  }

  @Test func `fit to screen double click restores previous viewport`() async throws {
    let originalZoomScale = CGFloat(0.25)
    var alwaysFitChanges: [Bool] = []
    let coordinator = ImageScrollView.Coordinator(
      onZoomScaleChange: { _ in },
      onAlwaysFitToWindowChange: { alwaysFitChanges.append($0) },
    )
    coordinator.shouldReduceMotion = { false }
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: NSSize(width: 320, height: 240)),
      styleMask: [.titled, .resizable],
      backing: .buffered,
      defer: false,
    )
    let originalWindowFrame = window.frame
    let scrollView = ImageScrollView.ImageNSScrollView(frame: window.contentView?.bounds ?? .zero)
    let imageView = NSView(frame: NSRect(origin: .zero, size: NSSize(width: 1000, height: 500)))
    scrollView.allowsMagnification = true
    scrollView.minMagnification = Constants.imageZoomScaleRange.lowerBound
    scrollView.maxMagnification = Constants.imageZoomScaleRange.upperBound
    scrollView.documentView = imageView
    scrollView.magnification = originalZoomScale
    window.contentView = scrollView
    coordinator.observe(scrollView)
    coordinator.updateAlwaysFitToWindowFromBinding(true)

    coordinator.handle(.fitToScreen)
    try await TestSupport.waitUntil {
      coordinator.isFitToScreenToggleActive
        && !window.frame.isApproximatelyEqual(to: originalWindowFrame)
        && scrollView.magnification > originalZoomScale
    }

    #expect(coordinator.alwaysFitToWindow == false)
    #expect(alwaysFitChanges.last == false)

    coordinator.handle(.fitToScreen)
    try await TestSupport.waitUntil {
      !coordinator.isFitToScreenToggleActive
        && window.frame.isApproximatelyEqual(to: originalWindowFrame)
        && scrollView.magnification.isApproximatelyEqual(to: originalZoomScale)
    }
  }

  @Test func `stale fit to screen animation does not override restore`() async throws {
    let originalZoomScale = CGFloat(0.25)
    let coordinator = ImageScrollView.Coordinator(
      onZoomScaleChange: { _ in },
      onAlwaysFitToWindowChange: { _ in },
    )
    coordinator.shouldReduceMotion = { false }
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: NSSize(width: 320, height: 240)),
      styleMask: [.titled, .resizable],
      backing: .buffered,
      defer: false,
    )
    let originalWindowFrame = window.frame
    let scrollView = ImageScrollView.ImageNSScrollView(frame: window.contentView?.bounds ?? .zero)
    scrollView.allowsMagnification = true
    scrollView.minMagnification = Constants.imageZoomScaleRange.lowerBound
    scrollView.maxMagnification = Constants.imageZoomScaleRange.upperBound
    scrollView.documentView = NSView(
      frame: NSRect(origin: .zero, size: NSSize(width: 1000, height: 500)),
    )
    scrollView.magnification = originalZoomScale
    window.contentView = scrollView
    coordinator.observe(scrollView)

    coordinator.handle(.fitToScreen)
    coordinator.handle(.fitToScreen)

    try await TestSupport.waitUntil {
      !coordinator.isFitToScreenToggleActive
        && window.frame.isApproximatelyEqual(to: originalWindowFrame)
        && scrollView.magnification.isApproximatelyEqual(to: originalZoomScale)
    }
  }
}
