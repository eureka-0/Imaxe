//
//  Magnification.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/10.
//

import AppKit
import QuartzCore

extension ImageScrollViewCoordinator {
  struct MagnificationState {
    var isLiveMagnifying = false
    var pendingLiveMagnificationEnd = false
    var pendingUserAlwaysFitDisable = false
    var animatedZoomTarget: CGFloat?
    var zoomAnimationGeneration = 0
  }

  struct PreparedZoomAnimation {
    let startZoomScale: CGFloat
    let targetZoomScale: CGFloat
    let center: NSPoint
    let generation: Int
  }

  var isLiveMagnifying: Bool {
    magnificationState.isLiveMagnifying
  }

  var isProgrammaticZoomAnimating: Bool {
    magnificationState.animatedZoomTarget != nil
  }

  static var programmaticZoomAnimationDuration: TimeInterval {
    0.3
  }

  var currentZoomScale: CGFloat {
    magnificationState.animatedZoomTarget ?? scrollView?.magnification ?? 1.0
  }

  func beginUserMagnification() {
    magnificationState.isLiveMagnifying = true
    magnificationState.pendingLiveMagnificationEnd = false
    commandState.pendingFitToWindow = false
    clearFitToScreenRestoreState()
    cancelProgrammaticZoomAnimation()
    disableAlwaysFitToWindowForUserMagnification()
  }

  func endUserMagnification(_ scrollView: NSScrollView) {
    guard magnificationState.isLiveMagnifying,
          !magnificationState.pendingLiveMagnificationEnd
    else { return }

    magnificationState.pendingLiveMagnificationEnd = true
    DispatchQueue.main.async { [weak self, weak scrollView] in
      guard let self, let scrollView else { return }

      magnificationState.isLiveMagnifying = false
      magnificationState.pendingLiveMagnificationEnd = false
      clampScrollBounds(scrollView)
      onZoomScaleChange(scrollView.magnification)
      performPendingCommands(scrollView)
    }
  }

  func disableAlwaysFitToWindowForUserMagnification() {
    guard alwaysFitToWindow else { return }

    alwaysFitToWindow = false
    magnificationState.pendingUserAlwaysFitDisable = true
    onAlwaysFitToWindowChange(false)
  }

  func applyZoomScale(_ zoomScale: CGFloat, to scrollView: NSScrollView, animated: Bool) {
    guard let documentView = scrollView.documentView else { return }

    let targetZoomScale = zoomScale.clamped(to: Constants.imageZoomScaleRange)
    let center = imageCenter(in: documentView)

    if animated {
      guard let zoomAnimation = prepareZoomAnimation(targetZoomScale, to: scrollView)
      else { return }

      NSAnimationContext.runAnimationGroup { context in
        context.duration = Self.programmaticZoomAnimationDuration
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        scrollView.animator().setMagnification(
          zoomAnimation.targetZoomScale,
          centeredAt: zoomAnimation.center,
        )
      } completionHandler: { [weak self, weak scrollView] in
        Task { @MainActor [weak self, weak scrollView] in
          guard let self, let scrollView else { return }

          finishZoomScale(zoomAnimation, to: scrollView)
        }
      }
    } else {
      cancelProgrammaticZoomAnimation()
      scrollView.setMagnification(targetZoomScale, centeredAt: center)
      clampScrollBounds(scrollView)
      onZoomScaleChange(scrollView.magnification)
    }
  }

  func prepareZoomAnimation(
    _ zoomScale: CGFloat,
    to scrollView: NSScrollView,
  ) -> PreparedZoomAnimation? {
    guard let documentView = scrollView.documentView else { return nil }

    let targetZoomScale = zoomScale.clamped(to: Constants.imageZoomScaleRange)
    let startZoomScale = scrollView.magnification
    let zoomScaleDelta = abs(startZoomScale - targetZoomScale)
    let replacesAnimatedTarget = magnificationState.animatedZoomTarget.map {
      abs($0 - targetZoomScale) > Constants.zoomScaleUpdateTolerance
    } ?? false

    guard zoomScaleDelta > Constants.zoomScaleUpdateTolerance || replacesAnimatedTarget
    else { return nil }

    magnificationState.zoomAnimationGeneration += 1
    let animationGeneration = magnificationState.zoomAnimationGeneration
    magnificationState.animatedZoomTarget = targetZoomScale
    onZoomScaleChange(targetZoomScale)

    return PreparedZoomAnimation(
      startZoomScale: startZoomScale,
      targetZoomScale: targetZoomScale,
      center: imageCenter(in: documentView),
      generation: animationGeneration,
    )
  }

  func finishZoomScale(
    _ animation: PreparedZoomAnimation,
    to scrollView: NSScrollView,
  ) {
    guard magnificationState.zoomAnimationGeneration == animation.generation else { return }

    scrollView.setMagnification(
      animation.targetZoomScale,
      centeredAt: animation.center,
    )
    magnificationState.animatedZoomTarget = nil
    clampScrollBounds(scrollView)
    onZoomScaleChange(scrollView.magnification)
  }

  private func imageCenter(in documentView: NSView) -> NSPoint {
    NSPoint(x: documentView.bounds.midX, y: documentView.bounds.midY)
  }

  func clampScrollBounds(_ scrollView: NSScrollView) {
    let constrainedBounds = scrollView.contentView
      .constrainBoundsRect(scrollView.contentView.bounds)
    scrollView.contentView.scroll(to: constrainedBounds.origin)
    scrollView.reflectScrolledClipView(scrollView.contentView)
  }

  func cancelProgrammaticZoomAnimation() {
    cancelSynchronizedWindowZoomAnimation()
    magnificationState.zoomAnimationGeneration += 1
    magnificationState.animatedZoomTarget = nil
  }
}
