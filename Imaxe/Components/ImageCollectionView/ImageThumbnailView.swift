//
//  ImageThumbnailView.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/6.
//

import SwiftUI

struct ImageThumbnailView: View {
  let url: URL
  @State private var thumbnailImage: NSImage?

  private var backgroundColor: Color = .clear
  private var aspectRatio: CGFloat? = 1
  private var contentMode: ContentMode = .fill
  private var cornerRadius: CGFloat = 0

  init(url: URL) {
    self.url = url
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
    .task(id: url) {
      thumbnailImage = nil
      guard let key = await ImageThumbnailCache.ensureThumbnail(for: url),
            !Task.isCancelled
      else { return }
      thumbnailImage = NSImage(contentsOf: ImageThumbnailCache.thumbnailURL(for: key))
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
