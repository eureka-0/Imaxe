//
//  ViewportCommands.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/10.
//

import AppKit

extension ImageScrollViewCoordinator: ImageViewportCommandHandling {
  struct CommandState {
    var pendingLoadedImageWindowSize = false
    var pendingFitToWindow = false
    var pendingFitWindowToImage = false
    var pendingFitToScreen = false
    var pendingRestoreFitToScreen = false

    var hasPendingCommands: Bool {
      pendingLoadedImageWindowSize
        || pendingFitToWindow
        || pendingFitWindowToImage
        || pendingFitToScreen
        || pendingRestoreFitToScreen
    }
  }

  var hasPendingCommands: Bool {
    commandState.hasPendingCommands
  }

  func handle(_ command: ImageViewportCommand) {
    guard let scrollView else { return }

    switch command {
    case .fitToWindow:
      clearFitToScreenRestoreState()
      alwaysFitToWindow = true
      magnificationState.pendingUserAlwaysFitDisable = false
      onAlwaysFitToWindowChange(true)
      queueFitToWindow()

    case .fitWindowToImage:
      clearFitToScreenRestoreState()
      queueFitWindowToImage()

    case .fitToScreen:
      alwaysFitToWindow = false
      magnificationState.pendingUserAlwaysFitDisable = false
      onAlwaysFitToWindowChange(false)
      if isFitToScreenToggleActive {
        queueRestoreFitToScreen()
      } else {
        queueFitToScreen()
      }

    case let .setZoomScale(to: newZoomScale):
      guard newZoomScale.isFinite, !magnificationState.isLiveMagnifying else { return }
      clearFitToScreenRestoreState()
      applyZoomScale(newZoomScale, to: scrollView, animated: true)

    case .zoomIn:
      guard !magnificationState.isLiveMagnifying else { return }
      clearFitToScreenRestoreState()
      applyZoomScale(
        currentZoomScale * Constants.imageZoomStepFactor,
        to: scrollView,
        animated: true,
      )

    case .zoomOut:
      guard !magnificationState.isLiveMagnifying else { return }
      clearFitToScreenRestoreState()
      applyZoomScale(
        currentZoomScale * (1.0 / Constants.imageZoomStepFactor),
        to: scrollView,
        animated: true,
      )

    case let .pan(horizontal, vertical):
      guard horizontal.isFinite, vertical.isFinite else { return }
      clearFitToScreenRestoreState()
      alwaysFitToWindow = false
      magnificationState.pendingUserAlwaysFitDisable = false
      onAlwaysFitToWindowChange(false)
      panViewport(scrollView, horizontal: horizontal, vertical: vertical)
    }

    if !magnificationState.isLiveMagnifying {
      performPendingCommands(scrollView)
    }
  }

  func performPendingCommands(_ scrollView: NSScrollView, shouldUpdateLayout: Bool = true) {
    guard commandState.hasPendingCommands else { return }

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

    if commandState.pendingFitToWindow, fitToWindow(scrollView, animated: true) {
      commandState.pendingFitToWindow = false
    }
  }

  func prepareCommandsForNewImage(shouldApplyLoadedImageWindowSize: Bool) {
    commandState.pendingLoadedImageWindowSize = shouldApplyLoadedImageWindowSize
    commandState.pendingFitToWindow = false
    commandState.pendingFitWindowToImage = false
    commandState.pendingFitToScreen = false
    commandState.pendingRestoreFitToScreen = false
  }

  private func queueFitToWindow() {
    commandState.pendingFitToWindow = true
  }

  private func queueFitWindowToImage() {
    commandState.pendingFitWindowToImage = true
  }

  private func queueFitToScreen() {
    commandState.pendingFitToScreen = true
    commandState.pendingRestoreFitToScreen = false
  }

  private func queueRestoreFitToScreen() {
    commandState.pendingRestoreFitToScreen = true
    commandState.pendingFitToScreen = false
  }
}
