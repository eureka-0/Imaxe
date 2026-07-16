//
//  Coordinator.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/10.
//

import AppKit

/// A coordinator class that manages the state and behavior of the `ImageScrollView`.
final class ImageScrollViewCoordinator: NSObject {
  var onZoomScaleChange: (CGFloat) -> Void
  var onAlwaysFitToWindowChange: (Bool) -> Void

  weak var scrollView: NSScrollView?
  var alwaysFitToWindow = false
  var commandState = CommandState()
  var magnificationState = MagnificationState()
  var windowSizingState = WindowSizingState()
  var windowAnimationState = WindowAnimationState()
  var shouldReduceMotion: () -> Bool = {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  private var imageIdentifier: UUID?
  private weak var viewportController: ImageViewportController?
  private weak var observedWindow: NSWindow?
  private var magnificationObservation: NSKeyValueObservation?
  private var willStartLiveMagnifyObserver: NSObjectProtocol?
  private var didEndLiveMagnifyObserver: NSObjectProtocol?
  private var didEndLiveResizeObserver: NSObjectProtocol?
  private var didMoveWindowObserver: NSObjectProtocol?

  init(
    onZoomScaleChange: @escaping (CGFloat) -> Void,
    onAlwaysFitToWindowChange: @escaping (Bool) -> Void,
  ) {
    self.onZoomScaleChange = onZoomScaleChange
    self.onAlwaysFitToWindowChange = onAlwaysFitToWindowChange
  }

  deinit {
    MainActor.assumeIsolated {
      windowAnimationState.synchronizedWindowZoomDisplayLink?.invalidate()
      unbindViewportController()
      removeObservers()
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

  func updateAlwaysFitToWindowFromBinding(_ newAlwaysFitToWindow: Bool) {
    if magnificationState.pendingUserAlwaysFitDisable {
      if !newAlwaysFitToWindow {
        magnificationState.pendingUserAlwaysFitDisable = false
      } else {
        return
      }
    }

    if magnificationState.isLiveMagnifying, newAlwaysFitToWindow {
      return
    }

    alwaysFitToWindow = newAlwaysFitToWindow
  }

  func prepareForImage(
    _ document: ImageDocument,
    shouldApplyLoadedImageWindowSize: Bool,
  ) {
    let newIdentifier = document.id
    if imageIdentifier != newIdentifier {
      imageIdentifier = newIdentifier
      prepareCommandsForNewImage(
        shouldApplyLoadedImageWindowSize: shouldApplyLoadedImageWindowSize,
      )
      clearFitToScreenRestoreState()
      cancelProgrammaticZoomAnimation()
    }
  }

  func scrollViewDidLayout(_ scrollView: NSScrollView) {
    observeWindowIfNeeded(scrollView.window)
    guard !magnificationState.isLiveMagnifying else { return }

    performPendingCommands(scrollView, shouldUpdateLayout: false)

    guard alwaysFitToWindow, !commandState.hasPendingCommands else { return }
    guard shouldApplyAlwaysFitToWindow(scrollView) else { return }

    fitToWindow(scrollView, animated: false)
  }

  func observe(_ scrollView: NSScrollView) {
    guard self.scrollView !== scrollView else { return }

    removeObservers()
    self.scrollView = scrollView
    observeWindowIfNeeded(scrollView.window)
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

  private func observeWindowIfNeeded(_ window: NSWindow?) {
    guard observedWindow !== window else { return }

    removeWindowObservers()
    observedWindow = window
    guard let window else { return }

    didEndLiveResizeObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didEndLiveResizeNotification,
      object: window,
      queue: .main,
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, !windowAnimationState.isApplyingWindowFrame else { return }

        clearFitToScreenRestoreState()
      }
    }

    didMoveWindowObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didMoveNotification,
      object: window,
      queue: .main,
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, !windowAnimationState.isApplyingWindowFrame else { return }

        if NSEvent.leftMousePressed {
          clearFitToScreenRestoreState()
        }
      }
    }
  }

  private func removeObservers() {
    if let willStartLiveMagnifyObserver {
      NotificationCenter.default.removeObserver(willStartLiveMagnifyObserver)
      self.willStartLiveMagnifyObserver = nil
    }

    if let didEndLiveMagnifyObserver {
      NotificationCenter.default.removeObserver(didEndLiveMagnifyObserver)
      self.didEndLiveMagnifyObserver = nil
    }

    removeWindowObservers()
  }

  private func removeWindowObservers() {
    if let didEndLiveResizeObserver {
      NotificationCenter.default.removeObserver(didEndLiveResizeObserver)
      self.didEndLiveResizeObserver = nil
    }
    if let didMoveWindowObserver {
      NotificationCenter.default.removeObserver(didMoveWindowObserver)
      self.didMoveWindowObserver = nil
    }
    observedWindow = nil
  }
}
