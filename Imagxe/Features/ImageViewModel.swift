//
//  ImageViewModel.swift
//  Imagxe
//
//  Created by lxlong on 2026/6/17.
//

import SwiftUI

@Observable
final class ImageViewModel {
  var currentImage: NSImage?
  var imageScale: CGFloat = 1.0
  private(set) var fitToWindowRequest = 0

  func fitToWindow() {
    fitToWindowRequest += 1
  }
}
