//
//  ImageScrollView.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/20.
//

import AppKit
import SwiftUI

// MARK: - ImageScrollView

/// A SwiftUI view that wraps an `NSScrollView` for displaying and interacting with an image. All
/// gestures and interactions are handled by the `NSScrollView` and its coordinator, while
/// `ImageViewportController` provides a way to send commands to the scroll view from outside the
/// view hierarchy. The `ImageScrollView` is designed to be used in a SwiftUI context, allowing for
/// easy integration with other SwiftUI views and state management.
struct ImageScrollView: NSViewRepresentable {
  typealias Coordinator = ImageScrollViewCoordinator
  typealias NSViewType = NSScrollView

  let imageContainer: ImageContainer
  let imageInfo: ImageInfo
  let shouldApplyLoadedImageWindowSize: Bool
  var viewportController: ImageViewportController?
  @Binding var zoomScale: CGFloat
  @Binding var alwaysFitToWindow: Bool

  @AppStorage(AppSettings.Keys.backgroundColor.rawValue)
  private var backgroundColor = AppSettings.Defaults.backgroundColor

  @AppStorage(AppSettings.Keys.loadedImageWindowSizeMode.rawValue)
  private var loadedImageWindowSizeMode = AppSettings.Defaults.loadedImageWindowSizeMode

  @AppStorage(AppSettings.Keys.fixedLoadedImageWindowWidth.rawValue)
  private var fixedLoadedImageWindowWidth = AppSettings.Defaults.fixedLoadedImageWindowWidth

  @AppStorage(AppSettings.Keys.fixedLoadedImageWindowHeight.rawValue)
  private var fixedLoadedImageWindowHeight = AppSettings.Defaults.fixedLoadedImageWindowHeight

  @AppStorage(AppSettings.Keys.fixedLoadedImageWindowSizeUnit.rawValue)
  private var fixedLoadedImageWindowSizeUnit = AppSettings.Defaults.fixedLoadedImageWindowSizeUnit

  private var fixedLoadedImageWindowSize: NSSize {
    NSSize(
      width: AppSettings.normalizedFixedLoadedImageWindowDimension(
        fixedLoadedImageWindowWidth,
        minimum: Constants.minimumWindowContentWidth,
      ),
      height: AppSettings.normalizedFixedLoadedImageWindowDimension(
        fixedLoadedImageWindowHeight,
        minimum: Constants.minimumWindowContentHeight,
      ),
    )
  }

  func onZoomScaleChange(_ newZoomScale: CGFloat) {
    guard newZoomScale.isFinite else { return }

    let clampedZoomScale = newZoomScale.clamped(to: Constants.imageZoomScaleRange)

    DispatchQueue.main.async {
      guard abs(zoomScale - clampedZoomScale) > Constants
        .zoomScaleUpdateTolerance else { return }
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
    let centeringClipView = ImageClipView()
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
    if let viewportController {
      context.coordinator.bind(to: viewportController)
    }
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
    if let viewportController {
      context.coordinator.bind(to: viewportController)
    }
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

  /// A custom `NSScrollView` subclass that provides hooks for various events and gestures, allowing
  /// the coordinator to respond appropriately. It also overrides certain behaviors to ensure the
  /// image is displayed and interacted with correctly.
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

  final class ImageClipView: NSClipView {
    /// Override constrainBoundsRect to allow the document view to be centered when it is smaller
    /// than the clip view.
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
}

// MARK: - Modifiers

extension ImageScrollView {
  func viewportController(_ viewportController: ImageViewportController) -> ImageScrollView {
    var view = self
    view.viewportController = viewportController
    return view
  }
}
