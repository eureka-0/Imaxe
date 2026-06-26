//
//  Constants.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/18.
//

import Foundation

enum Constants {
  static let topBarHeight: CGFloat = 32
  static let topBarHoverStripHeight: CGFloat = 50
  static let topBarItemSpacing: CGFloat = 6
  static let topBarControlGroupSpacing: CGFloat = 1
  static let topBarControlGroupPadding: CGFloat = 1
  static let topBarIconButtonWidth: CGFloat = 24
  static let topBarScaleButtonWidth: CGFloat = 48
  static let topBarButtonHeight: CGFloat = 22
  static let topBarPositionMinWidth: CGFloat = 48
  static let topBarPositionMaxWidth: CGFloat = 80
  static let topBarWindowButtonReservedWidth: CGFloat = 72

  static let minimumWindowContentWidth: CGFloat = 520
  static let minimumWindowContentHeight: CGFloat = 360
  static let defaultWindowWidth: CGFloat = 680
  static let defaultWindowHeight: CGFloat = 520

  static let imageScaleRange: ClosedRange<CGFloat> = 0.05 ... 20.0
  static let scaleUpdateTolerance: CGFloat = 0.0001
  static let commonScales: [CGFloat] = [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0]
  static let imageZoomStep: CGFloat = 1.25

  static let fallbackScreenPPI: (CGFloat, CGFloat) = (254, 254)
}
