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
    HStack(spacing: 12) {
      HomeRecentImageThumbnailView(
        item: item,
        isSelected: context.isSelected,
        isSelecting: context.isSelecting,
      )
      .frame(width: 58, height: 58)

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
      .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

      Text(relativeDateDescription(for: item.lastOpenedAt))
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(width: 116, alignment: .leading)

      Text(item.fileSizeDescription)
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 88, alignment: .trailing)

      HomeRecentImageActionsMenu(item: item, actions: actions)
        .frame(width: 28)
    }
    .padding(.horizontal, 12)
    .help(item.location)
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
      isSelected: context.isSelected,
      isSelecting: context.isSelecting,
    )
    .overlay(alignment: .bottom) {
      if context.isHovered {
        Text(item.displayName)
          .font(.caption)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 7)
          .padding(.vertical, 5)
          .background(.regularMaterial)
      }
    }
    .help(item.displayName)
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
  let isSelected: Bool
  let isSelecting: Bool

  private var thumbnailImage: NSImage? {
    guard let thumbnailCacheKey = item.thumbnailCacheKey else { return nil }

    return NSImage(contentsOf: ImageThumbnailCache.thumbnailURL(for: thumbnailCacheKey))
  }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.controlBackground)

      if let thumbnailImage {
        Image(nsImage: thumbnailImage)
          .resizable()
          .scaledToFill()
      } else {
        Image(systemName: "photo")
          .font(.system(size: 28))
          .foregroundStyle(.secondary)
      }

      if isSelecting, isSelected {
        VStack {
          HStack {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 18))
              .symbolRenderingMode(.palette)
              .foregroundStyle(.white, Color.accentColor)
              .padding(5)
          }
          Spacer()
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(
          isSelected ? Color.accentColor : Color.separator.opacity(0.5),
          lineWidth: isSelected ? 2 : 1,
        )
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
      Label("More", systemImage: "ellipsis.circle")
    }
    .menuStyle(.button)
    .labelStyle(.iconOnly)
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

private func relativeDateDescription(for date: Date?) -> String {
  guard let date else { return "--" }

  let formatter = RelativeDateTimeFormatter()
  formatter.unitsStyle = .full
  return formatter.localizedString(for: date, relativeTo: .now)
}
