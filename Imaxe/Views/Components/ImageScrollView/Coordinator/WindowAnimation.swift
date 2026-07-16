//
//  WindowAnimation.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/10.
//

import AppKit
import QuartzCore

extension ImageScrollViewCoordinator {
  struct WindowAnimationState {
    var isApplyingWindowFrame = false
    var windowFrameAnimationGeneration = 0
    var synchronizedWindowZoomAnimation: SynchronizedWindowZoomAnimation?
    var synchronizedWindowZoomDisplayLink: CADisplayLink?
    var synchronizedWindowZoomDisplayLinkTarget: DisplayLinkTarget?
  }

  struct SynchronizedWindowZoomAnimation {
    let window: NSWindow
    let scrollView: NSScrollView
    let startFrame: NSRect
    let targetFrame: NSRect
    let imageSize: NSSize
    let startViewportSize: NSSize
    let maintainsImageViewportFit: Bool
    let zoomAnimation: PreparedZoomAnimation
    let startTime: CFTimeInterval
    let duration: TimeInterval
    let windowAnimationGeneration: Int
  }

  final class DisplayLinkTarget: NSObject {
    weak var coordinator: ImageScrollViewCoordinator?

    init(coordinator: ImageScrollViewCoordinator) {
      self.coordinator = coordinator
    }

    @objc func displayLinkDidFire(_ displayLink: CADisplayLink) {
      coordinator?.advanceSynchronizedWindowZoomAnimation(displayLink)
    }
  }

  static var minimumWindowResizeAnimationDuration: TimeInterval {
    1.0 / 60.0
  }

  func applyWindowFrame(
    _ scrollView: NSScrollView,
    window: NSWindow,
    frame: NSRect,
    simultaneousZoomScale: CGFloat? = nil,
    targetImageFittedToViewport: Bool = false,
    caller: String = #function,
  ) {
    DispatchQueue.main.async { [weak self, weak scrollView, weak window] in
      guard let self, let scrollView, let window else { return }

      cancelSynchronizedWindowZoomAnimation()
      windowAnimationState.windowFrameAnimationGeneration += 1
      let animationGeneration = windowAnimationState.windowFrameAnimationGeneration
      let resizeDuration = max(0, window.animationResizeTime(frame))
      let reduceMotion = shouldReduceMotion()
      let animatesWindowResize = !reduceMotion
        && resizeDuration >= Self.minimumWindowResizeAnimationDuration
      let zoomAnimation: PreparedZoomAnimation? = if let simultaneousZoomScale {
        prepareZoomAnimation(simultaneousZoomScale, to: scrollView)
      } else {
        nil
      }
      let animationDuration: TimeInterval = if reduceMotion {
        0
      } else if animatesWindowResize {
        resizeDuration
      } else if zoomAnimation != nil {
        Self.programmaticZoomAnimationDuration
      } else {
        0
      }
      let synchronizesWindowAndZoom = animatesWindowResize && zoomAnimation != nil
      windowAnimationState.isApplyingWindowFrame = true

      #if DEBUG
        appLog(
          """
          Applying window frame from \(window.frame) to \(frame); window animation: \
          \(animatesWindowResize), synchronized window/zoom animation: \
          \(synchronizesWindowAndZoom), duration: \(animationDuration), zoom target: \
          \(String(describing: simultaneousZoomScale)) [Caller: \(caller)].
          """,
          level: .debug,
          category: .windowing,
        )
      #endif

      if let zoomAnimation, synchronizesWindowAndZoom {
        startSynchronizedWindowZoomAnimation(
          scrollView: scrollView,
          window: window,
          targetFrame: frame,
          duration: animationDuration,
          windowAnimationGeneration: animationGeneration,
          zoomAnimation: zoomAnimation,
          targetImageFittedToViewport: targetImageFittedToViewport,
        )
        return
      }

      if !animatesWindowResize {
        window.setFrame(frame, display: false)
      }

      guard animationDuration > 0 else {
        finishWindowFrameApplication(
          scrollView,
          animationGeneration: animationGeneration,
          zoomAnimation: zoomAnimation,
        )
        return
      }

      NSAnimationContext.runAnimationGroup { context in
        context.duration = animationDuration
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        if animatesWindowResize {
          window.animator().setFrame(frame, display: false)
        }
        if let zoomAnimation {
          scrollView.animator().setMagnification(
            zoomAnimation.targetZoomScale,
            centeredAt: zoomAnimation.center,
          )
        }
      } completionHandler: { [weak self, weak scrollView] in
        Task { @MainActor [weak self, weak scrollView] in
          guard let self else { return }

          finishWindowFrameApplication(
            scrollView,
            animationGeneration: animationGeneration,
            zoomAnimation: zoomAnimation,
          )
        }
      }
    }
  }

