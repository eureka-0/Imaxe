// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import AppKit
import SwiftData
import SwiftUI

// MARK: - FileLocationPicker

struct FileLocationPicker: View {
  let directoryURL: URL?
  let onSelectDirectory: (URL) -> Void

  @Query(sort: \RecentImage.lastOpenedAt, order: .reverse) private var recentImages: [RecentImage]

  @State private var isMenuOpen: Bool = false

  private var cornerRadius: CGFloat = 6

  private var recentDirectoryURLs: [URL] {
    recentImages.map { $0.url.deletingLastPathComponent() }
  }

  init(
    directoryURL: URL? = nil,
    onSelectDirectory: @escaping (URL) -> Void,
  ) {
    self.directoryURL = directoryURL
    self.onSelectDirectory = onSelectDirectory
  }

  var body: some View {
    NSPathControlRepresentable(
      directoryURL: directoryURL,
      recentDirectoryURLs: recentDirectoryURLs,
      onSelectDirectory: onSelectDirectory,
      isMenuOpen: $isMenuOpen,
    )
    .padding(.horizontal, 4)
    .padding(.vertical, 2)
    .background(isMenuOpen ? .controlBackground.opacity(0.7) : .controlBackground)
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    .overlay {
      RoundedRectangle(cornerRadius: cornerRadius)
        .stroke(.separator.opacity(0.45), lineWidth: 0.5)
    }
  }
}

extension FileLocationPicker {
  func cornerRadius(_ radius: CGFloat) -> Self {
    var view = self
    view.cornerRadius = radius
    return view
  }
}

// MARK: - NSPathControlRepresentable

private struct NSPathControlRepresentable: NSViewRepresentable {
  let directoryURL: URL?
  let recentDirectoryURLs: [URL]
  let onSelectDirectory: (URL) -> Void
  @Binding var isMenuOpen: Bool

  func makeCoordinator() -> Coordinator {
    Coordinator(
      recentDirectoryURLs: recentDirectoryURLs,
      onSelectDirectory: onSelectDirectory,
      isMenuOpen: $isMenuOpen,
    )
  }

  func makeNSView(context: Context) -> NSPathControl {
    let pathControl = NSPathControl()
    pathControl.pathStyle = .popUp
    pathControl.focusRingType = .none
    pathControl.isEditable = true
    pathControl.url = directoryURL
    pathControl.delegate = context.coordinator
    pathControl.target = context.coordinator
    pathControl.action = #selector(Coordinator.selectDirectory(_:))
    return pathControl
  }

  func updateNSView(_ pathControl: NSPathControl, context: Context) {
    context.coordinator.recentDirectoryURLs = recentDirectoryURLs
    context.coordinator.onSelectDirectory = onSelectDirectory
    if pathControl.url != directoryURL {
      pathControl.url = directoryURL
    }

    if isMenuOpen {
      pathControl.alphaValue = 0.7
    } else {
      pathControl.alphaValue = 1.0
    }
  }
}

// MARK: - Coordinator

private extension NSPathControlRepresentable {
  struct LocationSection {
    let title: LocalizedStringResource
    let urls: [URL]
  }

  final class Coordinator: NSObject, NSPathControlDelegate, NSMenuDelegate {
    var recentDirectoryURLs: [URL]
    var onSelectDirectory: (URL) -> Void
    var isMenuOpen: Binding<Bool>

    private let customMenuIdentifierPrefix = "FileLocationPicker.Custom"

    init(
      recentDirectoryURLs: [URL],
      onSelectDirectory: @escaping (URL) -> Void,
      isMenuOpen: Binding<Bool>,
    ) {
      self.recentDirectoryURLs = recentDirectoryURLs
      self.onSelectDirectory = onSelectDirectory
      self.isMenuOpen = isMenuOpen
    }

    @objc func selectDirectory(_ pathControl: NSPathControl) {
      guard let url = pathControl.clickedPathItem?.url ?? pathControl.url else { return }
      onSelectDirectory(url)
    }

    @objc private func selectMenuDirectory(_ menuItem: NSMenuItem) {
      guard let url = menuItem.representedObject as? URL else { return }
      onSelectDirectory(url)
    }

    func menuWillOpen(_: NSMenu) {
      DispatchQueue.main.async {
        self.isMenuOpen.wrappedValue = true
      }
    }

    func menuDidClose(_: NSMenu) {
      DispatchQueue.main.async {
        self.isMenuOpen.wrappedValue = false
      }
    }

    func pathControl(_ pathControl: NSPathControl, willPopUp menu: NSMenu) {
      menu.delegate = self
      removeCustomItems(from: menu)

      var insertionIndex = max(menu.items.count, 0)
      let sections = locationSections()
      guard !sections.isEmpty else { return }

      insertSeparator(into: menu, at: &insertionIndex)
      for (offset, section) in sections.enumerated() {
        if offset > 0 {
          insertSeparator(into: menu, at: &insertionIndex)
        }
        insertHeading(section.title, into: menu, at: &insertionIndex)
        for url in section.urls {
          insertLocation(url, currentURL: pathControl.url, into: menu, at: &insertionIndex)
        }
      }
      insertSeparator(into: menu, at: &insertionIndex)
    }

