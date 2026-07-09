//
//  ImageScrollView.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/20.
//

import AppKit
import SwiftUI

struct ImageScrollView: NSViewRepresentable {
  let imageContainer: ImageContainer
  let imageInfo: ImageInfo
  let viewportController: ImageViewportController
  let loadedImageWindowSizeMode: LoadedImageWindowSizeMode
  let fixedLoadedImageWindowSize: NSSize
  let fixedLoadedImageWindowSizeUnit: LoadedImageWindowSizeUnit
  let shouldApplyLoadedImageWindowSize: Bool
  @Binding var zoomScale: CGFloat
  @Binding var alwaysFitToWindow: Bool

  @AppStorage(AppSettings.Keys.backgroundColor.rawValue)
  private var backgroundColor = AppSettings.Defaults.backgroundColor

  func onZoomScaleChange(_ newZoomScale: CGFloat) {
    guard newZoomScale.isFinite else { return }

    let clampedZoomScale = newZoomScale.clamped(to: Constants.imageZoomScaleRange)
    DispatchQueue.main.async {
      guard abs(zoomScale - clampedZoomScale) > Constants.zoomScaleUpdateTolerance else { return }
      zoomScale = clampedZoomScale
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
      onZoomScaleChange: onZoomScaleChange,
      onAlwaysFitToWindowChange: onAlwaysFitToWindowChange,
    )
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = ImageNSScrollView()
    let centeringClipView = CenteringClipView()
    let clampedZoomScale = zoomScale.clamped(to: Constants.imageZoomScaleRange)
    centeringClipView.documentView = ImageCanvasView(
      imageContainer: imageContainer,
      imageInfo: imageInfo,
    )
    scrollView.contentView = centeringClipView

    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

    scrollView.drawsBackground = true
    scrollView.backgroundColor = backgroundColor.nsColor
    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = false
    scrollView.verticalScrollElasticity = .none
    scrollView.horizontalScrollElasticity = .none
    scrollView.allowsMagnification = true
    scrollView.minMagnification = Constants.imageZoomScaleRange.lowerBound
    scrollView.maxMagnification = Constants.imageZoomScaleRange.upperBound
    scrollView.usesPredominantAxisScrolling = false
    scrollView.magnification = clampedZoomScale
    context.coordinator.updateLoadedImageWindowSizeSettings(
      mode: loadedImageWindowSizeMode,
      fixedSize: fixedLoadedImageWindowSize,
      fixedSizeUnit: fixedLoadedImageWindowSizeUnit,
    )
    context.coordinator.prepareForImage(
      imageContainer,
      shouldApplyLoadedImageWindowSize: shouldApplyLoadedImageWindowSize,
    )
    context.coordinator.bind(to: viewportController)
    context.coordinator.updateAlwaysFitToWindowFromBinding(alwaysFitToWindow)
    scrollView.onLayout = { [weak coordinator = context.coordinator, weak scrollView] in
      guard let scrollView else { return }
      coordinator?.scrollViewDidLayout(scrollView)
    }
    scrollView.onLiveMagnificationStart = { [weak coordinator = context.coordinator] in
      coordinator?.beginUserMagnification()
    }
    scrollView.onLiveMagnificationEnd = { [
      weak coordinator = context.coordinator,
      weak scrollView,
    ] in
      guard let scrollView else { return }
      coordinator?.endUserMagnification(scrollView)
    }
    scrollView.onSmartMagnification = { [weak coordinator = context.coordinator] in
      coordinator?.disableAlwaysFitToWindowForUserMagnification()
    }
    scrollView.onDoubleClick = { [weak coordinator = context.coordinator] in
      coordinator?.handle(.fitToScreen)
    }
    context.coordinator.observe(scrollView)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    scrollView.backgroundColor = backgroundColor.nsColor
    context.coordinator.onZoomScaleChange = onZoomScaleChange
    context.coordinator.onAlwaysFitToWindowChange = onAlwaysFitToWindowChange
    context.coordinator.updateLoadedImageWindowSizeSettings(
      mode: loadedImageWindowSizeMode,
      fixedSize: fixedLoadedImageWindowSize,
      fixedSizeUnit: fixedLoadedImageWindowSizeUnit,
    )
    context.coordinator.updateAlwaysFitToWindowFromBinding(alwaysFitToWindow)
    context.coordinator.bind(to: viewportController)
    context.coordinator.observe(scrollView)
    let clampedZoomScale = zoomScale.clamped(to: Constants.imageZoomScaleRange)

    if let imageView = scrollView.documentView as? ImageCanvasView {
      if imageView.imageContainer.nsImage !== imageContainer.nsImage {
        imageView.imageContainer = imageContainer
        scrollView.reflectScrolledClipView(scrollView.contentView)
      }
      if imageView.imageInfo != imageInfo {
        imageView.imageInfo = imageInfo
      }
    } else {
      scrollView.documentView = ImageCanvasView(
        imageContainer: imageContainer,
        imageInfo: imageInfo,
      )
    }

    context.coordinator.prepareForImage(
      imageContainer,
      shouldApplyLoadedImageWindowSize: shouldApplyLoadedImageWindowSize,
    )
    if !context.coordinator.isLiveMagnifying || context.coordinator.hasPendingCommands {
      scrollView.layoutSubtreeIfNeeded()
    }

    if !context.coordinator.isLiveMagnifying,
       !context.coordinator.isProgrammaticZoomAnimating,
       !context.coordinator.alwaysFitToWindow, !context.coordinator.hasPendingCommands,
       abs(scrollView.magnification - clampedZoomScale) > Constants.zoomScaleUpdateTolerance
    {
      scrollView.magnification = clampedZoomScale
    }

    if !context.coordinator.isLiveMagnifying {
      context.coordinator.performPendingCommands(scrollView)
    }
  }

