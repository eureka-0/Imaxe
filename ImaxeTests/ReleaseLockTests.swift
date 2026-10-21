// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import Darwin
import Foundation
@testable import Imaxe
import Testing

@Suite("Release Lock")
struct ReleaseLockTests {
  @Test(arguments: [false, true])
  func `build and publish cannot enter an active release or remove its lock`(
    publish: Bool,
  ) async throws {
    let fixture = try ReleaseLockFixture()
    defer { fixture.remove() }
    let holder = Task.detached { try fixture.run(recordPID: true) }
    try await TestSupport.waitUntil { fixture.isReady }

    let contender = try await Task.detached {
      try fixture.run(arguments: publish ? ["--publish"] : [])
    }.value
    #expect(contender.status == 1)
    #expect(contender.output.contains("release build or publish already holds"))
    #expect(fixture.isLocked)

    try fixture.release()
    let failure = try await holder.value
    #expect(failure.status == 23)
    #expect(!fixture.isLocked)

    let retry = try await Task.detached { try fixture.run() }.value
    #expect(retry.status == 23)
    #expect(!retry.output.contains("already holds"))
    #expect(!fixture.isLocked)
  }

  @Test func `terminated release frees its lock after the active tool exits`() async throws {
    let fixture = try ReleaseLockFixture()
    defer { fixture.remove() }
    let holder = Task.detached { try fixture.run(recordPID: true) }
    try await TestSupport.waitUntil { fixture.isReady }
    let pidText = try String(contentsOf: fixture.pidFile, encoding: .utf8)
    let pid = try #require(Int32(pidText))
    #expect(kill(pid, SIGTERM) == 0)
    try fixture.release()

    let result = try await holder.value
    #expect(result.status == 143)
    #expect(!fixture.isLocked)
  }

  @Test(arguments: [false, true])
  func `build requires version directory notes before network access`(
    invalidHeading: Bool,
  ) async throws {
    let fixture = try ReleaseLockFixture(holdBuildSettings: false)
    defer { fixture.remove() }
    if invalidHeading {
      try fixture.writeNotes("# Imaxe 0.9.0\n\nChanges.\n")
    }

    let result = try await Task.detached { try fixture.run() }.value
    #expect(result.status == 1)
    #expect(result.output
      .contains(invalidHeading ? "must start with # Imaxe 1.1.0" : fixture.notes.path))
    #expect(!fixture.isLocked)
    #expect(!FileManager.default
      .fileExists(atPath: fixture.root.appending(path: "network-called").path))
  }

  @Test func `notes only directory reaches build preflight without a root notes file or manifest`(
  ) async throws {
    let fixture = try ReleaseLockFixture(holdBuildSettings: false)
    defer { fixture.remove() }
    let notes = "# Imaxe 1.1.0\n\nChanges.\n"
    try fixture.writeNotes(notes)

    let result = try await Task.detached { try fixture.run() }.value
    #expect(result.status == 99) // Stop at the mocked network call, before a real archive.
    #expect(FileManager.default
      .fileExists(atPath: fixture.root.appending(path: "network-called").path))
    #expect(try String(contentsOf: fixture.notes, encoding: .utf8) == notes)
    #expect(try FileManager.default
      .contentsOfDirectory(atPath: fixture.releaseDirectory.path) == ["Imaxe-1.1.0.md"])
    #expect(!FileManager.default
      .fileExists(atPath: fixture.root.appending(path: "build/release-notes.md").path))
    #expect(!fixture.isLocked)
  }

  @Test(arguments: ["Imaxe-1.1.0.zip", "appcast.xml", "SHA256SUMS.txt", ".partial"])
  func `build refuses a directory containing existing artifacts`(name: String) async throws {
    let fixture = try ReleaseLockFixture(holdBuildSettings: false)
    defer { fixture.remove() }
    try fixture.writeNotes("# Imaxe 1.1.0\n\nChanges.\n")
    let artifact = fixture.releaseDirectory.appending(path: name)
    try "existing artifact".write(to: artifact, atomically: true, encoding: .utf8)

    let result = try await Task.detached { try fixture.run() }.value
    #expect(result.status == 1)
    #expect(result.output.contains("refusing to overwrite"))
    #expect(try String(contentsOf: artifact, encoding: .utf8) == "existing artifact")
    #expect(!fixture.isLocked)
  }

  @Test(arguments: [false, true])
  func `build refuses an archive or a different source for the same version and build`(
    archive: Bool,
  ) async throws {
    let fixture = try ReleaseLockFixture(holdBuildSettings: false)
    defer { fixture.remove() }
    try fixture.writeNotes("# Imaxe 1.1.0\n\nChanges.\n")
    let existing = fixture.root.appending(path: archive
      ? "build/Archives/Imaxe-1.1.0-42-aaaaaaaaaaaa.xcarchive"
      : "build/Releases/Imaxe-1.1.0-42-bbbbbbbbbbbb")
    try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)

    let result = try await Task.detached { try fixture.run() }.value
    #expect(result.status == 1)
    #expect(result.output.contains(archive ? "refusing to overwrite" : "another artifact"))
    #expect(FileManager.default.fileExists(atPath: existing.path))
    #expect(!fixture.isLocked)
  }
}

