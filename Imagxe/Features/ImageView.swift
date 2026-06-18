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
      )

      topBar
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      DispatchQueue.main.async {
        viewModel.currentImage = image
        viewModel.fitToWindow()
      }
    }
  }
}

struct ImageScrollView: NSViewRepresentable {
  let image: NSImage
  let fitToWindowRequest: Int
  let fitWindowToImageRequest: Int
  @Binding var scale: CGFloat

  private let minScale: CGFloat = 0.05
  private let maxScale: CGFloat = 16.0

  func onScaleChange(_ scale: CGFloat) {
    self.scale = scale
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onScaleChange: onScaleChange)
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
    scrollView.onLayout = { [weak coordinator = context.coordinator, weak scrollView] in
      guard let scrollView else { return }
      coordinator?.performPendingRequests(scrollView, minScale: minScale, maxScale: maxScale)
    }
    context.coordinator.observe(scrollView)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.onScaleChange = onScaleChange
    context.coordinator.observe(scrollView)

    if let imageView = scrollView.documentView as? PixelImageView {
      imageView.image = image
      imageView.scale = scale
      scrollView.reflectScrolledClipView(scrollView.contentView)
    } else {
      scrollView.documentView = PixelImageView(image: image, scale: scale)
    }
    scrollView.layoutSubtreeIfNeeded()

    context.coordinator.prepareForImage(
      image,
      fitToWindowRequest: fitToWindowRequest,
      fitWindowToImageRequest: fitWindowToImageRequest,
    )

    let clampedScale = scale.clamped(to: minScale ... maxScale)
    if !context.coordinator.hasPendingRequests, scrollView.magnification != clampedScale {
      scrollView.magnification = clampedScale
    }

    context.coordinator.performPendingRequests(scrollView, minScale: minScale, maxScale: maxScale)
  }

  final class Coordinator {
    var onScaleChange: (CGFloat) -> Void
    var hasPendingRequests: Bool {
      pendingFitToWindowRequest != nil || pendingFitWindowToImageRequest != nil
    }

    private var imageIdentifier: ObjectIdentifier?
    private var pendingFitToWindowRequest: Int?
    private var pendingFitWindowToImageRequest: Int?
    private var completedFitToWindowRequest = 0
    private var completedFitWindowToImageRequest = 0
    private var observedScrollView: NSScrollView?
    private var magnificationObservation: NSKeyValueObservation?

    init(onScaleChange: @escaping (CGFloat) -> Void) {
      self.onScaleChange = onScaleChange
    }

    func prepareForImage(
      _ image: NSImage, fitToWindowRequest: Int, fitWindowToImageRequest: Int,
    ) {
      let newIdentifier = ObjectIdentifier(image)
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

    func performPendingRequests(_ scrollView: NSScrollView, minScale: CGFloat, maxScale: CGFloat) {
      guard hasPendingRequests else { return }

      scrollView.layoutSubtreeIfNeeded()

      if fitWindowToImageIfNeeded(scrollView, minScale: minScale, maxScale: maxScale) { return }

      fitToWindowIfNeeded(scrollView, minScale: minScale, maxScale: maxScale)
    }

    private func fitToWindowIfNeeded(
      _ scrollView: NSScrollView, minScale: CGFloat, maxScale: CGFloat,
    ) {
      guard let request = pendingFitToWindowRequest,
            let documentView = scrollView.documentView
      else { return }

      let viewportSize = scrollView.contentSize
      let imageSize = documentView.bounds.size

      guard viewportSize.width > 0,
            viewportSize.height > 0,
            imageSize.width > 0,
            imageSize.height > 0
      else { return }

      let fitScale = min(
        viewportSize.width / imageSize.width,
        viewportSize.height / imageSize.height,
      )
      .clamped(to: minScale ... maxScale)
      let center = NSPoint(x: imageSize.width / 2.0, y: imageSize.height / 2.0)
      scrollView.setMagnification(fitScale, centeredAt: center)
      pendingFitToWindowRequest = nil
      completedFitToWindowRequest = request
      clampScrollBounds(scrollView)
      onScaleChange(scrollView.magnification)
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
      applyFitWindowToImage(scrollView, window: window, frame: constrainedFrame)
      return true
    }

    private func applyFitWindowToImage(
      _ scrollView: NSScrollView, window: NSWindow, frame: NSRect,
    ) {
      DispatchQueue.main.async { [weak self, weak scrollView, weak window] in
        guard let self, let scrollView, let window else { return }

        window.setFrame(frame, display: false, animate: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self, weak scrollView] in
          guard let self, let scrollView else { return }

          scrollView.layoutSubtreeIfNeeded()
          clampScrollBounds(scrollView)
          onScaleChange(scrollView.magnification)
        }
      }
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

  final class ImageNSScrollView: NSScrollView {
    var onLayout: (() -> Void)?

    override func layout() {
      super.layout()
      onLayout?()
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

final class PixelImageView: NSView {
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

extension NSImage {
  var pixelSize: NSSize {
    var representationSize = NSSize.zero

    for representation in representations {
      representationSize.width = max(representationSize.width, CGFloat(representation.pixelsWide))
      representationSize.height = max(representationSize.height, CGFloat(representation.pixelsHigh))
    }

    if representationSize.width > 0, representationSize.height > 0 {
      return representationSize
    }

    return size
  }
}

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}

private extension CGFloat {
  func roundedDownToPixel(scale: CGFloat) -> CGFloat {
    guard scale > 0 else { return self }
    return floor(self * scale) / scale
  }
}

private extension NSRect {
  func constrained(to visibleFrame: NSRect) -> NSRect {
    var rect = self
    rect.size.width = min(rect.width, visibleFrame.width)
    rect.size.height = min(rect.height, visibleFrame.height)

    if rect.maxX > visibleFrame.maxX {
      rect.origin.x = visibleFrame.maxX - rect.width
    }
    if rect.minX < visibleFrame.minX {
      rect.origin.x = visibleFrame.minX
    }
    if rect.maxY > visibleFrame.maxY {
      rect.origin.y = visibleFrame.maxY - rect.height
    }
    if rect.minY < visibleFrame.minY {
      rect.origin.y = visibleFrame.minY
    }

    return rect
  }
}