  static func dismantleNSView(_: NSScrollView, coordinator: Coordinator) {
    coordinator.unbindViewportController()
  }

  final class ImageNSScrollView: NSScrollView {
    var onLayout: (() -> Void)?
    var onLiveMagnificationStart: (() -> Void)?
    var onLiveMagnificationEnd: (() -> Void)?
    var onSmartMagnification: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    private var receivedMagnifyEvent = false

    override var intrinsicContentSize: NSSize {
      NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
      super.layout()
      onLayout?()
    }

    override func magnify(with event: NSEvent) {
      receivedMagnifyEvent = true
      onLiveMagnificationStart?()
      super.magnify(with: event)
    }

    override func smartMagnify(with event: NSEvent) {
      onSmartMagnification?()
      super.smartMagnify(with: event)
    }

    override func mouseDown(with event: NSEvent) {
      guard event.clickCount == 2 else {
        super.mouseDown(with: event)
        return
      }

      onDoubleClick?()
    }

    override func endGesture(with event: NSEvent) {
      super.endGesture(with: event)

      guard receivedMagnifyEvent else { return }
      receivedMagnifyEvent = false
      onLiveMagnificationEnd?()
    }

    override func mouseDragged(with event: NSEvent) {
      window?.performDrag(with: event)
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

      constrainedBounds.origin = backingAlignedPoint(constrainedBounds.origin)

      return constrainedBounds
    }
  }

  /// A coordinator class that manages the state and behavior of the `ImageScrollView`.
  final class Coordinator: NSObject, ImageViewportCommandHandling {
    var onZoomScaleChange: (CGFloat) -> Void
    var onAlwaysFitToWindowChange: (Bool) -> Void
    var alwaysFitToWindow = false

