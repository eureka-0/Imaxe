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
  @Binding var scale: CGFloat
  @Binding var alwaysFitToWindow: Bool

  func onScaleChange(_ newScale: CGFloat) {
    guard newScale.isFinite else { return }

    let clampedScale = newScale.clamped(to: Constants.imageScaleRange)
    DispatchQueue.main.async {
      guard abs(scale - clampedScale) > Constants.scaleUpdateTolerance else { return }
      scale = clampedScale
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
    let clampedScale = scale.clamped(to: Constants.imageScaleRange)
    centeringClipView.documentView = ImageCanvasView(
      imageContainer: imageContainer,
      imageInfo: imageInfo,
      scale: clampedScale,
    )
    scrollView.contentView = centeringClipView

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
    scrollView.magnification = clampedScale
    context.coordinator.updateLoadedImageWindowSizeSettings(
      mode: loadedImageWindowSizeMode,
      fixedSize: fixedLoadedImageWindowSize,
      fixedSizeUnit: fixedLoadedImageWindowSizeUnit,
    )
    context.coordinator.prepareForImage(imageContainer)
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
    context.coordinator.onScaleChange = onScaleChange
    context.coordinator.onAlwaysFitToWindowChange = onAlwaysFitToWindowChange
    context.coordinator.updateLoadedImageWindowSizeSettings(
      mode: loadedImageWindowSizeMode,
      fixedSize: fixedLoadedImageWindowSize,
      fixedSizeUnit: fixedLoadedImageWindowSizeUnit,
    )
    context.coordinator.updateAlwaysFitToWindowFromBinding(alwaysFitToWindow)
    context.coordinator.bind(to: viewportController)
    context.coordinator.observe(scrollView)
    let clampedScale = scale.clamped(to: Constants.imageScaleRange)

    if let imageView = scrollView.documentView as? ImageCanvasView {
      if imageView.imageContainer.nsImage !== imageContainer.nsImage {
        imageView.imageContainer = imageContainer
        scrollView.reflectScrolledClipView(scrollView.contentView)
      }
      if imageView.imageInfo != imageInfo {
        imageView.imageInfo = imageInfo
      }
      imageView.scale = clampedScale
    } else {
      scrollView.documentView = ImageCanvasView(
        imageContainer: imageContainer,
        imageInfo: imageInfo,
        scale: clampedScale,
      )
    }

    context.coordinator.prepareForImage(imageContainer)
    if !context.coordinator.isLiveMagnifying || context.coordinator.hasPendingCommands {
      scrollView.layoutSubtreeIfNeeded()
    }

    if !context.coordinator.isLiveMagnifying,
       !context.coordinator.alwaysFitToWindow, !context.coordinator.hasPendingCommands,
       abs(scrollView.magnification - clampedScale) > Constants.scaleUpdateTolerance
    {
      scrollView.magnification = clampedScale
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
    var onScaleChange: (CGFloat) -> Void
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
    private weak var viewportController: ImageViewportController?
    private var observedScrollView: NSScrollView?
    private var magnificationObservation: NSKeyValueObservation?
    private var willStartLiveMagnifyObserver: NSObjectProtocol?
    private var didEndLiveMagnifyObserver: NSObjectProtocol?

    var hasPendingCommands: Bool {
      pendingLoadedImageWindowSize
        || pendingFitToWindow
        || pendingFitWindowToImage
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
      onScaleChange: @escaping (CGFloat) -> Void,
      onAlwaysFitToWindowChange: @escaping (Bool) -> Void,
    ) {
      self.onScaleChange = onScaleChange
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

    func prepareForImage(_ imageContainer: ImageContainer) {
      let newIdentifier = ObjectIdentifier(imageContainer.nsImage)
      if imageIdentifier != newIdentifier {
        imageIdentifier = newIdentifier
        pendingFitToWindow = false
        pendingFitWindowToImage = false
        queueLoadedImageWindowSize()
      }
    }

    func scrollViewDidLayout(_ scrollView: NSScrollView) {
      guard !isLiveMagnifying else { return }

      performPendingCommands(scrollView, shouldUpdateLayout: false)

      guard alwaysFitToWindow, !hasPendingCommands else { return }
      guard shouldApplyAlwaysFitToWindow(scrollView) else { return }

      fitToWindow(scrollView)
    }

    func beginUserMagnification() {
      isLiveMagnifying = true
      pendingLiveMagnificationEnd = false
      pendingFitToWindow = false
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
        onScaleChange(scrollView.magnification)
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
      switch command {
      case .fitToWindow:
        alwaysFitToWindow = true
        pendingUserAlwaysFitDisable = false
        onAlwaysFitToWindowChange(true)
        queueFitToWindow()

      case .fitWindowToImage:
        queueFitWindowToImage()
      }

      guard !isLiveMagnifying, let scrollView = observedScrollView else { return }

      performPendingCommands(scrollView)
    }

    func performPendingCommands(_ scrollView: NSScrollView, shouldUpdateLayout: Bool = true) {
      guard hasPendingCommands else { return }

      if shouldUpdateLayout {
        scrollView.layoutSubtreeIfNeeded()
      }

      if applyLoadedImageWindowSizeIfNeeded(scrollView) { return }

      if fitWindowToImageIfNeeded(scrollView) { return }

      if pendingFitToWindow, fitToWindow(scrollView) {
        pendingFitToWindow = false
      }
    }

    @discardableResult private func fitToWindow(_ scrollView: NSScrollView) -> Bool {
      guard let documentView = scrollView.documentView else { return false }

      let viewportSize = scrollView.contentSize
      let imageSize = documentView.bounds.size

      guard viewportSize.width > 0,
            viewportSize.height > 0,
            imageSize.width > 0,
            imageSize.height > 0
      else { return false }

      let fitScale = min(
        viewportSize.width / imageSize.width, viewportSize.height / imageSize.height,
      )
      applyScale(fitScale, to: scrollView)
      return true
    }

    private func fitWindowToImageIfNeeded(_ scrollView: NSScrollView) -> Bool {
      guard pendingFitWindowToImage,
            let documentView = scrollView.documentView,
            let sizingContext = windowSizingContext(for: scrollView)
      else { return false }

      let currentScale = scrollView.magnification.clamped(to: Constants.imageScaleRange)
      let targetImageDisplaySize = NSSize(
        width: documentView.bounds.width * currentScale,
        height: documentView.bounds.height * currentScale,
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

      applyScale(target.scale, to: scrollView)
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
      in sizingContext: WindowSizingContext, scrollView: NSScrollView,
    ) -> (frame: NSRect, scale: CGFloat)? {
      let imageSize = sizingContext.imageSize
      let fitScale = min(
        sizingContext.maxViewportSize.width / imageSize.width,
        sizingContext.maxViewportSize.height / imageSize.height,
      )
      let fillScale = max(
        sizingContext.maxViewportSize.width / imageSize.width,
        sizingContext.maxViewportSize.height / imageSize.height,
      )

      switch loadedImageWindowSizeMode {
      case .actualSizeLimitedToScreen:
        let targetScale = min(1.0, fitScale).clamped(to: Constants.imageScaleRange)
        let targetSize = NSSize(
          width: imageSize.width * targetScale,
          height: imageSize.height * targetScale,
        )
        let targetFrame = sizingContext.window.centeredConstrainedFrame(targetSize)
        return (frame: targetFrame, scale: targetScale)

      case .scaleToFitScreen:
        let targetScale = fitScale.clamped(to: Constants.imageScaleRange)
        let targetSize = NSSize(
          width: imageSize.width * targetScale,
          height: imageSize.height * targetScale,
        )
        let targetFrame = sizingContext.window.centeredConstrainedFrame(targetSize)
        return (frame: targetFrame, scale: targetScale)

      case .fillScreen:
        let targetScale = fillScale.clamped(to: Constants.imageScaleRange)
        let frame = sizingContext.window.constrainFrameRect(
          sizingContext.visibleFrame,
          to: sizingContext.screen,
        )
        return (frame: frame, scale: targetScale)

      case .actualSize:
        let targetScale = CGFloat(1.0).clamped(to: Constants.imageScaleRange)
        let targetSize = NSSize(width: imageSize.width, height: imageSize.height)
        let targetFrame = sizingContext.window.centeredConstrainedFrame(targetSize)
        return (frame: targetFrame, scale: targetScale)

      case .fixedSize:
        guard let fixedViewportSize = fixedViewportSize(in: scrollView) else { return nil }

        let targetScale = min(
          fixedViewportSize.width / imageSize.width,
          fixedViewportSize.height / imageSize.height,
        )
        .clamped(to: Constants.imageScaleRange)
        let targetFrame = sizingContext.window.centeredConstrainedFrame(fixedViewportSize)
        return (frame: targetFrame, scale: targetScale)
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

    private func applyScale(_ scale: CGFloat, to scrollView: NSScrollView) {
      guard let documentView = scrollView.documentView else { return }

      let targetScale = scale.clamped(to: Constants.imageScaleRange)
      let imageSize = documentView.bounds.size
      let center = NSPoint(x: imageSize.width / 2.0, y: imageSize.height / 2.0)
      let scaleDelta = abs(scrollView.magnification - targetScale)
      if scaleDelta > Constants.scaleUpdateTolerance {
        scrollView.setMagnification(targetScale, centeredAt: center)
        clampScrollBounds(scrollView)
        onScaleChange(scrollView.magnification)
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

    private func scaleToEliminateBlankSpaceIfNeeded(_ scrollView: NSScrollView) {
      guard let documentView = scrollView.documentView else { return }

      let viewportSize = scrollView.contentSize
      let imageSize = documentView.bounds.size

      guard viewportSize.width > 0,
            viewportSize.height > 0,
            imageSize.width > 0,
            imageSize.height > 0
      else { return }

      let widthDelta = viewportSize.width - imageSize.width
      let heightDelta = viewportSize.height - imageSize.height
      let fitScale: CGFloat? = if widthDelta > 0, widthDelta < 1.0 {
        viewportSize.width / imageSize.width
      } else if heightDelta > 0, heightDelta < 1.0 {
        viewportSize.height / imageSize.height
      } else {
        nil
      }

      guard let fitScale else { return }

      applyScale(fitScale, to: scrollView)
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

            scaleToEliminateBlankSpaceIfNeeded(scrollView)
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
            onScaleChange(scrollView.magnification)
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
