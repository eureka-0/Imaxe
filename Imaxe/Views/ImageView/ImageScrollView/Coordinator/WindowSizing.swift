//
//  WindowSizing.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/10.
//

import AppKit

extension ImageScrollViewCoordinator {
  struct WindowSizingState {
    var loadedImageWindowSizeMode = AppSettings.Defaults.loadedImageWindowSizeMode
    var fixedLoadedImageWindowSize = AppSettings.Defaults.fixedLoadedImageWindowSize
    var fixedLoadedImageWindowSizeUnit = AppSettings.Defaults.fixedLoadedImageWindowSizeUnit
    var suppressAlwaysFitForProgrammaticResize = false
    var suppressedAlwaysFitViewportSize: NSSize?
    var fitToScreenRestoreState: FitToScreenRestoreState?
  }

  struct FitToScreenRestoreState {
    let windowFrame: NSRect
    let zoomScale: CGFloat
    let imageFittedToViewport: Bool
  }

  struct WindowSizingContext {
    let window: NSWindow
    let screen: NSScreen?
    let visibleFrame: NSRect
    let imageSize: NSSize
    let frameViewportDelta: NSSize
    let maxViewportSize: NSSize
  }

  var isFitToScreenToggleActive: Bool {
    windowSizingState.fitToScreenRestoreState != nil
  }

  func updateLoadedImageWindowSizeSettings(
    mode: LoadedImageWindowSizeMode,
    fixedSize: NSSize,
    fixedSizeUnit: LoadedImageWindowSizeUnit,
  ) {
    windowSizingState.loadedImageWindowSizeMode = mode
    windowSizingState.fixedLoadedImageWindowSize = fixedSize
    windowSizingState.fixedLoadedImageWindowSizeUnit = fixedSizeUnit
  }

  @discardableResult
  func fitToWindow(_ scrollView: NSScrollView, animated: Bool) -> Bool {
    guard let documentView = scrollView.documentView else { return false }

    let viewportSize = scrollView.contentSize
    let imageSize = documentView.bounds.size

    guard viewportSize.width > 0,
          viewportSize.height > 0,
          imageSize.width > 0,
          imageSize.height > 0
    else { return false }

    let fitZoomScale = min(
      viewportSize.width / imageSize.width,
      viewportSize.height / imageSize.height,
    )
    applyZoomScale(fitZoomScale, to: scrollView, animated: animated)
    return true
  }

  private func imageFitsViewport(_ scrollView: NSScrollView) -> Bool {
    guard let documentView = scrollView.documentView else { return false }

    let imageSize = documentView.bounds.size
    let imageDisplaySize = NSSize(
      width: imageSize.width * scrollView.magnification,
      height: imageSize.height * scrollView.magnification,
    )
    let pointTolerance = 1 / (scrollView.window?.backingScaleFactor ?? 1)
    return sizesMatch(imageDisplaySize, scrollView.contentSize, tolerance: pointTolerance)
  }

  func fitToScreenIfNeeded(_ scrollView: NSScrollView) -> Bool {
    guard commandState.pendingFitToScreen,
          let sizingContext = windowSizingContext(for: scrollView),
          let target = fitToScreenTarget(in: sizingContext, centeringStrategy: .centerOnScreen)
    else { return false }

    commandState.pendingFitToScreen = false
    windowSizingState.fitToScreenRestoreState = FitToScreenRestoreState(
      windowFrame: sizingContext.window.frame,
      zoomScale: currentZoomScale,
      imageFittedToViewport: imageFitsViewport(scrollView),
    )
    windowSizingState.suppressAlwaysFitForProgrammaticResize = true
    windowSizingState.suppressedAlwaysFitViewportSize = nil
    applyWindowFrame(
      scrollView,
      window: sizingContext.window,
      frame: target.frame,
      simultaneousZoomScale: target.zoomScale,
      targetImageFittedToViewport: true,
    )
    return true
  }

  func restoreFitToScreenIfNeeded(_ scrollView: NSScrollView) -> Bool {
    guard commandState.pendingRestoreFitToScreen,
          let restoreState = windowSizingState.fitToScreenRestoreState,
          let window = scrollView.window
    else { return false }

    commandState.pendingRestoreFitToScreen = false
    clearFitToScreenRestoreState()
    windowSizingState.suppressAlwaysFitForProgrammaticResize = true
    windowSizingState.suppressedAlwaysFitViewportSize = nil
    applyWindowFrame(
      scrollView,
      window: window,
      frame: window.constrainFrameRect(restoreState.windowFrame, to: window.screen),
      simultaneousZoomScale: restoreState.zoomScale,
      targetImageFittedToViewport: restoreState.imageFittedToViewport,
    )
    return true
  }