    private(set) var isLiveMagnifying = false
    private var loadedImageWindowSizeMode = AppSettings.Defaults.loadedImageWindowSizeMode
    private var fixedLoadedImageWindowSize = AppSettings.Defaults.fixedLoadedImageWindowSize
    private var fixedLoadedImageWindowSizeUnit = AppSettings.Defaults.fixedLoadedImageWindowSizeUnit
    private var imageIdentifier: ObjectIdentifier?
    private var pendingLoadedImageWindowSize = false
    private var pendingFitToWindow = false
    private var pendingFitWindowToImage = false
    private var pendingFitToScreen = false
    private var pendingRestoreFitToScreen = false
    private var pendingLiveMagnificationEnd = false
    private var pendingUserAlwaysFitDisable = false
    private var suppressAlwaysFitForProgrammaticResize = false
    private var suppressedAlwaysFitViewportSize: NSSize?
    private var fitToScreenRestoreState: FitToScreenRestoreState?
    private var isApplyingWindowFrame = false
    private var windowFrameAnimationGeneration = 0
    private var animatedZoomTarget: CGFloat?
    private var zoomAnimationGeneration = 0
    private var zoomAnimationTask: Task<Void, Never>?
    private weak var viewportController: ImageViewportController?
    private var observedScrollView: NSScrollView?
    private weak var observedWindow: NSWindow?
    private var magnificationObservation: NSKeyValueObservation?
    private var willStartLiveMagnifyObserver: NSObjectProtocol?
    private var didEndLiveMagnifyObserver: NSObjectProtocol?
    private var didEndLiveResizeObserver: NSObjectProtocol?
    private var didMoveWindowObserver: NSObjectProtocol?

    var currentZoomScale: CGFloat {
      animatedZoomTarget ?? observedScrollView?.magnification ?? 1.0
    }

    var hasPendingCommands: Bool {
      pendingLoadedImageWindowSize
        || pendingFitToWindow
        || pendingFitWindowToImage
        || pendingFitToScreen
        || pendingRestoreFitToScreen
    }

    var isProgrammaticZoomAnimating: Bool {
      animatedZoomTarget != nil
    }

    var isFitToScreenToggleActive: Bool {
      fitToScreenRestoreState != nil
    }

    private struct FitToScreenRestoreState {
      let windowFrame: NSRect
      let zoomScale: CGFloat
    }

    private struct WindowSizingContext {
      let window: NSWindow
      let screen: NSScreen?
      let visibleFrame: NSRect
      let imageSize: NSSize
      let contentViewportDelta: NSSize
      let minimumContentSize: NSSize
      let maximumContentSize: NSSize
      let maxViewportSize: NSSize
    }

    init(
      onZoomScaleChange: @escaping (CGFloat) -> Void,
      onAlwaysFitToWindowChange: @escaping (Bool) -> Void,
    ) {
      self.onZoomScaleChange = onZoomScaleChange
      self.onAlwaysFitToWindowChange = onAlwaysFitToWindowChange
    }

    deinit {
      MainActor.assumeIsolated {
        unbindViewportController()
        removeObservers()
      }
    }

    func bind(to viewportController: ImageViewportController) {
      guard self.viewportController !== viewportController else { return }

      unbindViewportController()
      self.viewportController = viewportController
      viewportController.handler = self
    }

    func unbindViewportController() {
      if viewportController?.handler === self {
        viewportController?.handler = nil
      }
      viewportController = nil
    }

    func updateLoadedImageWindowSizeSettings(
      mode: LoadedImageWindowSizeMode,
      fixedSize: NSSize,
      fixedSizeUnit: LoadedImageWindowSizeUnit,
    ) {
      loadedImageWindowSizeMode = mode
      fixedLoadedImageWindowSize = fixedSize
      fixedLoadedImageWindowSizeUnit = fixedSizeUnit
    }

    func updateAlwaysFitToWindowFromBinding(_ newAlwaysFitToWindow: Bool) {
      if pendingUserAlwaysFitDisable {
        if !newAlwaysFitToWindow {
          pendingUserAlwaysFitDisable = false
        } else {
          return
        }
      }

      if isLiveMagnifying, newAlwaysFitToWindow {
        return
      }

      alwaysFitToWindow = newAlwaysFitToWindow
    }

