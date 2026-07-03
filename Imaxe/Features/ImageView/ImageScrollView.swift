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
    private var pendingLiveMagnificationEnd = false
    private var pendingUserAlwaysFitDisable = false
    private var suppressAlwaysFitForProgrammaticResize = false
    private var suppressedAlwaysFitViewportSize: NSSize?
    private var animatedZoomTarget: CGFloat?
    private var zoomAnimationGeneration = 0
    private weak var viewportController: ImageViewportController?
    private var observedScrollView: NSScrollView?
    private var magnificationObservation: NSKeyValueObservation?
    private var willStartLiveMagnifyObserver: NSObjectProtocol?
    private var didEndLiveMagnifyObserver: NSObjectProtocol?

    var currentZoomScale: CGFloat {
      animatedZoomTarget ?? observedScrollView?.magnification ?? 1.0
    }

    var hasPendingCommands: Bool {
      pendingLoadedImageWindowSize
        || pendingFitToWindow
        || pendingFitWindowToImage
    }

    var isProgrammaticZoomAnimating: Bool {
      animatedZoomTarget != nil
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
        removeLiveMagnifyObservers()
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
        cancelProgrammaticZoomAnimation()
        if shouldApplyLoadedImageWindowSize {
          queueLoadedImageWindowSize()
        } else {
          pendingLoadedImageWindowSize = false
        }
      }
    }

    func scrollViewDidLayout(_ scrollView: NSScrollView) {
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
        alwaysFitToWindow = true
        pendingUserAlwaysFitDisable = false
        onAlwaysFitToWindowChange(true)
        queueFitToWindow()

      case .fitWindowToImage:
        queueFitWindowToImage()

      case let .setZoomScale(to: newZoomScale):
        guard newZoomScale.isFinite, !isLiveMagnifying else { return }
        applyZoomScale(newZoomScale, to: scrollView, animated: true)

      case .zoomIn:
        guard !isLiveMagnifying else { return }
        applyZoomScale(
          currentZoomScale * Constants.imageZoomStepFactor,
          to: scrollView,
          animated: true,
        )

      case .zoomOut:
        guard !isLiveMagnifying else { return }
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

      if applyLoadedImageWindowSizeIfNeeded(scrollView) { return }

      if fitWindowToImageIfNeeded(scrollView) { return }

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

    private func fitWindowToImageIfNeeded(_ scrollView: NSScrollView) -> Bool {
      guard pendingFitWindowToImage,
            let documentView = scrollView.documentView,
            let sizingContext = windowSizingContext(for: scrollView)
      else { return false }

      let targetImageDisplaySize = NSSize(
        width: (documentView.bounds.width * currentZoomScale).rounded(),
        height: (documentView.bounds.height * currentZoomScale).rounded(),
      )
      pendingFitWindowToImage = false
      suppressAlwaysFitForProgrammaticResize = true
      suppressedAlwaysFitViewportSize = nil
      applyWindowFrame(
        scrollView,
        window: sizingContext.window,
        frame: sizingContext.window.centeredConstrainedFrame(targetImageDisplaySize),
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
      let fitZoomScale = min(
        sizingContext.maxViewportSize.width / imageSize.width,
        sizingContext.maxViewportSize.height / imageSize.height,
      )
      let fillZoomScale = max(
        sizingContext.maxViewportSize.width / imageSize.width,
        sizingContext.maxViewportSize.height / imageSize.height,
      )

      switch loadedImageWindowSizeMode {
      case .actualSizeLimitedToScreen:
        let targetZoomScale = min(1.0, fitZoomScale).clamped(to: Constants.imageZoomScaleRange)
        let targetSize = NSSize(
          width: imageSize.width * targetZoomScale,
          height: imageSize.height * targetZoomScale,
        )
        let targetFrame = sizingContext.window.centeredConstrainedFrame(targetSize)
        return (frame: targetFrame, zoomScale: targetZoomScale)

      case .zoomToFitScreen:
        let targetZoomScale = fitZoomScale.clamped(to: Constants.imageZoomScaleRange)
        let targetSize = NSSize(
          width: imageSize.width * targetZoomScale,
          height: imageSize.height * targetZoomScale,
        )
        let targetFrame = sizingContext.window.centeredConstrainedFrame(targetSize)
        return (frame: targetFrame, zoomScale: targetZoomScale)

      case .fillScreen:
        let targetZoomScale = fillZoomScale.clamped(to: Constants.imageZoomScaleRange)
        let frame = sizingContext.window.constrainFrameRect(
          sizingContext.visibleFrame,
          to: sizingContext.screen,
        )
        return (frame: frame, zoomScale: targetZoomScale)

      case .actualSize:
        let targetZoomScale = CGFloat(1.0).clamped(to: Constants.imageZoomScaleRange)
        let targetSize = NSSize(width: imageSize.width, height: imageSize.height)
        let targetFrame = sizingContext.window.centeredConstrainedFrame(targetSize)
        return (frame: targetFrame, zoomScale: targetZoomScale)

      case .fixedSize:
        guard let fixedViewportSize = fixedViewportSize(in: scrollView) else { return nil }

        let targetZoomScale = min(
          fixedViewportSize.width / imageSize.width,
          fixedViewportSize.height / imageSize.height,
        )
        .clamped(to: Constants.imageZoomScaleRange)
        let targetFrame = sizingContext.window.centeredConstrainedFrame(fixedViewportSize)
        return (frame: targetFrame, zoomScale: targetZoomScale)
      }
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
      let imageSize = documentView.bounds.size
      let center = NSPoint(x: imageSize.width / 2.0, y: imageSize.height / 2.0)
      let zoomScaleDelta = abs(currentZoomScale - targetZoomScale)
      let replacesAnimatedTarget = animatedZoomTarget.map {
        abs($0 - targetZoomScale) > Constants.zoomScaleUpdateTolerance
      } ?? false

      guard zoomScaleDelta > Constants.zoomScaleUpdateTolerance || replacesAnimatedTarget
      else { return }

      if animated {
        zoomAnimationGeneration += 1
        let animationGeneration = zoomAnimationGeneration
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
            onZoomScaleChange(scrollView.magnification)
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

    func observe(_ scrollView: NSScrollView) {
      guard observedScrollView !== scrollView else { return }

      removeLiveMagnifyObservers()
      observedScrollView = scrollView
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

    private func removeLiveMagnifyObservers() {
      if let willStartLiveMagnifyObserver {
        NotificationCenter.default.removeObserver(willStartLiveMagnifyObserver)
        self.willStartLiveMagnifyObserver = nil
      }

      if let didEndLiveMagnifyObserver {
        NotificationCenter.default.removeObserver(didEndLiveMagnifyObserver)
        self.didEndLiveMagnifyObserver = nil
      }
    }
  }
}
