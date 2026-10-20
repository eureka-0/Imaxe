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
}

private nonisolated struct ReleaseLockFixture: Sendable {
  let root: URL

  var lock: URL {
    root.appending(path: "Build/.release.lock")
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

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appending(path: "imaxe-release-lock-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = FileManager.default
    for path in ["Scripts", "Imaxe", "tools"] {
      try manager.createDirectory(at: root.appending(path: path), withIntermediateDirectories: true)
    }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent()
    for path in ["Scripts/build-zip.sh", "Imaxe/Info.plist"] {
      try manager.copyItem(at: project.appending(path: path), to: root.appending(path: path))
    }
    try writeTool("git", source: """
    case "$1" in
      branch) echo main ;;
      remote) echo https://github.com/eureka-0/Imaxe.git ;;
    esac
    """)
    for name in ["gh", "jq", "swift", "xmllint", "curl", "shasum"] {
      try writeTool(name, source: "exit 99")
    }
    try writeTool("xcodebuild", source: """
    mkdir active-tool 2>/dev/null || exit 87
    trap 'rmdir active-tool' EXIT
    touch ready
    while [[ ! -f release && -d tools ]]; do sleep 0.01; done
    exit 23
    """)
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
    process.arguments = [root.appending(path: "Scripts/build-zip.sh").path] + arguments
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