    func prepareForImage(
      _ imageContainer: ImageContainer,
      shouldApplyLoadedImageWindowSize: Bool,
    ) {
      let newIdentifier = ObjectIdentifier(imageContainer.nsImage)
      if imageIdentifier != newIdentifier {
        imageIdentifier = newIdentifier
        pendingFitToWindow = false
        pendingFitWindowToImage = false
        pendingFitToScreen = false
        pendingRestoreFitToScreen = false
        clearFitToScreenRestoreState()
        cancelProgrammaticZoomAnimation()
        if shouldApplyLoadedImageWindowSize {
          queueLoadedImageWindowSize()
        } else {
          pendingLoadedImageWindowSize = false
        }
      }
    }

    func scrollViewDidLayout(_ scrollView: NSScrollView) {
      observeWindowIfNeeded(scrollView.window)
      guard !isLiveMagnifying else { return }

      performPendingCommands(scrollView, shouldUpdateLayout: false)

      guard alwaysFitToWindow, !hasPendingCommands else { return }
      guard shouldApplyAlwaysFitToWindow(scrollView) else { return }

      fitToWindow(scrollView, animated: false)
    }

    func beginUserMagnification() {
      isLiveMagnifying = true
      pendingLiveMagnificationEnd = false
      pendingFitToWindow = false
      clearFitToScreenRestoreState()
      cancelProgrammaticZoomAnimation()
      disableAlwaysFitToWindowForUserMagnification()
    }

    func endUserMagnification(_ scrollView: NSScrollView) {
      guard isLiveMagnifying, !pendingLiveMagnificationEnd else { return }

      pendingLiveMagnificationEnd = true
      DispatchQueue.main.async { [weak self, weak scrollView] in
        guard let self, let scrollView else { return }

        isLiveMagnifying = false
        pendingLiveMagnificationEnd = false
        clampScrollBounds(scrollView)
        onZoomScaleChange(scrollView.magnification)
        performPendingCommands(scrollView)
      }
    }

    func disableAlwaysFitToWindowForUserMagnification() {
      guard alwaysFitToWindow else { return }

      alwaysFitToWindow = false
      pendingUserAlwaysFitDisable = true
      onAlwaysFitToWindowChange(false)
    }

    func handle(_ command: ImageViewportCommand) {
      guard let scrollView = observedScrollView else { return }

      switch command {
      case .fitToWindow:
        clearFitToScreenRestoreState()
        alwaysFitToWindow = true
        pendingUserAlwaysFitDisable = false
        onAlwaysFitToWindowChange(true)
        queueFitToWindow()

      case .fitWindowToImage:
        clearFitToScreenRestoreState()
        queueFitWindowToImage()

      case .fitToScreen:
        alwaysFitToWindow = false
        pendingUserAlwaysFitDisable = false
        onAlwaysFitToWindowChange(false)
        if isFitToScreenToggleActive {
          queueRestoreFitToScreen()
        } else {
          queueFitToScreen()
        }

      case let .setZoomScale(to: newZoomScale):
        guard newZoomScale.isFinite, !isLiveMagnifying else { return }
        clearFitToScreenRestoreState()
        applyZoomScale(newZoomScale, to: scrollView, animated: true)

      case .zoomIn:
        guard !isLiveMagnifying else { return }
        clearFitToScreenRestoreState()
        applyZoomScale(
          currentZoomScale * Constants.imageZoomStepFactor,
          to: scrollView,
          animated: true,
        )

      case .zoomOut:
        guard !isLiveMagnifying else { return }
        clearFitToScreenRestoreState()
        applyZoomScale(
          currentZoomScale * (1.0 / Constants.imageZoomStepFactor),
          to: scrollView,
          animated: true,
        )
      }

      if !isLiveMagnifying {
        performPendingCommands(scrollView)
      }
    }

    func performPendingCommands(_ scrollView: NSScrollView, shouldUpdateLayout: Bool = true) {
      guard hasPendingCommands else { return }

      if shouldUpdateLayout {
        scrollView.layoutSubtreeIfNeeded()
      }

      if applyLoadedImageWindowSizeIfNeeded(scrollView) {
        return
      }

      if fitWindowToImageIfNeeded(scrollView) {
        return
      }

      if restoreFitToScreenIfNeeded(scrollView) {
        return
      }

      if fitToScreenIfNeeded(scrollView) {
        return
      }

      if pendingFitToWindow, fitToWindow(scrollView, animated: true) {
        pendingFitToWindow = false
      }
    }