  /// `NSScrollView` magnification is relative to its clip view's current geometry. Animating the
  /// magnification proxy while the window is also resizing lets the changing viewport compound
  /// with the proxy's interpolation. Drive both values from one display link instead, and apply
  /// magnification only after the viewport has laid out for that frame.
  private func startSynchronizedWindowZoomAnimation(
    scrollView: NSScrollView,
    window: NSWindow,
    targetFrame: NSRect,
    duration: TimeInterval,
    windowAnimationGeneration: Int,
    zoomAnimation: PreparedZoomAnimation,
    targetImageFittedToViewport: Bool,
  ) {
    let startFrame = window.frame
    let startViewportSize = scrollView.contentSize
    let frameViewportDelta = NSSize(
      width: startFrame.width - startViewportSize.width,
      height: startFrame.height - startViewportSize.height,
    )
    let imageSize = scrollView.documentView?.bounds.size ?? .zero
    let targetViewportSize = NSSize(
      width: targetFrame.width - frameViewportDelta.width,
      height: targetFrame.height - frameViewportDelta.height,
    )
    let pointTolerance = 1 / window.backingScaleFactor
    let startImageDisplaySize = NSSize(
      width: imageSize.width * zoomAnimation.startZoomScale,
      height: imageSize.height * zoomAnimation.startZoomScale,
    )
    let targetImageDisplaySize = NSSize(
      width: imageSize.width * zoomAnimation.targetZoomScale,
      height: imageSize.height * zoomAnimation.targetZoomScale,
    )
    windowAnimationState.synchronizedWindowZoomAnimation = SynchronizedWindowZoomAnimation(
      window: window,
      scrollView: scrollView,
      startFrame: startFrame,
      targetFrame: targetFrame,
      imageSize: imageSize,
      startViewportSize: startViewportSize,
      maintainsImageViewportFit: targetImageFittedToViewport
        && sizesMatch(
          startImageDisplaySize,
          startViewportSize,
          tolerance: pointTolerance,
        )
        && sizesMatch(
          targetImageDisplaySize,
          targetViewportSize,
          tolerance: max(1, pointTolerance),
        ),
      zoomAnimation: zoomAnimation,
      startTime: CACurrentMediaTime(),
      duration: duration,
      windowAnimationGeneration: windowAnimationGeneration,
    )

    guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else {
      window.setFrame(targetFrame, display: false)
      window.contentView?.layoutSubtreeIfNeeded()
      scrollView.layoutSubtreeIfNeeded()
      scrollView.setMagnification(
        zoomAnimation.targetZoomScale,
        centeredAt: zoomAnimation.center,
      )
      stopSynchronizedWindowZoomAnimation()
      finishWindowFrameApplication(
        scrollView,
        animationGeneration: windowAnimationGeneration,
        zoomAnimation: zoomAnimation,
      )
      return
    }

    let displayLinkTarget = DisplayLinkTarget(coordinator: self)
    windowAnimationState.synchronizedWindowZoomDisplayLinkTarget = displayLinkTarget
    let displayLink = screen.displayLink(
      target: displayLinkTarget,
      selector: #selector(DisplayLinkTarget.displayLinkDidFire(_:)),
    )
    windowAnimationState.synchronizedWindowZoomDisplayLink = displayLink
    displayLink.add(to: .main, forMode: .common)
  }

  private func advanceSynchronizedWindowZoomAnimation(_ displayLink: CADisplayLink) {
    guard windowAnimationState.synchronizedWindowZoomDisplayLink === displayLink,
          let animation = windowAnimationState.synchronizedWindowZoomAnimation
    else { return }

    guard windowAnimationState.windowFrameAnimationGeneration
      == animation.windowAnimationGeneration,
      magnificationState.zoomAnimationGeneration == animation.zoomAnimation.generation
    else {
      cancelSynchronizedWindowZoomAnimation()
      return
    }

    let displayTimestamp = displayLink.targetTimestamp > 0
      ? displayLink.targetTimestamp
      : CACurrentMediaTime()
    let linearProgress = CGFloat(
      (displayTimestamp - animation.startTime) / animation.duration,
    )
    .clamped(to: 0 ... 1)
    let progress = easeInEaseOut(linearProgress)
    let intendedZoomScale = interpolatedValue(
      from: animation.zoomAnimation.startZoomScale,
      to: animation.zoomAnimation.targetZoomScale,
      progress: progress,
    )
    let currentFrame = synchronizedWindowFrame(
      animation,
      intendedZoomScale: intendedZoomScale,
      progress: progress,
      isFinalFrame: linearProgress >= 1,
    )

    animation.window.setFrame(currentFrame, display: false)
    animation.window.contentView?.layoutSubtreeIfNeeded()
    animation.scrollView.layoutSubtreeIfNeeded()
    let currentZoomScale = if animation.maintainsImageViewportFit {
      zoomScaleMatchingViewport(
        animation.scrollView.contentSize,
        imageSize: animation.imageSize,
        fallback: intendedZoomScale,
      )
    } else {
      intendedZoomScale
    }
    animation.scrollView.setMagnification(
      currentZoomScale,
      centeredAt: animation.zoomAnimation.center,
    )

    guard linearProgress >= 1 else { return }

    stopSynchronizedWindowZoomAnimation()
    finishWindowFrameApplication(
      animation.scrollView,
      animationGeneration: animation.windowAnimationGeneration,
      zoomAnimation: animation.zoomAnimation,
    )
  }

