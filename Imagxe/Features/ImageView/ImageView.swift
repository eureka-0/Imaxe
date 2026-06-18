//
//  ImageView.swift
//  Imagxe
//
//  Created by lxlong on 2026/6/17.
//

import AppKit
import SwiftUI

struct ImageView: View {
  @State private(set) var viewModel = ImageViewModel()

  let image: NSImage

  var body: some View {
    ZStack(alignment: .top) {
      ImageScrollView(
        image: image,
        fitToWindowRequest: viewModel.fitToWindowRequest,
        fitWindowToImageRequest: viewModel.fitWindowToImageRequest,
        scale: $viewModel.imageScale,
        alwaysFitToWindow: $viewModel.alwaysFitToWindow,
      )

      topBar
        .opacity(viewModel.showTopBar ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showTopBar)
        .allowsHitTesting(viewModel.showTopBar)

      HoverTrackingStrip { isHovering in
        viewModel.setTopBarVisibility(to: isHovering)
      }
      .frame(maxWidth: .infinity)
      .frame(height: Constants.topBarHoverStripHeight)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      viewModel.setTopBarVisibility(to: false)

      DispatchQueue.main.async {
        viewModel.currentImage = image
        viewModel.fitToWindow()
      }
    }
  }
}

private struct HoverTrackingStrip: NSViewRepresentable {
  let onHoverChange: (Bool) -> Void

  func makeNSView(context _: Context) -> HoverTrackingNSView {
    let view = HoverTrackingNSView()
    view.onHoverChange = onHoverChange
    return view
  }

  func updateNSView(_ nsView: HoverTrackingNSView, context _: Context) {
    nsView.onHoverChange = onHoverChange
  }

  final class HoverTrackingNSView: NSView {
    var onHoverChange: ((Bool) -> Void)?

    private var isHovering = false
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
      nil
    }

    override func hitTest(_: NSPoint) -> NSView? {
      nil
    }

    override func updateTrackingAreas() {
      if let trackingArea {
        removeTrackingArea(trackingArea)
      }

      let trackingArea = NSTrackingArea(
        rect: .zero,
        options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
        owner: self,
        userInfo: nil,
      )
      addTrackingArea(trackingArea)
      self.trackingArea = trackingArea

      super.updateTrackingAreas()
    }

    override func mouseEntered(with _: NSEvent) {
      setHovering(true)
    }

    override func mouseExited(with _: NSEvent) {
      setHovering(false)
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()

      if window == nil {
        setHovering(false)
      }
    }

    private func setHovering(_ isHovering: Bool) {
      guard self.isHovering != isHovering else { return }

      self.isHovering = isHovering
      onHoverChange?(isHovering)
    }
  }
}

struct ImageScrollView: NSViewRepresentable {
  let image: NSImage
  let fitToWindowRequest: Int
  let fitWindowToImageRequest: Int
  @Binding var scale: CGFloat
  @Binding var alwaysFitToWindow: Bool

  private let minScale: CGFloat = 0.05
  private let maxScale: CGFloat = 16.0
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
    centeringClipView.documentView = PixelImageView(image: image, scale: scale)
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
    scrollView.minMagnification = minScale
    scrollView.maxMagnification = maxScale
    scrollView.usesPredominantAxisScrolling = false
    scrollView.magnification = scale.clamped(to: minScale ... maxScale)
    context.coordinator.prepareForImage(
      image,
      fitToWindowRequest: fitToWindowRequest,
      fitWindowToImageRequest: fitWindowToImageRequest,
    )
    context.coordinator.alwaysFitToWindow = alwaysFitToWindow
    scrollView.onLayout = { [weak coordinator = context.coordinator, weak scrollView] in
      guard let scrollView else { return }
      coordinator?.scrollViewDidLayout(scrollView, minScale: minScale, maxScale: maxScale)
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

    if let imageView = scrollView.documentView as? PixelImageView {
      imageView.image = image
      imageView.scale = scale
      scrollView.reflectScrolledClipView(scrollView.contentView)
    } else {
      scrollView.documentView = PixelImageView(image: image, scale: scale)
    }

    context.coordinator.prepareForImage(
      image,
      fitToWindowRequest: fitToWindowRequest,
      fitWindowToImageRequest: fitWindowToImageRequest,
    )
    scrollView.layoutSubtreeIfNeeded()

    let clampedScale = scale.clamped(to: minScale ... maxScale)
    if !alwaysFitToWindow, !context.coordinator.hasPendingRequests,
       scrollView.magnification != clampedScale
    {
      scrollView.magnification = clampedScale
    }

    context.coordinator.performPendingRequests(scrollView, minScale: minScale, maxScale: maxScale)
  }

  final class ImageNSScrollView: NSScrollView {
    var onLayout: (() -> Void)?
    var onUserMagnification: (() -> Void)?

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
}

private final class PixelImageView: NSView {
  var image: NSImage {
    didSet {
      frame.size = image.pixelSize
      needsDisplay = true
    }
  }

  var scale: CGFloat

  override var isFlipped: Bool {
    true
  }

  init(image: NSImage, scale: CGFloat) {
    self.image = image
    self.scale = scale
    super.init(frame: NSRect(origin: .zero, size: image.pixelSize))
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    nil
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.clear.setFill()
    dirtyRect.fill()

    if let currentContext = NSGraphicsContext.current {
      currentContext.imageInterpolation = scale > 1.0 ? .none : .high

      let cgContext = currentContext.cgContext
      cgContext.setShouldAntialias(false)
      cgContext.interpolationQuality = scale > 1.0 ? .none : .high
    }
    image.draw(
      in: bounds,
      from: NSRect(origin: .zero, size: image.size),
      operation: .copy,
      fraction: 1.0,
      respectFlipped: true,
      hints: nil,
    )
  }
}
