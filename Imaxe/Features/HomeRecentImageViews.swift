//
//  HomeRecentImageViews.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/4.
//

import AppKit
import SwiftUI

struct HomeRecentImageListRow: View {
  let context: ImageCollectionItemContext<HomeRecentImageItem>
  let actions: HomeRecentImageActions

  private var item: HomeRecentImageItem {
    context.item
  }

  var body: some View {
    HStack(spacing: 6) {
      HomeRecentImageThumbnailView(
        item: item,
      )
      .frame(width: 28, height: 28)

      VStack(alignment: .leading, spacing: 3) {
        Text(item.displayName)
          .font(.callout)
          .lineLimit(1)
          .truncationMode(.middle)

        Text(item.location)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)

      Text(item.lastOpenedAt.relativeDateDescription)
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(idealWidth: 116, alignment: .leading)

      Text(item.fileSizeDescription)
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 68, alignment: .trailing)

      HomeRecentImageActionsMenu(item: item, actions: actions)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
  }
}

struct HomeRecentImageGridItem: View {
  let context: ImageCollectionItemContext<HomeRecentImageItem>

  private var item: HomeRecentImageItem {
    context.item
  }

  var body: some View {
    HomeRecentImageThumbnailView(
      item: item,
    )
    .overlay(alignment: .bottom) {
      if context.isHovered {
        Text(item.displayName)
          .font(.system(size: 9, weight: .light))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 2)
          .padding(.vertical, 2)
          .background(.regularMaterial)
      }
    }
    .help(item.location)
  }
}

struct HomeRecentImageActions {
  let onOpen: (HomeRecentImageItem) -> Void
  let onRemove: (HomeRecentImageItem) -> Void
  let onReveal: (HomeRecentImageItem) -> Void
  let onDeleteFile: (HomeRecentImageItem) -> Void
  let onRename: (HomeRecentImageItem) -> Void
}

struct RenameFileSheet: View {
  let item: HomeRecentImageItem
  @Binding var fileName: String
  let onCancel: () -> Void
  let onRename: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Rename")
        .font(.headline)

      TextField("Name", text: $fileName)
        .textFieldStyle(.roundedBorder)
        .frame(width: 320)

      HStack {
        Spacer()

        Button("Cancel") {
          onCancel()
        }
        .keyboardShortcut(.cancelAction)

        Button("Rename") {
          onRename(fileName)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 380)
  }
}

private struct HomeRecentImageThumbnailView: View {
  let item: HomeRecentImageItem

  private var thumbnailImage: NSImage? {
    guard let thumbnailCacheKey = item.thumbnailCacheKey else { return nil }

    return NSImage(contentsOf: ImageThumbnailCache.thumbnailURL(for: thumbnailCacheKey))
  }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 0)
        .fill(Color.clear)

      if let thumbnailImage {
        Image(nsImage: thumbnailImage)
          .resizable()
          .scaledToFit()
      } else {
        Image(systemName: "photo")
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct HomeRecentImageActionsMenu: View {
  let item: HomeRecentImageItem
  let actions: HomeRecentImageActions

  var body: some View {
    Menu {
      HomeRecentImageActionsContent(item: item, actions: actions)
    } label: {
      Label("More", systemImage: "ellipsis")
        .labelStyle(.iconOnly)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 24, height: 24)
    }
    .menuStyle(.button)
    .buttonStyle(.borderedOnHover)
    .help("More")
  }
}

struct HomeRecentImageActionsContent: View {
  let item: HomeRecentImageItem
  let actions: HomeRecentImageActions

  var body: some View {
    Button {
      actions.onOpen(item)
    } label: {
      Label("Open", systemImage: "photo")
    }

    Button {
      actions.onRename(item)
    } label: {
      Label("Rename", systemImage: "pencil")
    }
    .disabled(item.url == nil)

    Button(role: .destructive) {
      actions.onDeleteFile(item)
    } label: {
      Label("Move to Trash", systemImage: "trash")
    }
    .disabled(item.url == nil)

    Divider()

    Button {
      actions.onRemove(item)
    } label: {
      Label("Remove from Recents", systemImage: "minus.circle")
    }

    Button {
      actions.onReveal(item)
    } label: {
      Label("Show in Finder", systemImage: "folder")
    }
    .disabled(item.url == nil)
  }
}