    @discardableResult
    private func fitToWindow(_ scrollView: NSScrollView, animated: Bool) -> Bool {
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

    private func fitToScreenIfNeeded(_ scrollView: NSScrollView) -> Bool {
      guard pendingFitToScreen,
            let sizingContext = windowSizingContext(for: scrollView),
            let target = fitToScreenTarget(in: sizingContext, centeringStrategy: .centerOnScreen)
      else { return false }

      pendingFitToScreen = false
      fitToScreenRestoreState = FitToScreenRestoreState(
        windowFrame: sizingContext.window.frame,
        zoomScale: currentZoomScale,
      )
      suppressAlwaysFitForProgrammaticResize = true
      suppressedAlwaysFitViewportSize = nil
      applyWindowFrame(
        scrollView,
        window: sizingContext.window,
        frame: target.frame,
        simultaneousZoomScale: target.zoomScale,
      )
      return true
    }

    private func restoreFitToScreenIfNeeded(_ scrollView: NSScrollView) -> Bool {
      guard pendingRestoreFitToScreen,
            let restoreState = fitToScreenRestoreState,
            let window = scrollView.window
      else { return false }

      pendingRestoreFitToScreen = false
      clearFitToScreenRestoreState()
      suppressAlwaysFitForProgrammaticResize = true
      suppressedAlwaysFitViewportSize = nil
      applyWindowFrame(
        scrollView,
        window: window,
        frame: window.constrainFrameRect(restoreState.windowFrame, to: window.screen),
        simultaneousZoomScale: restoreState.zoomScale,
      )
      return true
    }

    private func fitWindowToImageIfNeeded(_ scrollView: NSScrollView) -> Bool {
      guard pendingFitWindowToImage,
            let sizingContext = windowSizingContext(for: scrollView)
      else { return false }

      let targetImageDisplaySize = imageDisplaySize(
        imageSize: sizingContext.imageSize,
        zoomScale: currentZoomScale,
      )
      pendingFitWindowToImage = false
      suppressAlwaysFitForProgrammaticResize = true
      suppressedAlwaysFitViewportSize = nil
      applyWindowFrame(
        scrollView,
        window: sizingContext.window,
        frame: sizingContext.window.constrainedFrame(
          targetImageDisplaySize,
          centeringStrategy: .remain,
        ),
      )
      return true
    }

    private func applyLoadedImageWindowSizeIfNeeded(_ scrollView: NSScrollView) -> Bool {
      guard pendingLoadedImageWindowSize,
            let sizingContext = windowSizingContext(for: scrollView),
            let target = loadedImageWindowSizeTarget(in: sizingContext, scrollView: scrollView)
      else { return false }

      applyZoomScale(target.zoomScale, to: scrollView, animated: false)
      pendingLoadedImageWindowSize = false
      clearFitToScreenRestoreState()
      suppressAlwaysFitForProgrammaticResize = true
      suppressedAlwaysFitViewportSize = nil
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

      switch loadedImageWindowSizeMode {
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
        let targetFrame = sizingContext.window.constrainedFrame(
          fixedViewportSize,
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
      let targetFrame = sizingContext.window.constrainedFrame(
        targetSize,
        centeringStrategy: centeringStrategy,
      )
      return (frame: targetFrame, zoomScale: zoomScale)
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
      guard fixedLoadedImageWindowSize.width.isFinite,
            fixedLoadedImageWindowSize.height.isFinite,
            fixedLoadedImageWindowSize.width > 0,
            fixedLoadedImageWindowSize.height > 0
      else { return nil }

      let fixedSize = NSSize(
        width: fixedLoadedImageWindowSize.width,
        height: fixedLoadedImageWindowSize.height,
      )

      switch fixedLoadedImageWindowSizeUnit {
      case .points:
        return fixedSize
      case .pixels:
        return scrollView.window?.convertFromBacking(fixedSize)
      }
    }

    private func applyZoomScale(_ zoomScale: CGFloat, to scrollView: NSScrollView, animated: Bool) {
      guard let documentView = scrollView.documentView else { return }

      let targetZoomScale = zoomScale.clamped(to: Constants.imageZoomScaleRange)
      let center = imageCenter(in: documentView)
      let zoomScaleDelta = abs(currentZoomScale - targetZoomScale)
      let replacesAnimatedTarget = animatedZoomTarget.map {
        abs($0 - targetZoomScale) > Constants.zoomScaleUpdateTolerance
      } ?? false

      guard zoomScaleDelta > Constants.zoomScaleUpdateTolerance || replacesAnimatedTarget
      else { return }

      if animated {
        zoomAnimationGeneration += 1
        let animationGeneration = zoomAnimationGeneration
        zoomAnimationTask?.cancel()
        zoomAnimationTask = nil
        animatedZoomTarget = targetZoomScale
        onZoomScaleChange(targetZoomScale)
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.3
          context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
          scrollView.animator().setMagnification(targetZoomScale, centeredAt: center)
        } completionHandler: { [weak self, weak scrollView] in
          Task { @MainActor [weak self, weak scrollView] in
            guard let self, let scrollView else { return }
            guard zoomAnimationGeneration == animationGeneration else { return }

            animatedZoomTarget = nil
            zoomAnimationTask = nil
            clampScrollBounds(scrollView)
            onZoomScaleChange(scrollView.magnification)
          }
        }
      } else {
        cancelProgrammaticZoomAnimation()
        scrollView.setMagnification(targetZoomScale, centeredAt: center)
        clampScrollBounds(scrollView)
        onZoomScaleChange(scrollView.magnification)
      }
    }

    private func animateZoomScale(
      _ zoomScale: CGFloat,
      to scrollView: NSScrollView,
      duration: TimeInterval,
    ) -> Int? {
      guard let documentView = scrollView.documentView else { return nil }

      let targetZoomScale = zoomScale.clamped(to: Constants.imageZoomScaleRange)
      let startZoomScale = scrollView.magnification
      let zoomScaleDelta = abs(startZoomScale - targetZoomScale)
      let replacesAnimatedTarget = animatedZoomTarget.map {
        abs($0 - targetZoomScale) > Constants.zoomScaleUpdateTolerance
      } ?? false

      guard zoomScaleDelta > Constants.zoomScaleUpdateTolerance || replacesAnimatedTarget
      else { return nil }

      zoomAnimationGeneration += 1
      let animationGeneration = zoomAnimationGeneration
      let imageCenter = imageCenter(in: documentView)
      let animationDuration = max(0, duration)
      zoomAnimationTask?.cancel()
      animatedZoomTarget = targetZoomScale
      onZoomScaleChange(targetZoomScale)

      guard animationDuration > 0 else {
        finishZoomScale(
          targetZoomScale,
          to: scrollView,
          centeredAt: imageCenter,
          animationGeneration: animationGeneration,
        )
        return animationGeneration
      }

      zoomAnimationTask = Task { @MainActor [weak self, weak scrollView] in
        guard let self, let scrollView else { return }

        let startTime = CACurrentMediaTime()
        while !Task.isCancelled {
          guard zoomAnimationGeneration == animationGeneration else { return }

          let elapsedTime = CACurrentMediaTime() - startTime
          let progress = min(1, CGFloat(elapsedTime / animationDuration))
          let easedProgress = easeInEaseOut(progress)
          let currentZoomScale = startZoomScale
            + (targetZoomScale - startZoomScale) * easedProgress
          scrollView.setMagnification(currentZoomScale, centeredAt: imageCenter)

          guard progress < 1 else { break }
          try? await Task.sleep(for: .milliseconds(16))
        }

        guard !Task.isCancelled else { return }
        finishZoomScale(
          targetZoomScale,
          to: scrollView,
          centeredAt: imageCenter,
          animationGeneration: animationGeneration,
        )
      }

      return animationGeneration
    }

    private func finishZoomScale(
      _ zoomScale: CGFloat,
      to scrollView: NSScrollView,
      centeredAt center: NSPoint,
      animationGeneration: Int,
    ) {
      guard zoomAnimationGeneration == animationGeneration else { return }

      zoomAnimationTask?.cancel()
      zoomAnimationTask = nil
      scrollView.setMagnification(zoomScale, centeredAt: center)
      animatedZoomTarget = nil
      clampScrollBounds(scrollView)
      onZoomScaleChange(scrollView.magnification)
    }

    private func easeInEaseOut(_ progress: CGFloat) -> CGFloat {
      let clampedProgress = progress.clamped(to: 0 ... 1)
      return clampedProgress * clampedProgress * (3 - 2 * clampedProgress)
    }

    private func imageCenter(in documentView: NSView) -> NSPoint {
      NSPoint(x: documentView.bounds.midX, y: documentView.bounds.midY)
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
      let contentSize = window.contentView?.bounds.size ?? window.contentLayoutRect.size
      let contentViewportDelta = NSSize(
        width: max(0, contentSize.width - viewportSize.width),
        height: max(0, contentSize.height - viewportSize.height),
      )
      let minimumContentSize = NSSize(
        width: max(window.contentMinSize.width, Constants.minimumWindowContentWidth),
        height: max(window.contentMinSize.height, Constants.minimumWindowContentHeight),
      )
      let maximumFrame = window.constrainFrameRect(visibleFrame, to: screen)
      let maximumWindowContentSize = window.contentRect(forFrameRect: maximumFrame).size
      let maximumContentSize = NSSize(
        width: max(1, maximumWindowContentSize.width),
        height: max(1, maximumWindowContentSize.height),
      )
      let maxViewportSize = NSSize(
        width: max(1, maximumContentSize.width - contentViewportDelta.width),
        height: max(1, maximumContentSize.height - contentViewportDelta.height),
      )

      return WindowSizingContext(
        window: window,
        screen: screen,
        visibleFrame: visibleFrame,
        imageSize: imageSize,
        contentViewportDelta: contentViewportDelta,
        minimumContentSize: minimumContentSize,
        maximumContentSize: maximumContentSize,
        maxViewportSize: maxViewportSize,
      )
    }

    private func applyWindowFrame(
      _ scrollView: NSScrollView,
      window: NSWindow,
      frame: NSRect,
      simultaneousZoomScale: CGFloat? = nil,
    ) {
      DispatchQueue.main.async { [weak self, weak scrollView, weak window] in
        guard let self, let scrollView, let window else { return }

        windowFrameAnimationGeneration += 1
        let animationGeneration = windowFrameAnimationGeneration
        let duration = window.animationResizeTime(frame)
        if duration <= 0 {
          window.setFrame(frame, display: false)
          if let simultaneousZoomScale {
            applyZoomScale(simultaneousZoomScale, to: scrollView, animated: true)
          }
          clampScrollBounds(scrollView)
          onZoomScaleChange(scrollView.magnification)
          return
        }

        let simultaneousZoomAnimationGeneration: Int? = if let simultaneousZoomScale {
          animateZoomScale(
            simultaneousZoomScale,
            to: scrollView,
            duration: duration,
          )
        } else {
          nil
        }
        isApplyingWindowFrame = true

        NSAnimationContext.runAnimationGroup { context in
          context.duration = duration
          context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
          window.animator().setFrame(frame, display: false)
        } completionHandler: { [weak self, weak scrollView] in
          Task { @MainActor [weak self, weak scrollView] in
            guard let self else { return }
            guard windowFrameAnimationGeneration == animationGeneration else { return }

            isApplyingWindowFrame = false
            guard let scrollView else { return }

            scrollView.layoutSubtreeIfNeeded()
            suppressedAlwaysFitViewportSize = scrollView.contentSize
            if let simultaneousZoomScale,
               let simultaneousZoomAnimationGeneration
            {
              guard let documentView = scrollView.documentView else { return }

              finishZoomScale(
                simultaneousZoomScale.clamped(to: Constants.imageZoomScaleRange),
                to: scrollView,
                centeredAt: imageCenter(in: documentView),
                animationGeneration: simultaneousZoomAnimationGeneration,
              )
            } else {
              clampScrollBounds(scrollView)
              onZoomScaleChange(scrollView.magnification)
            }
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

    private func cancelProgrammaticZoomAnimation() {
      zoomAnimationGeneration += 1
      zoomAnimationTask?.cancel()
      zoomAnimationTask = nil
      animatedZoomTarget = nil
    }

    private func queueLoadedImageWindowSize() {
      pendingLoadedImageWindowSize = true
    }

    private func queueFitToWindow() {
      pendingFitToWindow = true
    }

    private func queueFitWindowToImage() {
      pendingFitWindowToImage = true
    }

    private func queueFitToScreen() {
      pendingFitToScreen = true
      pendingRestoreFitToScreen = false
    }

    private func queueRestoreFitToScreen() {
      pendingRestoreFitToScreen = true
      pendingFitToScreen = false
    }

    private func clearFitToScreenRestoreState() {
      fitToScreenRestoreState = nil
    }

    func observe(_ scrollView: NSScrollView) {
      guard observedScrollView !== scrollView else { return }

      removeObservers()
      observedScrollView = scrollView
      observeWindowIfNeeded(scrollView.window)
      magnificationObservation = scrollView
        .observe(\.magnification, options: [.new]) { [weak self] scrollView, _ in
          Task { @MainActor [weak self, weak scrollView] in
            guard let self, let scrollView else { return }
            guard !isProgrammaticZoomAnimating else { return }

            onZoomScaleChange(scrollView.magnification)
          }
        }

      willStartLiveMagnifyObserver = NotificationCenter.default.addObserver(
        forName: NSScrollView.willStartLiveMagnifyNotification,
        object: scrollView,
        queue: .main,
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.beginUserMagnification()
        }
      }

      didEndLiveMagnifyObserver = NotificationCenter.default.addObserver(
        forName: NSScrollView.didEndLiveMagnifyNotification,
        object: scrollView,
        queue: .main,
      ) { [weak self, weak scrollView] _ in
        Task { @MainActor [weak self, weak scrollView] in
          guard let self, let scrollView else { return }

          endUserMagnification(scrollView)
        }
      }
    }

    private func observeWindowIfNeeded(_ window: NSWindow?) {
      guard observedWindow !== window else { return }

      removeWindowObservers()
      observedWindow = window
      guard let window else { return }

      didEndLiveResizeObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.didEndLiveResizeNotification,
        object: window,
        queue: .main,
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          guard let self, !isApplyingWindowFrame else { return }

          clearFitToScreenRestoreState()
        }
      }

      didMoveWindowObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.didMoveNotification,
        object: window,
        queue: .main,
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          guard let self, !isApplyingWindowFrame else { return }

          clearFitToScreenRestoreState()
        }
      }
    }

    private func removeObservers() {
      if let willStartLiveMagnifyObserver {
        NotificationCenter.default.removeObserver(willStartLiveMagnifyObserver)
        self.willStartLiveMagnifyObserver = nil
      }

      if let didEndLiveMagnifyObserver {
        NotificationCenter.default.removeObserver(didEndLiveMagnifyObserver)
        self.didEndLiveMagnifyObserver = nil
      }

      removeWindowObservers()
    }

    private func removeWindowObservers() {
      if let didEndLiveResizeObserver {
        NotificationCenter.default.removeObserver(didEndLiveResizeObserver)
        self.didEndLiveResizeObserver = nil
      }
      if let didMoveWindowObserver {
        NotificationCenter.default.removeObserver(didMoveWindowObserver)
        self.didMoveWindowObserver = nil
      }
      observedWindow = nil
    }
  }
}
