//
//  ImageThumbnailView.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/6.
//

import SwiftUI

struct ImageThumbnailView: View {
  let url: URL

  private var backgroundColor: Color = .clear
  private var cornerRadius: CGFloat = 0

  private var thumbnailImage: NSImage? {
    guard let thumbnailCacheKey = ImageThumbnailCache.ensureThumbnail(for: url) else { return nil }

    return NSImage(contentsOf: ImageThumbnailCache.thumbnailURL(for: thumbnailCacheKey))
  }

  init(url: URL) {
    self.url = url
  }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: cornerRadius)
        .fill(backgroundColor)

      if let thumbnailImage {
        Image(nsImage: thumbnailImage)
          .resizable()
          .scaledToFit()
      } else {
        Image(systemName: "photo.badge.exclamationmark")
          .resizable()
          .scaledToFit()
          .foregroundStyle(.secondary)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
  }
}

extension ImageThumbnailView {
  func backgroundColor(_ color: Color) -> Self {
    var view = self
    view.backgroundColor = color
    return view
  }

  func cornerRadius(_ radius: CGFloat) -> Self {
    var view = self
    view.cornerRadius = radius
    return view
  }
}
