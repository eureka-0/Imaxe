//
//  ImageView.swift
//  Imagxe
//
//  Created by lxlong on 2026/6/17.
//

import AppKit
import SwiftUI

struct ImageView: View {
  @State private var viewModel = ImageViewModel()

  let image: NSImage

  var body: some View {
    ZStack(alignment: .top) {
      ImageScrollView(
        image: image,
        fitToWindowRequest: viewModel.fitToWindowRequest,
        scale: $viewModel.imageScale,
      )

      topBar
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // .background(.gray.opacity(0.2))
    .onAppear {
      DispatchQueue.main.async {
        viewModel.currentImage = image
        viewModel.fitToWindow()
      }
    }
  }

  var topBar: some View {
    HStack {
      Spacer()

      fitToWindowButton

      scaleText
        .padding(.vertical, 3)
        .background(.gray.opacity(0.3))
        .clipShape(.rect(cornerRadius: 8))

      fitWindowToImageButton

      pinWindowButton
    }
    .frame(height: 30)
    .padding(.horizontal, 10)
    .background(.thinMaterial)
    .labelStyle(.iconOnly)
    .buttonStyle(.plain)
  }

  var fitToWindowButton: some View {
    Button("Fit to Window", systemImage: "arrow.up.left.and.down.right.magnifyingglass") {
      viewModel.fitToWindow()
    }
    .keyboardShortcut("f", modifiers: .command)
    .disabled(viewModel.currentImage == nil)
    .help(Text("Fit the image to the window"))
  }

  var scaleText: some View {
    Text(Double(viewModel.imageScale), format: .percent.precision(.fractionLength(0)))
      .frame(width: 56)
      .disabled(viewModel.currentImage == nil)
  }

  var fitWindowToImageButton: some View {
    Button("Fit Window to Image", systemImage: "rectangle.and.arrow.up.right.and.arrow.down.left") {
      viewModel.fitWindowToImage()
    }
    .disabled(viewModel.currentImage == nil)
    .help(Text("Resize the window to fit the image"))
  }

  var pinWindowButton: some View {
    Button("Pin Window", systemImage: viewModel.isWindowPinned ? "pin.slash" : "pin") {
      viewModel.toggleWindowPinning()
    }
    .keyboardShortcut("p", modifiers: .command)
    .help(Text("Toggle window pinning"))
  }
}

struct ImageScrollView: NSViewRepresentable {
  let image: NSImage
  let fitToWindowRequest: Int
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
    let scrollView = ImageScrollView()
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
    context.coordinator.prepareForImage(image, fitToWindowRequest: fitToWindowRequest)
    scrollView.onLayout = { [weak coordinator = context.coordinator, weak scrollView] in
      guard let scrollView else {
        return
      }
      coordinator?.fitToWindowIfNeeded(scrollView, minScale: minScale, maxScale: maxScale)
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

    context.coordinator.prepareForImage(image, fitToWindowRequest: fitToWindowRequest)

    let clampedScale = scale.clamped(to: minScale ... maxScale)
    if !context.coordinator.needsFitToWindow, scrollView.magnification != clampedScale {
      scrollView.magnification = clampedScale
    }

    context.coordinator.fitToWindowIfNeeded(scrollView, minScale: minScale, maxScale: maxScale)
  }

  final class Coordinator {
    var onScaleChange: (CGFloat) -> Void
    private(set) var needsFitToWindow = false
    private var imageIdentifier: ObjectIdentifier?
    private var pendingFitToWindowRequest: Int?
    private var completedFitToWindowRequest = 0
    private var observedScrollView: NSScrollView?
    private var magnificationObservation: NSKeyValueObservation?

    init(onScaleChange: @escaping (CGFloat) -> Void) {
      self.onScaleChange = onScaleChange
    }

    func prepareForImage(_ image: NSImage, fitToWindowRequest: Int) {
      let newIdentifier = ObjectIdentifier(image)
      if imageIdentifier != newIdentifier {
        imageIdentifier = newIdentifier
        queueFitToWindow(fitToWindowRequest)
      } else if fitToWindowRequest != completedFitToWindowRequest {
        queueFitToWindow(fitToWindowRequest)
      }
    }

    func fitToWindowIfNeeded(_ scrollView: NSScrollView, minScale: CGFloat, maxScale: CGFloat) {
      guard needsFitToWindow, let request = pendingFitToWindowRequest,
            let documentView = scrollView.documentView
      else {
        return
      }

      scrollView.layoutSubtreeIfNeeded()
      let viewportSize = scrollView.contentSize
      let imageSize = documentView.frame.size

      guard viewportSize.width > 0,
            viewportSize.height > 0,
            imageSize.width > 0,
            imageSize.height > 0
      else {
        scrollView.needsLayout = true
        return
      }

      let fitScale = min(
        viewportSize.width / imageSize.width,
        viewportSize.height / imageSize.height,
      )
      .clamped(to: minScale ... maxScale)
      let center = NSPoint(x: imageSize.width / 2.0, y: imageSize.height / 2.0)
      scrollView.setMagnification(fitScale, centeredAt: center)
      needsFitToWindow = false
      pendingFitToWindowRequest = nil
      completedFitToWindowRequest = request
      onScaleChange(scrollView.magnification)
    }

    private func queueFitToWindow(_ request: Int) {
      pendingFitToWindowRequest = request
      needsFitToWindow = true
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

  final class ImageScrollView: NSScrollView {
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

      // Center horizontally
      if documentFrame.width <= proposedBounds.width {
        constrainedBounds.origin.x = floor((proposedBounds.width - documentFrame.width) / -2.0)
      }

      // Center vertically
      if documentFrame.height <= proposedBounds.height {
        constrainedBounds.origin.y = floor((proposedBounds.height - documentFrame.height) / -2.0)
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