private nonisolated struct ReleaseLockFixture: Sendable {
  let root: URL

  var lock: URL {
    root.appending(path: "build/.release.lock")
  }

  var ready: URL {
    root.appending(path: "ready")
  }

  var pidFile: URL {
    root.appending(path: "pid")
  }

  var isLocked: Bool {
    FileManager.default.fileExists(atPath: lock.path)
  }

  var isReady: Bool {
    FileManager.default.fileExists(atPath: ready.path)
      && FileManager.default.fileExists(atPath: pidFile.path)
  }

  var releaseDirectory: URL {
    root.appending(path: "build/Releases/Imaxe-1.1.0-42-aaaaaaaaaaaa")
  }

  var notes: URL {
    releaseDirectory.appending(path: "Imaxe-1.1.0.md")
  }

  init(holdBuildSettings: Bool = true) throws {
    root = FileManager.default.temporaryDirectory
      .appending(path: "imaxe-release-lock-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = FileManager.default
    for path in ["scripts", "Imaxe", "tools"] {
      try manager.createDirectory(at: root.appending(path: path), withIntermediateDirectories: true)
    }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent()
    for path in ["scripts/build-zip.sh", "Imaxe/Info.plist"] {
      try manager.copyItem(at: project.appending(path: path), to: root.appending(path: path))
    }
    try writeTool("git", source: """
    case "$1" in
      branch) echo main ;;
      remote) echo https://github.com/eureka-0/Imaxe.git ;;
      rev-parse)
        if [[ "$2" == --short=12 ]]; then echo aaaaaaaaaaaa
        else echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; fi ;;
    esac
    """)
    for name in ["gh", "jq", "swift", "xmllint", "curl", "shasum"] {
      try writeTool(name, source: "exit 99")
    }
    if holdBuildSettings {
      try writeTool("xcodebuild", source: """
      mkdir active-tool 2>/dev/null || exit 87
      trap 'rmdir active-tool' EXIT
      touch ready
      while [[ ! -f release && -d tools ]]; do sleep 0.01; done
      exit 23
      """)
    } else {
      try writeTool("xcodebuild", source: """
      echo ' MARKETING_VERSION = 1.1.0'
      echo ' CURRENT_PROJECT_VERSION = 42'
      """)
      try writeTool("curl", source: "touch network-called; exit 99")
    }
  }

  func writeNotes(_ contents: String) throws {
    try FileManager.default.createDirectory(at: releaseDirectory, withIntermediateDirectories: true)
    try contents.write(to: notes, atomically: true, encoding: .utf8)
  }

  private func writeTool(_ name: String, source: String) throws {
    let url = root.appending(path: "tools/\(name)")
    try "#!/bin/bash\nset -euo pipefail\n\(source)\n".write(
      to: url,
      atomically: true,
      encoding: .utf8,
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: url.path,
    )
  }

  func run(arguments: [String] = [], recordPID: Bool = false) throws
    -> (status: Int32, output: String)
  {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [root.appending(path: "scripts/build-zip.sh").path] + arguments
    process.currentDirectoryURL = root
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = "\(root.appending(path: "tools").path):/usr/bin:/bin"
    process.environment = environment
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    if recordPID {
      try String(process.processIdentifier).write(to: pidFile, atomically: true, encoding: .utf8)
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (
      process.terminationStatus,
      String(data: data, encoding: .utf8) ?? "Non-UTF8 process output",
    )
  }

  func release() throws {
    try Data().write(to: root.appending(path: "release"))
  }

  func remove() {
    try? release()
    try? FileManager.default.removeItem(at: root)
  }
}
