//
//  ImageScrollView.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/20.
//

import AppKit
import PocketSVG
import SwiftUI

struct ImageScrollView: NSViewRepresentable {
  let loadedImage: LoadedImage
  let fitToWindowRequest: Int
  let fitWindowToImageRequest: Int
  @Binding var scale: CGFloat
  @Binding var alwaysFitToWindow: Bool

  private let scaleUpdateTolerance: CGFloat = 0.000_1

  func onScaleChange(_ newScale: CGFloat) {
    guard newScale.isFinite else { return }

    DispatchQueue.main.async {
      guard abs(scale - newScale) > scaleUpdateTolerance else { return }
      scale = newScale
    }
  }

  func onAlwaysFitToWindowChange(_ newAlwaysFitToWindow: Bool) {
    DispatchQueue.main.async {
      guard alwaysFitToWindow != newAlwaysFitToWindow else { return }
      alwaysFitToWindow = newAlwaysFitToWindow
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(
      onScaleChange: onScaleChange,
      onAlwaysFitToWindowChange: onAlwaysFitToWindowChange,
    )
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = ImageNSScrollView()
    let centeringClipView = CenteringClipView()
    centeringClipView.documentView = ImageCanvasView(loadedImage: loadedImage, scale: scale)
    scrollView.contentView = centeringClipView

    // Disable automatic content insets adjustment to ensure the image can be properly centered and
    // scaled without unexpected padding.
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

    scrollView.drawsBackground = false
    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = false
    scrollView.verticalScrollElasticity = .none
    scrollView.horizontalScrollElasticity = .none
    scrollView.allowsMagnification = true
    scrollView.minMagnification = Constants.imageScaleRange.lowerBound
    scrollView.maxMagnification = Constants.imageScaleRange.upperBound
    scrollView.usesPredominantAxisScrolling = false
    scrollView.magnification = scale.clamped(to: Constants.imageScaleRange)
    context.coordinator.prepareForImage(
      loadedImage,
      fitToWindowRequest: fitToWindowRequest,
      fitWindowToImageRequest: fitWindowToImageRequest,
    )
    context.coordinator.alwaysFitToWindow = alwaysFitToWindow
    scrollView.onLayout = { [weak coordinator = context.coordinator, weak scrollView] in
      guard let scrollView else { return }
      coordinator?.scrollViewDidLayout(scrollView)
    }
    scrollView.onUserMagnification = { [weak coordinator = context.coordinator] in
      coordinator?.disableAlwaysFitToWindowForUserMagnification()
    }
    context.coordinator.observe(scrollView)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.onScaleChange = onScaleChange
    context.coordinator.onAlwaysFitToWindowChange = onAlwaysFitToWindowChange
    context.coordinator.alwaysFitToWindow = alwaysFitToWindow
    context.coordinator.observe(scrollView)

    if let imageView = scrollView.documentView as? ImageCanvasView {
      imageView.loadedImage = loadedImage
      imageView.scale = scale
      scrollView.reflectScrolledClipView(scrollView.contentView)
    } else {
      scrollView.documentView = ImageCanvasView(loadedImage: loadedImage, scale: scale)
    }

    context.coordinator.prepareForImage(
      loadedImage,
      fitToWindowRequest: fitToWindowRequest,
      fitWindowToImageRequest: fitWindowToImageRequest,
    )
    scrollView.layoutSubtreeIfNeeded()

    let clampedScale = scale.clamped(to: Constants.imageScaleRange)
    if !alwaysFitToWindow, !context.coordinator.hasPendingRequests,
       scrollView.magnification != clampedScale
    {
      scrollView.magnification = clampedScale
    }

    context.coordinator.performPendingRequests(scrollView)
  }

  final class ImageNSScrollView: NSScrollView {
    var onLayout: (() -> Void)?
    var onUserMagnification: (() -> Void)?

    override var intrinsicContentSize: NSSize {
      NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
      super.layout()
      onLayout?()
    }

    override func magnify(with event: NSEvent) {
      onUserMagnification?()
      super.magnify(with: event)
    }

    override func smartMagnify(with event: NSEvent) {
      onUserMagnification?()
      super.smartMagnify(with: event)
    }
  }

  final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
      var constrainedBounds = super.constrainBoundsRect(proposedBounds)

      guard let documentView else { return constrainedBounds }

      let documentFrame = documentView.frame
      let visibleSize = constrainedBounds.size

      if documentFrame.width <= visibleSize.width {
        constrainedBounds.origin.x = (visibleSize.width - documentFrame.width) / -2.0
      } else {
        constrainedBounds.origin.x = constrainedBounds.origin.x.clamped(
          to: 0 ... documentFrame.width - visibleSize.width,
        )
      }

      if documentFrame.height <= visibleSize.height {
        constrainedBounds.origin.y = (visibleSize.height - documentFrame.height) / -2.0
      } else {
        constrainedBounds.origin.y = constrainedBounds.origin.y.clamped(
          to: 0 ... documentFrame.height - visibleSize.height,
        )
      }

      return constrainedBounds
    }
  }

  final class Coordinator {
    var onScaleChange: (CGFloat) -> Void
    var onAlwaysFitToWindowChange: (Bool) -> Void
    var alwaysFitToWindow = false

    var hasPendingRequests: Bool {
      pendingFitToWindowRequest != nil || pendingFitWindowToImageRequest != nil
    }

    private var imageIdentifier: ObjectIdentifier?
    private var pendingFitToWindowRequest: Int?
    private var pendingFitWindowToImageRequest: Int?
    private var completedFitToWindowRequest = 0
    private var completedFitWindowToImageRequest = 0
    private var suppressAlwaysFitForProgrammaticResize = false
    private var suppressedAlwaysFitViewportSize: NSSize?
    private var observedScrollView: NSScrollView?
    private var magnificationObservation: NSKeyValueObservation?

    init(
      onScaleChange: @escaping (CGFloat) -> Void,
      onAlwaysFitToWindowChange: @escaping (Bool) -> Void,
    ) {
      self.onScaleChange = onScaleChange
      self.onAlwaysFitToWindowChange = onAlwaysFitToWindowChange
    }

    func prepareForImage(
      _ loadedImage: LoadedImage, fitToWindowRequest: Int, fitWindowToImageRequest: Int,
    ) {
      let newIdentifier = ObjectIdentifier(loadedImage.image)
      if imageIdentifier != newIdentifier {
        imageIdentifier = newIdentifier
        completedFitWindowToImageRequest = fitWindowToImageRequest
        pendingFitWindowToImageRequest = nil
        queueFitToWindow(fitToWindowRequest)
      } else if fitToWindowRequest != completedFitToWindowRequest {
        queueFitToWindow(fitToWindowRequest)
      }

      if fitWindowToImageRequest != completedFitWindowToImageRequest {
        queueFitWindowToImage(fitWindowToImageRequest)
      }
    }

    func scrollViewDidLayout(_ scrollView: NSScrollView) {
      performPendingRequests(
        scrollView,
        shouldUpdateLayout: false,
      )

      guard alwaysFitToWindow, !hasPendingRequests else { return }
      guard shouldApplyAlwaysFitToWindow(scrollView) else { return }

      fitToWindow(scrollView)
    }

    func disableAlwaysFitToWindowForUserMagnification() {
      guard alwaysFitToWindow else { return }

      alwaysFitToWindow = false
      onAlwaysFitToWindowChange(false)
    }

    func performPendingRequests(_ scrollView: NSScrollView, shouldUpdateLayout: Bool = true) {
      guard hasPendingRequests else { return }

      if shouldUpdateLayout {
        scrollView.layoutSubtreeIfNeeded()
      }

      if fitWindowToImageIfNeeded(scrollView) { return }

      fitToWindowIfNeeded(scrollView)
    }

    private func fitToWindowIfNeeded(_ scrollView: NSScrollView) {
      guard let request = pendingFitToWindowRequest,
            fitToWindow(scrollView)
      else { return }

      pendingFitToWindowRequest = nil
      completedFitToWindowRequest = request
    }

    @discardableResult
    private func fitToWindow(_ scrollView: NSScrollView) -> Bool {
      guard let documentView = scrollView.documentView else { return false }

      let viewportSize = scrollView.contentSize
      let imageSize = documentView.bounds.size

      guard viewportSize.width > 0,
            viewportSize.height > 0,
            imageSize.width > 0,
            imageSize.height > 0
      else { return false }

      let fitScale = min(
        viewportSize.width / imageSize.width,
        viewportSize.height / imageSize.height,
      )
      .clamped(to: Constants.imageScaleRange)
      let center = NSPoint(x: imageSize.width / 2.0, y: imageSize.height / 2.0)

      let shouldUpdateMagnification = abs(scrollView.magnification - fitScale) > 0.000_1
      if shouldUpdateMagnification {
        scrollView.setMagnification(fitScale, centeredAt: center)
      }

      clampScrollBounds(scrollView)
      if shouldUpdateMagnification {
        onScaleChange(scrollView.magnification)
      }
      return true
    }

    private func fitWindowToImageIfNeeded(_ scrollView: NSScrollView) -> Bool {
      guard let request = pendingFitWindowToImageRequest,
            let documentView = scrollView.documentView,
            let window = scrollView.window
      else { return false }

      let imageSize = documentView.bounds.size
      let viewportSize = scrollView.contentSize
      guard imageSize.width > 0,
            imageSize.height > 0,
            viewportSize.width > 0,
            viewportSize.height > 0
      else { return false }

      let screen = window.screen ?? NSScreen.main
      let visibleFrame = screen?.visibleFrame ?? window.frame
      let frameViewportDelta = NSSize(
        width: max(0, window.frame.width - viewportSize.width),
        height: max(0, window.frame.height - viewportSize.height),
      )
      let maxViewportSize = NSSize(
        width: max(1, visibleFrame.width - frameViewportDelta.width),
        height: max(1, visibleFrame.height - frameViewportDelta.height),
      )
      let currentScale = scrollView.magnification.clamped(to: Constants.imageScaleRange)
      let targetImageDisplaySize = NSSize(
        width: imageSize.width * currentScale,
        height: imageSize.height * currentScale,
      )
      let backingScale = window.backingScaleFactor
      let targetViewportSize = NSSize(
        width: min(targetImageDisplaySize.width, maxViewportSize.width)
          .roundedDownToPixel(scale: backingScale),
        height: min(targetImageDisplaySize.height, maxViewportSize.height)
          .roundedDownToPixel(scale: backingScale),
      )
      let targetFrameSize = NSSize(
        width: targetViewportSize.width + frameViewportDelta.width,
        height: targetViewportSize.height + frameViewportDelta.height,
      )
      let currentCenter = NSPoint(x: window.frame.midX, y: window.frame.midY)
      let centeredFrame = NSRect(
        x: currentCenter.x - targetFrameSize.width / 2.0,
        y: currentCenter.y - targetFrameSize.height / 2.0,
        width: targetFrameSize.width,
        height: targetFrameSize.height,
      )
      let constrainedFrame = window.constrainFrameRect(
        centeredFrame.constrained(to: visibleFrame), to: screen,
      )

      pendingFitWindowToImageRequest = nil
      completedFitWindowToImageRequest = request
      suppressAlwaysFitForProgrammaticResize = true
      suppressedAlwaysFitViewportSize = nil
      applyFitWindowToImage(scrollView, window: window, frame: constrainedFrame)
      return true
    }

    private func applyFitWindowToImage(
      _ scrollView: NSScrollView, window: NSWindow, frame: NSRect,
    ) {
      DispatchQueue.main.async { [weak self, weak scrollView, weak window] in
        guard let self, let scrollView, let window else { return }

        NSAnimationContext.runAnimationGroup { context in
          context.duration = window.animationResizeTime(frame)
          context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

          window.animator().setFrame(frame, display: false)
        } completionHandler: { [weak self, weak scrollView] in
          Task { @MainActor [weak self, weak scrollView] in
            guard let self, let scrollView else { return }

            scrollView.layoutSubtreeIfNeeded()
            clampScrollBounds(scrollView)
            suppressedAlwaysFitViewportSize = scrollView.contentSize
            onScaleChange(scrollView.magnification)
          }
        }
      }
    }

    private func shouldApplyAlwaysFitToWindow(_ scrollView: NSScrollView) -> Bool {
      guard suppressAlwaysFitForProgrammaticResize else { return true }
      guard let suppressedAlwaysFitViewportSize else { return false }

      if scrollView.contentSize.isApproximatelyEqual(to: suppressedAlwaysFitViewportSize) {
        return false
      }

      suppressAlwaysFitForProgrammaticResize = false
      self.suppressedAlwaysFitViewportSize = nil
      return true
    }

    private func clampScrollBounds(_ scrollView: NSScrollView) {
      let constrainedBounds = scrollView.contentView
        .constrainBoundsRect(scrollView.contentView.bounds)
      scrollView.contentView.scroll(to: constrainedBounds.origin)
      scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func queueFitToWindow(_ request: Int) {
      pendingFitToWindowRequest = request
    }

    private func queueFitWindowToImage(_ request: Int) {
      pendingFitWindowToImageRequest = request
    }

    func observe(_ scrollView: NSScrollView) {
      guard observedScrollView !== scrollView else { return }

      observedScrollView = scrollView
      magnificationObservation = scrollView
        .observe(\.magnification, options: [.new]) { [weak self] scrollView, _ in
          Task { @MainActor [weak self, weak scrollView] in
            guard let self, let scrollView else { return }
            onScaleChange(scrollView.magnification)
          }
        }
    }
  }
}
