//
//  ImageView.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/17.
//

import AppKit
import PocketSVG
import SwiftUI

struct ImageView: View {
  @State private(set) var viewModel = ImageViewModel()

  let loadedImage: LoadedImage

  var body: some View {
    ZStack(alignment: .top) {
      ImageScrollView(
        loadedImage: loadedImage,
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
        viewModel.currentImage = loadedImage.image
        viewModel.fitToWindow()
      }
    }
  }
}

struct ImageScrollView: NSViewRepresentable {
  let loadedImage: LoadedImage
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
    scrollView.minMagnification = minScale
    scrollView.maxMagnification = maxScale
    scrollView.usesPredominantAxisScrolling = false
    scrollView.magnification = scale.clamped(to: minScale ... maxScale)
    context.coordinator.prepareForImage(
      loadedImage,
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

private final class ImageCanvasView: NSView {
  var loadedImage: LoadedImage {
    didSet {
      frame.size = loadedImage.displaySize
      needsDisplay = true
    }
  }

  var scale: CGFloat

  override var isFlipped: Bool {
    true
  }

  init(loadedImage: LoadedImage, scale: CGFloat) {
    self.loadedImage = loadedImage
    self.scale = scale
    super.init(frame: NSRect(origin: .zero, size: loadedImage.displaySize))
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    nil
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.clear.setFill()
    dirtyRect.fill()

    guard let currentContext = NSGraphicsContext.current else {
      drawNSImage(hints: nil)
      return
    }

    if let vectorContent = loadedImage.vectorContent {
      drawSVG(vectorContent, in: currentContext.cgContext)
      return
    }

    let previousInterpolation = currentContext.imageInterpolation
    let interpolation = imageInterpolation
    let hints: [NSImageRep.HintKey: Any] = [
      .interpolation: NSNumber(value: interpolation.rawValue),
    ]

    NSGraphicsContext.saveGraphicsState()
    currentContext.imageInterpolation = interpolation
    currentContext.cgContext.setShouldAntialias(false)
    currentContext.cgContext.interpolationQuality = cgInterpolationQuality
    drawNSImage(hints: hints)
    NSGraphicsContext.restoreGraphicsState()
    currentContext.imageInterpolation = previousInterpolation
  }

  private var imageInterpolation: NSImageInterpolation {
    switch loadedImage.kind {
    case .bitmap:
      scale > 1.0 ? .none : .high
    case .vector:
      .high
    }
  }

  private var cgInterpolationQuality: CGInterpolationQuality {
    switch loadedImage.kind {
    case .bitmap:
      scale > 1.0 ? .none : .high
    case .vector:
      .high
    }
  }

  private func drawSVG(_ vectorContent: SVGVectorContent, in context: CGContext) {
    NSGraphicsContext.saveGraphicsState()
    context.setShouldAntialias(false)
    context.clip(to: bounds)

    let viewBox = vectorContent.viewBox
    context.scaleBy(
      x: bounds.width / viewBox.width,
      y: bounds.height / viewBox.height,
    )
    context.translateBy(x: -viewBox.minX, y: -viewBox.minY)

    for path in vectorContent.paths {
      drawSVGPath(path)
    }

    NSGraphicsContext.restoreGraphicsState()
  }

  private func drawSVGPath(_ path: SVGBezierPath) {
    let fillColor = cgColor(from: path.svgAttributes["fill"]) ?? NSColor.black.cgColor
    if fillColor.alpha > 0 {
      NSColor(cgColor: fillColor)?.setFill()
      path.fill()
    }

    if let strokeColor = cgColor(from: path.svgAttributes["stroke"]),
       strokeColor.alpha > 0
    {
      NSColor(cgColor: strokeColor)?.setStroke()
      path.stroke()
    }
  }

  private func cgColor(from value: Any?) -> CGColor? {
    guard let value else { return nil }

    let object = value as AnyObject
    guard CFGetTypeID(object) == CGColor.typeID else { return nil }
    return (object as! CGColor)
  }

  private func drawNSImage(hints: [NSImageRep.HintKey: Any]?) {
    loadedImage.image.draw(
      in: bounds,
      from: NSRect(origin: .zero, size: loadedImage.image.size),
      operation: .copy,
      fraction: 1.0,
      respectFlipped: true,
      hints: hints,
    )
  }
}
