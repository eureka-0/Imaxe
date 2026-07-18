//
//  Constants.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/18.
//

import Foundation

nonisolated enum Constants {
  /// The minimum window content width to use when creating a new window.
  static let minimumWindowContentWidth: CGFloat = 520

  /// The minimum window content height to use when creating a new window. Note that this is the
  /// minimum height for the content area of the window, not the entire window. The actual minimum
  /// window height will be larger due to the title bar and other window chrome.
  static let minimumWindowContentHeight: CGFloat = 360

  /// The default window width to use when creating a new window.
  static let defaultWindowWidth: CGFloat = 680

  /// The default window height to use when creating a new window.
  static let defaultWindowHeight: CGFloat = 640

  /// The range of valid zoom scales for the image view.
  static let imageZoomScaleRange: ClosedRange<CGFloat> = 0.05 ... 20.0

  /// The tolerance for updating the zoom scale. If the new zoom scale is within this tolerance of
  /// the current zoom scale, the zoom scale will not be updated.
  static let zoomScaleUpdateTolerance: CGFloat = 0.0001

  /// The factor by which to zoom in or out when the user performs a zoom command (e.g., zoom in/out
  /// button, keyboard shortcut, etc.).
  static let imageZoomStepFactor: CGFloat = 1.25

  /// The distance to pan the image when the user presses a keyboard panning key.
  static let keyboardPanDistance: CGFloat = 80

  // TODO: Consider downsampling large images instead of rejecting them outright.
  /// The maximum dimension (width or height) of an image that can be opened in the app. This value
  /// is based on the maximum texture size supported by Metal on macOS. Images larger than this
  /// dimension will be rejected to prevent rendering issues.
  static let maximumImageDimension: CGFloat = 16384

  /// The maximum pixel count of an image that can be opened in the app. This is calculated as the
  /// square of the maximum image dimension.
  static let maximumImagePixelCount: CGFloat = maximumImageDimension * maximumImageDimension

  /// Fallback screen PPI (pixels per inch) to use when the actual screen PPI cannot be determined.
  static let fallbackScreenPPI: (CGFloat, CGFloat) = (254, 254)

  /// The maximum number of recent images to display in the menu. If there are more recent images
  /// than this limit, the oldest ones will be removed from the list.
  static let maximumRecentImagesToDisplayInMenu = 20
}
