// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

#if DEBUG
  import Darwin
  import Foundation

  nonisolated enum TestStorage {
    static let current: Context? = {
      guard ProcessInfo.processInfo.arguments.contains("--disable-updates-for-testing") else {
        return nil
      }
      let environment = ProcessInfo.processInfo.environment
      let runID = environment["IMAXE_TEST_RUN_ID"] ?? UUID().uuidString
      let testID = environment["IMAXE_TEST_ID"] ?? UUID().uuidString
      guard let context = Context(runID: runID, testID: testID) else {
        fatalError("Invalid test storage identifier")
      }
      do {
        try context.prepare()
      } catch {
        fatalError("Unable to prepare isolated test storage: \(error)")
      }
      atexit { TestStorage.current?.remove() }
      return context
    }()

    struct Context: Sendable {
      let directory: URL
      let defaultsName: String

      init?(runID: String, testID: String) {
        guard UUID(uuidString: runID) != nil, UUID(uuidString: testID) != nil else {
          return nil
        }
        directory = URL(fileURLWithPath: "/private/tmp/com.imaxe.ImaxeTests", isDirectory: true)
          .appending(path: runID, directoryHint: .isDirectory)
          .appending(path: testID, directoryHint: .isDirectory)
        defaultsName = "com.imaxe.Imaxe.tests.\(runID).\(testID)"
      }

      func makeDefaults() -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: defaultsName) else {
          fatalError("Unable to create isolated test preferences")
        }
        return defaults
      }

      func prepare() throws {
        let manager = FileManager.default
        for path in directoryHierarchy {
          if !manager.fileExists(atPath: path.path) {
            do {
              try manager.createDirectory(
                at: path,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700],
              )
            } catch {
              guard (error as? CocoaError)?.code == .fileWriteFileExists else { throw error }
            }
          }
          guard isOwnedDirectory(path) else {
            throw CocoaError(.fileWriteNoPermission)
          }
        }
      }

      func remove() {
        let defaults = makeDefaults()
        defaults.removePersistentDomain(forName: defaultsName)
        defaults.synchronize()
        guard directoryHierarchy.allSatisfy(isOwnedDirectory) else { return }
        try? FileManager.default.removeItem(at: directory)
      }

      private var directoryHierarchy: [URL] {
        [
          directory.deletingLastPathComponent().deletingLastPathComponent(),
          directory.deletingLastPathComponent(),
          directory,
        ]
      }

      private func isOwnedDirectory(_ path: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path.path) else {
          return false
        }
        return attributes[.type] as? FileAttributeType == .typeDirectory
          && (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid()
      }
    }
  }
#endif