  func fitWindowToImageIfNeeded(_ scrollView: NSScrollView) -> Bool {
    guard commandState.pendingFitWindowToImage,
          let sizingContext = windowSizingContext(for: scrollView)
    else { return false }

    let targetImageDisplaySize = imageDisplaySize(
      imageSize: sizingContext.imageSize,
      zoomScale: currentZoomScale,
    )
    commandState.pendingFitWindowToImage = false
    windowSizingState.suppressAlwaysFitForProgrammaticResize = true
    windowSizingState.suppressedAlwaysFitViewportSize = nil
    applyWindowFrame(
      scrollView,
      window: sizingContext.window,
      frame: windowFrame(
        forViewportSize: targetImageDisplaySize,
        in: sizingContext,
        centeringStrategy: .remain,
      ),
    )
    return true
  }

  func applyLoadedImageWindowSizeIfNeeded(_ scrollView: NSScrollView) -> Bool {
    guard commandState.pendingLoadedImageWindowSize,
          let sizingContext = windowSizingContext(for: scrollView),
          let target = loadedImageWindowSizeTarget(in: sizingContext, scrollView: scrollView)
    else { return false }

    applyZoomScale(target.zoomScale, to: scrollView, animated: false)
    commandState.pendingLoadedImageWindowSize = false
    clearFitToScreenRestoreState()
    windowSizingState.suppressAlwaysFitForProgrammaticResize = true
    windowSizingState.suppressedAlwaysFitViewportSize = nil
    applyWindowFrame(
      scrollView,
      window: sizingContext.window,
      frame: target.frame,
    )
    return true
  }

  private func loadedImageWindowSizeTarget(
    in sizingContext: WindowSizingContext,
    scrollView: NSScrollView,
  ) -> (frame: NSRect, zoomScale: CGFloat)? {
    let imageSize = sizingContext.imageSize
    let fitZoomScale = fitZoomScale(for: imageSize, in: sizingContext.maxViewportSize)
    let fillZoomScale = fillZoomScale(for: imageSize, in: sizingContext.maxViewportSize)

    switch windowSizingState.loadedImageWindowSizeMode {
    case .actualSizeLimitedToScreen:
      let targetZoomScale = min(1.0, fitZoomScale).clamped(to: Constants.imageZoomScaleRange)
      return fitImageWindowTarget(
        zoomScale: targetZoomScale,
        in: sizingContext,
        centeringStrategy: .remain,
      )

    case .zoomToFitScreen:
      return fitToScreenTarget(in: sizingContext, centeringStrategy: .remain)

    case .fillScreen:
      let targetZoomScale = fillZoomScale.clamped(to: Constants.imageZoomScaleRange)
      let frame = sizingContext.window.constrainFrameRect(
        sizingContext.visibleFrame,
        to: sizingContext.screen,
      )
      return (frame: frame, zoomScale: targetZoomScale)

    case .actualSize:
      let targetZoomScale = CGFloat(1.0).clamped(to: Constants.imageZoomScaleRange)
      return fitImageWindowTarget(
        zoomScale: targetZoomScale,
        in: sizingContext,
        centeringStrategy: .remain,
      )

    case .fixedSize:
      guard let fixedViewportSize = fixedViewportSize(in: scrollView) else { return nil }

      let targetZoomScale = min(
        fixedViewportSize.width / imageSize.width,
        fixedViewportSize.height / imageSize.height,
      )
      .clamped(to: Constants.imageZoomScaleRange)
      let targetFrame = windowFrame(
        forViewportSize: fixedViewportSize,
        in: sizingContext,
        centeringStrategy: .remain,
      )
      return (frame: targetFrame, zoomScale: targetZoomScale)
    }
  }

  /// Calculates the target window frame and zoom scale for fitting the image to the screen based
  /// on the provided sizing context and centering strategy.
  private func fitToScreenTarget(
    in sizingContext: WindowSizingContext,
    centeringStrategy: NSWindow.CenteringStrategy,
  ) -> (frame: NSRect, zoomScale: CGFloat)? {
    let targetZoomScale = fitZoomScale(
      for: sizingContext.imageSize,
      in: sizingContext.maxViewportSize,
    )
    .clamped(to: Constants.imageZoomScaleRange)

    return fitImageWindowTarget(
      zoomScale: targetZoomScale,
      in: sizingContext,
      centeringStrategy: centeringStrategy,
    )
  }

