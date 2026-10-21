// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import Foundation
@testable import Imaxe
import SwiftData
import SwiftUI
import Testing

@Suite("Test Storage")
struct TestStorageTests {
  @Test func `host uses isolated paths and preferences before application launch`() throws {
    let storage = try #require(TestStorage.current)
    let runID = storage.directory.deletingLastPathComponent().lastPathComponent
    #expect(UUID(uuidString: storage.directory.lastPathComponent) != nil)
    #expect(UUID(uuidString: runID) != nil)
    #expect(URL.dataDirectory == storage.directory.appending(
      path: "Data",
      directoryHint: .isDirectory,
    ))
    #expect(URL.thumbnailCachesDirectory.path.hasPrefix(storage.directory.path + "/"))
    #expect(AppSettings.userDefaults !== UserDefaults.standard)
    print("IMAXE_TEST_STORAGE_ROOT \(storage.directory.path)")
  }

  @Test func `contexts prepare shared directories concurrently`() async throws {
    for _ in 0 ..< 16 {
      let runID = UUID().uuidString
      let contexts = try (0 ..< 30).map { _ in
        try #require(TestStorage.Context(runID: runID, testID: UUID().uuidString))
      }
      let first = try #require(contexts.first)
      defer {
        try? FileManager.default.removeItem(at: first.directory.deletingLastPathComponent())
      }
      await Task.detached {
        DispatchQueue.concurrentPerform(iterations: contexts.count) { index in
          #expect(throws: Never.self) { try contexts[index].prepare() }
        }
      }.value
    }
  }

  @Test func `parallel contexts keep AppStorage and direct preference reads separate`() throws {
    let runID = UUID().uuidString
    let first = try #require(TestStorage.Context(runID: runID, testID: UUID().uuidString))
    let second = try #require(TestStorage.Context(runID: runID, testID: UUID().uuidString))
    defer {
      first.remove()
      second.remove()
      try? FileManager.default.removeItem(at: first.directory.deletingLastPathComponent())
    }
    let identifier = try #require(Bundle.main.bundleIdentifier)
    let original = UserDefaults.standard.persistentDomain(forName: identifier) ?? [:]
    let firstDefaults = first.makeDefaults()
    let secondDefaults = second.makeDefaults()
    for key in AppSettings.Keys.allCases {
      #expect(firstDefaults.object(forKey: key.rawValue) == nil)
    }
    let firstAppearance = AppStorage(wrappedValue: "system", "appearance", store: firstDefaults)
    let secondAppearance = AppStorage(wrappedValue: "system", "appearance", store: secondDefaults)
    firstAppearance.wrappedValue = "dark"
    firstDefaults.set("printSize", forKey: AppSettings.Keys.imageActualSizeStrategy.rawValue)
    #expect(firstDefaults.string(forKey: "appearance") == "dark")
    #expect(secondAppearance.wrappedValue == "system")
    #expect(firstDefaults.imageActualSizeStrategyValue == .printSize)
    #expect(secondDefaults.imageActualSizeStrategyValue == AppSettings.Defaults
      .imageActualSizeStrategy)
    #expect(NSDictionary(dictionary: UserDefaults.standard
        .persistentDomain(forName: identifier) ?? [:])
      .isEqual(to: original))
  }

  @Test func `cleanup removes only its own database cache and settings`() throws {
    let runID = UUID().uuidString
    let first = try #require(TestStorage.Context(runID: runID, testID: UUID().uuidString))
    let second = try #require(TestStorage.Context(runID: runID, testID: UUID().uuidString))
    defer {
      first.remove()
      second.remove()
      try? FileManager.default.removeItem(at: first.directory.deletingLastPathComponent())
    }
    try first.prepare()
    try second.prepare()
    let cache = first.directory.appending(path: "thumbnail.png")
    try Data([1, 2, 3]).write(to: cache)
    first.makeDefaults().set("dark", forKey: "appearance")
    second.makeDefaults().set("light", forKey: "appearance")
    do {
      let configuration = ModelConfiguration(url: first.directory
        .appending(path: "database.sqlite"))
      let container = try ModelContainer(for: RecentImage.self, configurations: configuration)
      container.mainContext.insert(RecentImage(url: second.directory.appending(path: "source.png")))
      try container.mainContext.save()
      #expect(try container.mainContext.fetchCount(FetchDescriptor<RecentImage>()) == 1)
    }
    first.remove()
    #expect(!FileManager.default.fileExists(atPath: first.directory.path))
    #expect(first.makeDefaults().object(forKey: "appearance") == nil)
    #expect(FileManager.default.fileExists(atPath: second.directory.path))
    #expect(second.makeDefaults().string(forKey: "appearance") == "light")
  }

  @Test func `storage rejects symlinks and cleanup preserves their destination`() throws {
    let context = try #require(TestStorage.Context(
      runID: UUID().uuidString,
      testID: UUID().uuidString,
    ))
    try context.prepare()
    let destination = try TestSupport.temporaryDirectory(prefix: "imaxe-storage-link-target")
    defer {
      try? FileManager.default.removeItem(at: context.directory.deletingLastPathComponent())
      try? FileManager.default.removeItem(at: destination)
    }
    let sentinel = destination.appending(path: "keep.txt")
    try Data([42]).write(to: sentinel)
    try FileManager.default.removeItem(at: context.directory)
    try FileManager.default.createSymbolicLink(
      at: context.directory,
      withDestinationURL: destination,
    )
    #expect(throws: (any Error).self) { try context.prepare() }
    context.remove()
    #expect(try Data(contentsOf: sentinel) == Data([42]))
  }

  @Test func `identifiers reject path traversal and empty values`() {
    let valid = UUID().uuidString
    #expect(TestStorage.Context(runID: "../outside", testID: valid) == nil)
    #expect(TestStorage.Context(runID: valid, testID: "") == nil)
    #expect(TestStorage.Context(runID: valid, testID: "../../outside") == nil)
  }

  @Test func `runner reclaims interrupted preferences without clearing another run`() async throws {
    let outer = try #require(TestStorage.current)
    let sentinel = outer.directory.appending(path: "keep-\(UUID().uuidString)")
    try Data([42]).write(to: sentinel)
    defer { try? FileManager.default.removeItem(at: sentinel) }
    let fixture = try TestSupport.temporaryDirectory(prefix: "imaxe-test-runner-cleanup")
    defer { try? FileManager.default.removeItem(at: fixture) }
    let manager = FileManager.default
    for path in ["scripts", "tools"] {
      try manager.createDirectory(
        at: fixture.appending(path: path),
        withIntermediateDirectories: true,
      )
    }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent()
    try manager.copyItem(
      at: project.appending(path: "scripts/test.sh"),
      to: fixture.appending(path: "scripts/test.sh"),
    )
    let testID = UUID().uuidString
    let tool = """
    #!/bin/bash
    set -euo pipefail
    run_id="${TEST_RUNNER_IMAXE_TEST_RUN_ID:?missing test run ID}"
    mkdir -p "/private/tmp/com.imaxe.ImaxeTests/$run_id/\(testID)"
    defaults write "com.imaxe.Imaxe.tests.$run_id.\(testID)" marker -string interrupted
    echo "$run_id" > interrupted-run
    exit 23
    """
    for (name, source) in [("xcodebuild", tool), ("xcbeautify", "#!/bin/bash\ncat\n")] {
      let url = fixture.appending(path: "tools/\(name)")
      try source.write(to: url, atomically: true, encoding: .utf8)
      try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
    let status = try await Task.detached {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/bash")
      process.arguments = [
        fixture.appending(path: "scripts/test.sh").path,
        "--skip-ui",
        "--no-coverage",
      ]
      process.currentDirectoryURL = fixture
      var environment = ProcessInfo.processInfo.environment
      environment["PATH"] = fixture.appending(path: "tools").path + ":/usr/bin:/bin:/usr/sbin:/sbin"
      process.environment = environment
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      try process.run()
      process.waitUntilExit()
      return process.terminationStatus
    }.value
    #expect(status == 23)
    let runID = try String(contentsOf: fixture.appending(path: "interrupted-run"), encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let interrupted = try #require(TestStorage.Context(runID: runID, testID: testID))
    defer { interrupted.remove() }
    #expect(interrupted.makeDefaults().object(forKey: "marker") == nil)
    #expect(!manager.fileExists(atPath: interrupted.directory.deletingLastPathComponent().path))
    #expect(try Data(contentsOf: sentinel) == Data([42]))
  }
}
