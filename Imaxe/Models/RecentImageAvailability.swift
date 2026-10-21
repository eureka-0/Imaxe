// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import Foundation

nonisolated enum RecentImageAvailability: Sendable {
  case available, missing, unavailable

  static func check(_ url: URL) -> Self {
    guard url.isFileURL else { return .unavailable }
    let url = url.standardizedFileURL
    let components = url.pathComponents
    let fileManager = FileManager.default

    // A missing mount point must never look like a deleted image.
    if components.count > 2, components[1] == "Volumes" {
      let mountPath = "/Volumes/\(components[2])"
      guard let volumes = fileManager.mountedVolumeURLs(
        includingResourceValuesForKeys: [.volumeIsLocalKey],
        options: [],
      ), let volume = volumes.first(where: { $0.standardizedFileURL.path == mountPath }),
      (try? volume.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) == true
      else { return .unavailable }
    } else if components.count > 1, components[1] == "Network" {
      return .unavailable
    }

    do {
      _ = try fileManager.attributesOfItem(atPath: url.path)
      return .available
    } catch {
      guard isMissingFileError(error) else { return .unavailable }
    }

    // Confirm an accessible local ancestor; permission and network failures stay unknown.
    var parent = url.deletingLastPathComponent()
    while true {
      do {
        let attributes = try fileManager.attributesOfItem(atPath: parent.path)
        guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
          return .unavailable
        }
        let values = try parent.resourceValues(forKeys: [.isDirectoryKey, .volumeIsLocalKey])
        return values.isDirectory == true && values.volumeIsLocal == true ? .missing : .unavailable
      } catch {
        guard isMissingFileError(error), parent.path != "/" else { return .unavailable }
        parent.deleteLastPathComponent()
      }
    }
  }

  private static func isMissingFileError(_ error: Error) -> Bool {
    let error = error as NSError
    return (error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError)
      || (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT))
  }
}

nonisolated struct MissingImagesCleanupResult: Sendable {
  var removedCount = 0
  var unavailableCount = 0
}