    func pathControl(_: NSPathControl, willDisplay openPanel: NSOpenPanel) {
      openPanel.canChooseFiles = false
      openPanel.canChooseDirectories = true
      openPanel.allowsMultipleSelection = false
      openPanel.canCreateDirectories = true
    }

    private func locationSections() -> [LocationSection] {
      var sections: [LocationSection] = []

      let iCloudLocations = availableDirectoryLocations(from: iCloudDirectoryURLs())
      if !iCloudLocations.isEmpty {
        sections.append(LocationSection(title: "iCloud Library", urls: iCloudLocations))
      }

      let commonLocations = availableDirectoryLocations(from: commonDirectoryURLs())
      if !commonLocations.isEmpty {
        sections.append(LocationSection(title: "Common Locations", urls: commonLocations))
      }

      let recentLocations = availableDirectoryLocations(from: recentDirectoryURLs, limit: 12)
      if !recentLocations.isEmpty {
        sections.append(LocationSection(title: "Recent Locations", urls: recentLocations))
      }

      return sections
    }

    private func iCloudDirectoryURLs() -> [URL] {
      let fileManager = FileManager.default
      var urls: [URL] = []
      if let containerURL = fileManager.url(forUbiquityContainerIdentifier: nil) {
        urls.append(containerURL)
      }

      urls.append(
        fileManager.homeDirectoryForCurrentUser
          .appending(
            path: "Library/Mobile Documents/com~apple~CloudDocs",
            directoryHint: .isDirectory,
          ),
      )
      return urls
    }

    private func commonDirectoryURLs() -> [URL] {
      let fileManager = FileManager.default
      let directories: [FileManager.SearchPathDirectory] = [
        .picturesDirectory,
        .moviesDirectory,
        .desktopDirectory,
        .downloadsDirectory,
        .documentDirectory,
      ]
      return directories.compactMap {
        fileManager.urls(for: $0, in: .userDomainMask).first
      }
    }

    private func availableDirectoryLocations(
      from urls: [URL],
      limit: Int = .max,
    ) -> [URL] {
      var seenPaths = Set<String>()
      var availableURLs: [URL] = []

      for url in urls where availableURLs.count < limit {
        let standardizedURL = url.standardizedFileURL
        let path = standardizedURL.filePath
        guard seenPaths.insert(path).inserted,
              (try? standardizedURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else {
          continue
        }
        availableURLs.append(standardizedURL)
      }

      return availableURLs
    }

    private func insertLocation(
      _ url: URL,
      currentURL: URL?,
      into menu: NSMenu,
      at index: inout Int,
    ) {
      let values = try? url.resourceValues(forKeys: [.localizedNameKey])
      let title = values?.localizedName ?? url.lastPathComponent
      let item = NSMenuItem(
        title: title,
        action: #selector(selectMenuDirectory(_:)),
        keyEquivalent: "",
      )
      item.target = self
      item.representedObject = url

      if url.lastPathComponent == "com~apple~CloudDocs" {
        let multicolorConfig = NSImage.SymbolConfiguration.preferringMulticolor()
        let icloudIcon = NSImage(systemSymbolName: "icloud.fill", accessibilityDescription: nil)?
          .withSymbolConfiguration(multicolorConfig)
        icloudIcon?.isTemplate = false
        item.image = icloudIcon ?? icon(for: url)
      } else {
        item.image = icon(for: url)
      }

      item.state = currentURL?.standardizedFileURL == url ? .on : .off
      identifyCustomItem(item)
      menu.insertItem(item, at: index)
      index += 1
    }

    private func insertHeading(
      _ title: LocalizedStringResource,
      into menu: NSMenu,
      at index: inout Int,
    ) {
      let headingItem = NSMenuItem.sectionHeader(title: String(localized: title))
      menu.insertItem(headingItem, at: index)
      index += 1
    }

    private func insertSeparator(into menu: NSMenu, at index: inout Int) {
      let item = NSMenuItem.separator()
      identifyCustomItem(item)
      menu.insertItem(item, at: index)
      index += 1
    }

    private func icon(for url: URL) -> NSImage {
      let workspaceIcon = NSWorkspace.shared.icon(forFile: url.filePath)
      let image = (workspaceIcon.copy() as? NSImage) ?? workspaceIcon
      image.size = NSSize(width: 16, height: 16)
      return image
    }

    private func identifyCustomItem(_ item: NSMenuItem) {
      item.identifier = NSUserInterfaceItemIdentifier(
        "\(customMenuIdentifierPrefix).\(UUID().uuidString)",
      )
    }

    private func removeCustomItems(from menu: NSMenu) {
      for item in menu.items.reversed() {
        guard item.identifier?.rawValue.hasPrefix(customMenuIdentifierPrefix) == true else {
          continue
        }
        menu.removeItem(item)
      }
    }
  }
}
