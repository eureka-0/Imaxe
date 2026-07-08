//
//  FileSnapshot.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/8.
//

import Foundation

nonisolated struct FileSnapshot: Equatable {
  let contentModificationDate: Date?
  let fileSize: Int?

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
  }
}
