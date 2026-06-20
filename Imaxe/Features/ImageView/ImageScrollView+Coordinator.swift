//
//  ImageScrollView+Coordinator.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/18.
//

import SwiftUI

extension ImageScrollView {
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
        queueFitToWindow(fitToWindowRequest)
      } else if fitToWindowRequest != completedFitToWindowRequest {
        queueFitToWindow(fitToWindowRequest)
      }

      if fitWindowToImageRequest != completedFitWindowToImageRequest {
        queueFitWindowToImage(fitWindowToImageRequest)
      }
    }

    func scrollViewDidLayout(_ scrollView: NSScrollView, minScale: CGFloat, maxScale: CGFloat) {
      performPendingRequests(
        scrollView,
        minScale: minScale,
        maxScale: maxScale,
        shouldUpdateLayout: false,
      )

      guard alwaysFitToWindow, !hasPendingRequests else { return }
      guard shouldApplyAlwaysFitToWindow(scrollView) else { return }

      fitToWindow(scrollView, minScale: minScale, maxScale: maxScale)
    }

    func disableAlwaysFitToWindowForUserMagnification() {
      guard alwaysFitToWindow else { return }

      alwaysFitToWindow = false
      onAlwaysFitToWindowChange(false)
    }

    func performPendingRequests(
      _ scrollView: NSScrollView,
      minScale: CGFloat,
      maxScale: CGFloat,
      shouldUpdateLayout: Bool = true,
    ) {
      guard hasPendingRequests else { return }

      if shouldUpdateLayout {
        scrollView.layoutSubtreeIfNeeded()
      }

      if fitWindowToImageIfNeeded(scrollView, minScale: minScale, maxScale: maxScale) { return }

      fitToWindowIfNeeded(scrollView, minScale: minScale, maxScale: maxScale)
    }

    private func fitToWindowIfNeeded(
      _ scrollView: NSScrollView, minScale: CGFloat, maxScale: CGFloat,
    ) {
      guard let request = pendingFitToWindowRequest,
            fitToWindow(scrollView, minScale: minScale, maxScale: maxScale)
      else { return }

      pendingFitToWindowRequest = nil
      completedFitToWindowRequest = request
    }

    @discardableResult
    private func fitToWindow(
      _ scrollView: NSScrollView, minScale: CGFloat, maxScale: CGFloat,
    ) -> Bool {
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
      .clamped(to: minScale ... maxScale)
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

    private func fitWindowToImageIfNeeded(
      _ scrollView: NSScrollView, minScale: CGFloat, maxScale: CGFloat,
    ) -> Bool {
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
      let currentScale = scrollView.magnification.clamped(to: minScale ... maxScale)
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
          guard let self, let scrollView else { return }

          scrollView.layoutSubtreeIfNeeded()
          clampScrollBounds(scrollView)
          suppressedAlwaysFitViewportSize = scrollView.contentSize
          onScaleChange(scrollView.magnification)
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
          self?.onScaleChange(scrollView.magnification)
        }
    }
  }
}

private extension NSSize {
  func isApproximatelyEqual(to other: NSSize) -> Bool {
    abs(width - other.width) < 1.0 && abs(height - other.height) < 1.0
  }
}
