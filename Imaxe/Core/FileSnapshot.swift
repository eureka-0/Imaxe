//
//  FileSnapshot.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/8.
//

import Foundation

nonisolated struct FileSnapshot: Equatable, Sendable {
  let contentModificationDate: Date?
  let fileSize: Int?
  let fileSystemNumber: UInt64?
  let fileNumber: UInt64?

  init?(url: URL) {
    guard let resourceValues = try? url.freshResourceValues(forKeys: [
      .contentModificationDateKey,
      .fileSizeKey,
      .isRegularFileKey,
    ]),
      resourceValues.isRegularFile == true
    else { return nil }

    contentModificationDate = resourceValues.contentModificationDate
    fileSize = resourceValues.fileSize

    let attributes = try? FileManager.default.attributesOfItem(atPath: url.filePath)
    fileSystemNumber = (attributes?[.systemNumber] as? NSNumber)?.uint64Value
    fileNumber = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
  }

  func hasSameFileIdentity(as other: FileSnapshot) -> Bool {
    guard let fileSystemNumber,
          let fileNumber,
          let otherFileSystemNumber = other.fileSystemNumber,
          let otherFileNumber = other.fileNumber
    else { return true }

    return fileSystemNumber == otherFileSystemNumber && fileNumber == otherFileNumber
  }
}
