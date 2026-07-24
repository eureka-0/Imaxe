//
//  FileLocationPicker.swift
//  Imaxe
import AppKit
import SwiftUI

// MARK: - FileLocationPicker

struct FileLocationPicker: NSViewRepresentable {
  let directoryURL: URL?
  let recentDirectoryURLs: [URL]
  let onSelectDirectory: (URL) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(
      recentDirectoryURLs: recentDirectoryURLs,
      onSelectDirectory: onSelectDirectory,
    )
  }

  func makeNSView(context: Context) -> NSPathControl {
    let pathControl = NSPathControl()
    pathControl.pathStyle = .popUp
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
  }
}

// MARK: - Coordinator

extension FileLocationPicker {
  private struct LocationSection {
    let title: String
    let locations: [Location]
  }

  private struct Location {
    let title: String
    let url: URL
  }

  final class Coordinator: NSObject, NSPathControlDelegate {
    var recentDirectoryURLs: [URL]
    var onSelectDirectory: (URL) -> Void

    private let customMenuIdentifierPrefix = "FileLocationPicker.Custom"

    init(
      recentDirectoryURLs: [URL],
      onSelectDirectory: @escaping (URL) -> Void,
    ) {
      self.recentDirectoryURLs = recentDirectoryURLs
      self.onSelectDirectory = onSelectDirectory
    }

    @objc func selectDirectory(_ pathControl: NSPathControl) {
      guard let url = pathControl.clickedPathItem?.url ?? pathControl.url else { return }
      onSelectDirectory(url)
    }

    @objc private func selectMenuDirectory(_ menuItem: NSMenuItem) {
      guard let url = menuItem.representedObject as? URL else { return }
      onSelectDirectory(url)
    }

    func pathControl(_ pathControl: NSPathControl, willPopUp menu: NSMenu) {
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
        for location in section.locations {
          insertLocation(location, currentURL: pathControl.url, into: menu, at: &insertionIndex)
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
        sections.append(LocationSection(
          title: String(localized: "iCloud"),
          locations: iCloudLocations,
        ))
      }

      let favoriteLocations = availableDirectoryLocations(from: favoriteDirectoryURLs())
      if !favoriteLocations.isEmpty {
        sections.append(
          LocationSection(title: String(localized: "Favorites"), locations: favoriteLocations),
        )
      }

      let recentLocations = availableDirectoryLocations(from: recentDirectoryURLs, limit: 12)
      if !recentLocations.isEmpty {
        sections.append(
          LocationSection(
            title: String(localized: "Recent Locations"),
            locations: recentLocations,
          ),
        )
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

    private func favoriteDirectoryURLs() -> [URL] {
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
    ) -> [Location] {
      var seenPaths = Set<String>()
      var locations: [Location] = []

      for url in urls where locations.count < limit {
        let standardizedURL = url.standardizedFileURL
        let path = standardizedURL.filePath
        guard seenPaths.insert(path).inserted,
              (try? standardizedURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else {
          continue
        }

        let values = try? standardizedURL.resourceValues(forKeys: [.localizedNameKey])
        let title = values?.localizedName ?? standardizedURL.lastPathComponent
        locations.append(Location(title: title, url: standardizedURL))
      }

      return locations
    }

    private func insertLocation(
      _ location: Location,
      currentURL: URL?,
      into menu: NSMenu,
      at index: inout Int,
    ) {
      let item = NSMenuItem(
        title: location.title,
        action: #selector(selectMenuDirectory(_:)),
        keyEquivalent: "",
      )
      item.target = self
      item.representedObject = location.url
      item.image = icon(for: location.url)
      item.state = currentURL?.standardizedFileURL == location.url ? .on : .off
      identifyCustomItem(item)
      menu.insertItem(item, at: index)
      index += 1
    }

    private func insertHeading(_ title: String, into menu: NSMenu, at index: inout Int) {
      let headingItem = NSMenuItem.sectionHeader(title: title)
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
      let image = (NSWorkspace.shared.icon(forFile: url.filePath).copy() as? NSImage)
        ?? NSWorkspace.shared.icon(forFile: url.filePath)
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
