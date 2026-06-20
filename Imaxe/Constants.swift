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
  static let topBarHideDelay: TimeInterval = 3
  static let topBarItemSpacing: CGFloat = 6
  static let topBarControlGroupSpacing: CGFloat = 1
  static let topBarControlGroupPadding: CGFloat = 1
  static let topBarIconButtonWidth: CGFloat = 24
  static let topBarScaleButtonWidth: CGFloat = 58
  static let topBarButtonHeight: CGFloat = 22
  static let topBarPositionWidth: CGFloat = 52
  static let topBarWindowButtonReservedWidth: CGFloat = 72

  static let minimumWindowContentWidth: CGFloat = 620
  static let minimumWindowContentHeight: CGFloat = 420

  static let imageScaleRange: ClosedRange<CGFloat> = 0.05 ... 16.0
  static let imageZoomStep: CGFloat = 1.25
}