  private func synchronizedWindowFrame(
    _ animation: SynchronizedWindowZoomAnimation,
    intendedZoomScale: CGFloat,
    progress: CGFloat,
    isFinalFrame: Bool,
  ) -> NSRect {
    guard animation.maintainsImageViewportFit, !isFinalFrame else {
      return interpolatedRect(
        from: animation.startFrame,
        to: animation.targetFrame,
        progress: progress,
      )
    }

    let frameViewportDelta = NSSize(
      width: animation.startFrame.width - animation.startViewportSize.width,
      height: animation.startFrame.height - animation.startViewportSize.height,
    )
    return NSRect(
      x: interpolatedValue(
        from: animation.startFrame.origin.x,
        to: animation.targetFrame.origin.x,
        progress: progress,
      ),
      y: interpolatedValue(
        from: animation.startFrame.origin.y,
        to: animation.targetFrame.origin.y,
        progress: progress,
      ),
      width: animation.imageSize.width * intendedZoomScale + frameViewportDelta.width,
      height: animation.imageSize.height * intendedZoomScale + frameViewportDelta.height,
    )
  }

  private func interpolatedRect(
    from start: NSRect,
    to end: NSRect,
    progress: CGFloat,
  ) -> NSRect {
    NSRect(
      x: interpolatedValue(from: start.origin.x, to: end.origin.x, progress: progress),
      y: interpolatedValue(from: start.origin.y, to: end.origin.y, progress: progress),
      width: interpolatedValue(from: start.width, to: end.width, progress: progress),
      height: interpolatedValue(from: start.height, to: end.height, progress: progress),
    )
  }

  private func interpolatedValue(
    from start: CGFloat,
    to end: CGFloat,
    progress: CGFloat,
  ) -> CGFloat {
    start + (end - start) * progress
  }

  private func zoomScaleMatchingViewport(
    _ viewportSize: NSSize,
    imageSize: NSSize,
    fallback: CGFloat,
  ) -> CGFloat {
    guard viewportSize.width > 0,
          viewportSize.height > 0,
          imageSize.width > 0,
          imageSize.height > 0
    else { return fallback }

    return ((viewportSize.width + viewportSize.height)
      / (imageSize.width + imageSize.height))
      .clamped(to: Constants.imageZoomScaleRange)
  }

  private func easeInEaseOut(_ progress: CGFloat) -> CGFloat {
    let clampedProgress = progress.clamped(to: 0 ... 1)
    return clampedProgress * clampedProgress * (3 - 2 * clampedProgress)
  }

  private func stopSynchronizedWindowZoomAnimation() {
    windowAnimationState.synchronizedWindowZoomDisplayLink?.invalidate()
    windowAnimationState.synchronizedWindowZoomDisplayLink = nil
    windowAnimationState.synchronizedWindowZoomDisplayLinkTarget = nil
    windowAnimationState.synchronizedWindowZoomAnimation = nil
  }

  func cancelSynchronizedWindowZoomAnimation() {
    guard windowAnimationState.synchronizedWindowZoomDisplayLink != nil
      || windowAnimationState.synchronizedWindowZoomAnimation != nil
    else { return }

    stopSynchronizedWindowZoomAnimation()
    windowAnimationState.windowFrameAnimationGeneration += 1
    magnificationState.zoomAnimationGeneration += 1
    magnificationState.animatedZoomTarget = nil
    windowAnimationState.isApplyingWindowFrame = false
  }

  private func finishWindowFrameApplication(
    _ scrollView: NSScrollView?,
    animationGeneration: Int,
    zoomAnimation: PreparedZoomAnimation?,
  ) {
    guard windowAnimationState.windowFrameAnimationGeneration == animationGeneration
    else { return }

    windowAnimationState.isApplyingWindowFrame = false
    guard let scrollView else { return }

    scrollView.layoutSubtreeIfNeeded()
    windowSizingState.suppressedAlwaysFitViewportSize = scrollView.contentSize

    if let zoomAnimation {
      finishZoomScale(zoomAnimation, to: scrollView)
    } else {
      clampScrollBounds(scrollView)
      onZoomScaleChange(scrollView.magnification)
    }
  }
}
