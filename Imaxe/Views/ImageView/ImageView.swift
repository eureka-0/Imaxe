// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import SwiftUI

struct ImageView: View {
  @Bindable var imageSession: ImageSession
  var onAlertAcknowledged: () -> Void = {}

  @Environment(\.openWindow) private var openWindow
  @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

  @State private var isTopBarHovering = false
  @State private var isPopoverPresented = false

  private let topBarHoverStripHeight: CGFloat = 50

  var body: some View {
    Group {
      if imageSession.currentDocument != nil || imageSession.isLoading {
        ZStack(alignment: .top) {
          imageContent

          TopBar(imageSession: imageSession, isPopoverPresented: $isPopoverPresented)
            .opacity(imageSession.showTopBar ? 1 : 0)
            .animation(
              accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2),
              value: imageSession.showTopBar,
            )
            .allowsHitTesting(imageSession.showTopBar)

          HoverTrackingStrip { isHovering, window in
            isTopBarHovering = isHovering
            updateTopBarVisibility(in: window)
          }
          .frame(maxWidth: .infinity)
          .frame(height: topBarHoverStripHeight)
        }
      } else {
        Color.clear
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .alert(imageSession.alertTitle, isPresented: $imageSession.isAlertPresented) {
      Button("OK", action: onAlertAcknowledged)
    } message: {
      Text(imageSession.alertMessage ?? "")
    }
    .onChange(of: isPopoverPresented) {
      updateTopBarVisibility()
    }
    .onChange(of: imageSession.isLoading) { _, newValue in
      if !newValue, imageSession.currentDocument == nil {
        imageSession.restoreStandardWindowButtons()
      } else {
        updateTopBarVisibility()
      }
    }
    .fileImporter(
      isPresented: $imageSession.isImporterPresented,
      allowedContentTypes: ImageLoader.supportedImageTypes,
      allowsMultipleSelection: true,
    ) { result in
      imageSession.onOpenImage(result: result, openWindow: openWindow)
    }
  }

  @ViewBuilder
  private var imageContent: some View {
    if let document = imageSession.currentDocument {
      ImageScrollView(
        document: document,
        shouldApplyLoadedImageWindowSize: imageSession.shouldApplyLoadedImageWindowSize,
        zoomScale: $imageSession.zoomScale,
        alwaysFitToWindow: $imageSession.alwaysFitToWindow,
      )
      .viewportController(imageSession.viewportController)
      .overlay {
        if imageSession.isLoading, imageSession.loadingElapsedTime > 0.1 {
          loadingImageView
        }
      }
    } else if imageSession.isLoading {
      loadingImageView
    } else {
      Color.clear
    }
  }

  private var loadingImageView: some View {
    VStack(spacing: 12) {
      ProgressView()
        .controlSize(.large)

      Text("Loading...")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
    }
    .padding(24)
    .frostedBackground(in: RoundedRectangle(cornerRadius: 12), style: .floating)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text("Loading..."))
  }

  private func updateTopBarVisibility(in window: NSWindow? = nil) {
    imageSession.setTopBarVisibility(to: isTopBarHovering || isPopoverPresented, in: window)
  }
}
