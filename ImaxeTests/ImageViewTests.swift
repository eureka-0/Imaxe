//
//  ImageViewTests.swift
//  ImaxeTests
//
//  Created by lxlong on 2026/6/14.
//

import AppKit
@testable import Imaxe
import SwiftUI
import Testing

@MainActor
@Suite("Image View")
struct ImageViewTests {
  @Test func `bitmap image container uses pixel size`() {
    let image = TestSupport.bitmapImage()
    let url = URL(fileURLWithPath: "/tmp/example.png")

    let imageContainer = ImageContainer(url: url, nsImage: image)

    #expect(imageContainer.pixelSize == NSSize(width: 10, height: 20))
    #expect(imageContainer.nsImage.size == NSSize(width: 10, height: 20))
  }

  @Test func `canvas occupies image pixel size in backing pixels`() {
    let image = TestSupport.bitmapImage()
    let url = URL(fileURLWithPath: "/tmp/example.png")
    let imageContainer = ImageContainer(url: url, nsImage: image)
    let imageInfo = ImageInfo(url: url)

    let canvas = ImageCanvasView(
      imageContainer: imageContainer,
      imageInfo: imageInfo,
    )
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: NSSize(width: 200, height: 200)),
      styleMask: [.titled],
      backing: .buffered,
      defer: false,
    )
    window.contentView?.addSubview(canvas)

    let backingSize = canvas.convertToBacking(canvas.bounds.size)
    #expect(backingSize.isApproximatelyEqual(to: imageContainer.pixelSize))
  }

  @Test func `always fit to window still applies after viewport preserving image change`() {
    var reportedZoomScale: CGFloat?
    let coordinator = ImageScrollView.Coordinator(
      onZoomScaleChange: { reportedZoomScale = $0 },
      onAlwaysFitToWindowChange: { _ in },
    )
    let scrollView = NSScrollView(
      frame: NSRect(origin: .zero, size: NSSize(width: 100, height: 100)),
    )
    let imageView = NSView(frame: NSRect(origin: .zero, size: NSSize(width: 200, height: 100)))
    let imageContainer = ImageContainer(
      url: URL(fileURLWithPath: "/tmp/example.png"),
      nsImage: TestSupport.bitmapImage(width: 200, height: 100),
    )
    scrollView.allowsMagnification = true
    scrollView.minMagnification = Constants.imageZoomScaleRange.lowerBound
    scrollView.maxMagnification = Constants.imageZoomScaleRange.upperBound
    scrollView.documentView = imageView
    coordinator.updateAlwaysFitToWindowFromBinding(true)
    coordinator.prepareForImage(
      imageContainer,
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
      try await TestSupport.waitUntil(timeout: .seconds(2)) {
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
