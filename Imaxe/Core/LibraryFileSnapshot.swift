//
//  LibraryFileSnapshot.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/3.
//

import Foundation

nonisolated struct LibraryFileSnapshot: Hashable {
  let url: URL
  let location: String
  let isFileURL: Bool
  let displayName: String
  let contentModificationDate: Date?
  let fileSize: Int
  let isDirectory: Bool

  init(url: URL) {
    self.url = url
    location = Self.location(for: url)
    isFileURL = url.isFileURL
    displayName = Self.displayName(for: url)

    if url.isFileURL {
      let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
      isDirectory = resourceValues?.isDirectory == true

      if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
        contentModificationDate = attributes[.modificationDate] as? Date
        fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
      } else {
        contentModificationDate = nil
        fileSize = 0
      }
    } else {
      contentModificationDate = nil
      fileSize = 0
      isDirectory = false
    }
  }

  static func location(for url: URL) -> String {
    if url.isFileURL {
      return url.standardizedFileURL.path
    }

    return url.absoluteString
  }

  private static func displayName(for url: URL) -> String {
    let name = url.lastPathComponent
    return name.isEmpty ? location(for: url) : name
  }
}