  /// Calculates the target window frame for fitting the window to the image based on the provided
  /// zoom scale, sizing context and centering strategy.
  private func fitImageWindowTarget(
    zoomScale: CGFloat,
    in sizingContext: WindowSizingContext,
    centeringStrategy: NSWindow.CenteringStrategy,
  ) -> (frame: NSRect, zoomScale: CGFloat)? {
    guard zoomScale.isFinite else { return nil }

    let targetSize = imageDisplaySize(
      imageSize: sizingContext.imageSize,
      zoomScale: zoomScale,
    )
    let targetFrame = windowFrame(
      forViewportSize: targetSize,
      in: sizingContext,
      centeringStrategy: centeringStrategy,
    )
    return (frame: targetFrame, zoomScale: zoomScale)
  }

  private func windowFrame(
    forViewportSize viewportSize: NSSize,
    in sizingContext: WindowSizingContext,
    centeringStrategy: NSWindow.CenteringStrategy,
  ) -> NSRect {
    let targetWindowSize = NSSize(
      width: viewportSize.width + sizingContext.frameViewportDelta.width,
      height: viewportSize.height + sizingContext.frameViewportDelta.height,
    )
    return sizingContext.window.constrainedFrame(
      targetWindowSize,
      centeringStrategy: centeringStrategy,
    )
  }

  private func imageDisplaySize(imageSize: NSSize, zoomScale: CGFloat) -> NSSize {
    NSSize(
      width: (imageSize.width * zoomScale).rounded(),
      height: (imageSize.height * zoomScale).rounded(),
    )
  }

  private func fitZoomScale(for imageSize: NSSize, in viewportSize: NSSize) -> CGFloat {
    min(
      viewportSize.width / imageSize.width,
      viewportSize.height / imageSize.height,
    )
  }

  private func fillZoomScale(for imageSize: NSSize, in viewportSize: NSSize) -> CGFloat {
    max(
      viewportSize.width / imageSize.width,
      viewportSize.height / imageSize.height,
    )
  }

  private func fixedViewportSize(in scrollView: NSScrollView) -> NSSize? {
    guard windowSizingState.fixedLoadedImageWindowSize.width.isFinite,
          windowSizingState.fixedLoadedImageWindowSize.height.isFinite,
          windowSizingState.fixedLoadedImageWindowSize.width > 0,
          windowSizingState.fixedLoadedImageWindowSize.height > 0
    else { return nil }

    let fixedSize = NSSize(
      width: windowSizingState.fixedLoadedImageWindowSize.width,
      height: windowSizingState.fixedLoadedImageWindowSize.height,
    )

    switch windowSizingState.fixedLoadedImageWindowSizeUnit {
    case .points:
      return fixedSize
    case .pixels:
      return scrollView.window?.convertFromBacking(fixedSize)
    }
  }

  private func windowSizingContext(for scrollView: NSScrollView) -> WindowSizingContext? {
    guard let documentView = scrollView.documentView,
          let window = scrollView.window
    else { return nil }

    let imageSize = documentView.bounds.size
    let viewportSize = scrollView.contentSize
    guard imageSize.width > 0,
          imageSize.height > 0,
          viewportSize.width > 0,
          viewportSize.height > 0
    else { return nil }

    let screen = window.screen ?? NSScreen.main
    let visibleFrame = screen?.visibleFrame ?? window.frame
    let frameViewportDelta = NSSize(
      width: max(0, window.frame.width - viewportSize.width),
      height: max(0, window.frame.height - viewportSize.height),
    )
    let maximumFrame = window.constrainFrameRect(visibleFrame, to: screen)
    let maxViewportSize = NSSize(
      width: max(1, maximumFrame.width - frameViewportDelta.width),
      height: max(1, maximumFrame.height - frameViewportDelta.height),
    )

    return WindowSizingContext(
      window: window,
      screen: screen,
      visibleFrame: visibleFrame,
      imageSize: imageSize,
      frameViewportDelta: frameViewportDelta,
      maxViewportSize: maxViewportSize,
    )
  }

  func sizesMatch(
    _ first: NSSize,
    _ second: NSSize,
    tolerance: CGFloat,
  ) -> Bool {
    abs(first.width - second.width) <= tolerance
      && abs(first.height - second.height) <= tolerance
  }

  func shouldApplyAlwaysFitToWindow(_ scrollView: NSScrollView) -> Bool {
    guard windowSizingState.suppressAlwaysFitForProgrammaticResize else { return true }
    guard let suppressedAlwaysFitViewportSize = windowSizingState.suppressedAlwaysFitViewportSize
    else { return false }

    if scrollView.contentSize.isApproximatelyEqual(to: suppressedAlwaysFitViewportSize) {
      return false
    }

    windowSizingState.suppressAlwaysFitForProgrammaticResize = false
    windowSizingState.suppressedAlwaysFitViewportSize = nil
    return true
  }

  func clearFitToScreenRestoreState() {
    windowSizingState.fitToScreenRestoreState = nil
  }
}
