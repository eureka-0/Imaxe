//
//  ImageThumbnailView.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/6.
//

import SwiftUI

struct ImageThumbnailView: View {
  let url: URL
  let cacheKey: String?

  @State private var thumbnailImage: NSImage?

  private var backgroundColor: Color = .clear
  private var aspectRatio: CGFloat? = 1
  private var contentMode: ContentMode = .fill
  private var cornerRadius: CGFloat = 0

  init(url: URL, cacheKey: String? = nil) {
    self.url = url
    self.cacheKey = cacheKey
  }

  var body: some View {
    Group {
      if let aspectRatio {
        backgroundColor
          .aspectRatio(aspectRatio, contentMode: .fit)
          .overlay {
            thumbnailContent
          }
          .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      } else {
        ZStack {
          Rectangle()
            .fill(backgroundColor)

          thumbnailContent
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      }
    }
    .task(id: cacheKey ?? url.absoluteString) {
      thumbnailImage = nil
      let key = await ImageThumbnailCache.thumbnailKey(for: url, preferredKey: cacheKey)

      guard let key,
            !Task.isCancelled
      else { return }
      let thumbnailURL = ImageThumbnailCache.thumbnailURL(for: key)
      let image = await Task.detached(priority: .utility) {
        NSImage(contentsOf: thumbnailURL)
      }.value
      guard !Task.isCancelled else { return }
      thumbnailImage = image
    }
  }

  @ViewBuilder
  private var thumbnailContent: some View {
    if let thumbnailImage {
      Image(nsImage: thumbnailImage)
        .resizable()
        .aspectRatio(contentMode: contentMode)
    } else {
      Image(systemName: "photo.badge.exclamationmark")
        .resizable()
        .scaledToFit()
        .foregroundStyle(.secondary)
    }
  }
}

extension ImageThumbnailView {
  func backgroundColor(_ color: Color) -> Self {
    var view = self
    view.backgroundColor = color
    return view
  }

  func aspectRatio(contentMode: ContentMode) -> Self {
    var view = self
    view.contentMode = contentMode
    return view
  }

  func aspectRatio(_ ratio: CGFloat? = 1, contentMode: ContentMode = .fill) -> Self {
    var view = self
    view.aspectRatio = ratio
    view.contentMode = contentMode
    return view
  }

  func cornerRadius(_ radius: CGFloat) -> Self {
    var view = self
    view.cornerRadius = radius
    return view
  }
}
