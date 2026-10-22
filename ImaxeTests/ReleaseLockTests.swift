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
    let holder = try fixture.start(recordPID: true)
    try await fixture.waitUntilReady(holder)

    let contender = try await fixture.run(arguments: publish ? ["--publish"] : [])
    #expect(contender.status == 1)
    #expect(contender.output.contains("release build or publish already holds"))
    #expect(fixture.isLocked)

    try fixture.release()
    let failure = try await fixture.result(of: holder)
    #expect(failure.status == 23)
    #expect(!fixture.isLocked)

    let retry = try await fixture.run()
    #expect(retry.status == 23)
    #expect(!retry.output.contains("already holds"))
    #expect(!fixture.isLocked)
  }

  @Test func `terminated release frees its lock after the active tool exits`() async throws {
    let fixture = try ReleaseLockFixture()
    defer { fixture.remove() }
    let holder = try fixture.start(recordPID: true)
    try await fixture.waitUntilReady(holder)
    let pidText = try String(contentsOf: fixture.pidFile, encoding: .utf8)
    let pid = try #require(Int32(pidText))
    #expect(kill(pid, SIGTERM) == 0)
    try fixture.release()

    let result = try await fixture.result(of: holder)
    #expect(result.status == 143)
    #expect(!fixture.isLocked)
  }

  @Test func `readiness reports an early exit with status and output`() async throws {
    let fixture = try ReleaseLockFixture()
    defer { fixture.remove() }
    try fixture.writeTool("xcodebuild", source: "echo 'exited before ready' >&2; exit 42")
    let holder = try fixture.start(recordPID: true)

    do {
      try await fixture.waitUntilReady(holder)
      Issue.record("An exited release must not report readiness")
    } catch let error as ReleaseLockFailure {
      #expect(error.description.contains("exited before readiness"))
      #expect(error.description.contains("status=42"))
      #expect(error.description.contains("exited before ready"))
      #expect(error.description.contains("build-zip.sh:"))
    }
    #expect(!fixture.isLocked)
  }

  @Test func `readiness timeout keeps diagnostics and cleanup reaps the holder`() async throws {
    let fixture = try ReleaseLockFixture()
    defer { fixture.remove() }
    try fixture.writeTool("xcodebuild", source: """
    echo 'waiting before ready' >&2
    touch waiting
    while [[ ! -f release ]]; do sleep 0.01; done
    exit 23
    """)
    let holder = try fixture.start(recordPID: true)
    try await TestSupport.waitUntil {
      FileManager.default.fileExists(atPath: fixture.root.appending(path: "waiting").path)
    }

    do {
      try await fixture.waitUntilReady(holder, timeout: .milliseconds(100))
      Issue.record("A release without a ready marker must time out")
    } catch let error as ReleaseLockFailure {
      #expect(error.description.contains("timed out waiting for readiness"))
      #expect(error.description.contains("pid=\(holder.process.processIdentifier)"))
      #expect(error.description.contains("running=true"))
      #expect(error.description.contains("ready=false, locked=true"))
      #expect(error.description.contains("waiting before ready"))
    }

    fixture.remove()
    #expect(!holder.process.isRunning)
    #expect(!FileManager.default.fileExists(atPath: fixture.root.path))
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

    let result = try await fixture.run()
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

    let result = try await fixture.run()
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

    let result = try await fixture.run()
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

    let result = try await fixture.run()
    #expect(result.status == 1)
    #expect(result.output.contains(archive ? "refusing to overwrite" : "another artifact"))
    #expect(FileManager.default.fileExists(atPath: existing.path))
    #expect(!fixture.isLocked)
  }
}

private final class ReleaseLockFixture {
  let root: URL
  private var processes: [RunningRelease] = []

  struct RunningRelease {
    let process: Process
    let outputFile: URL
    let started: ContinuousClock.Instant
  }

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

  func writeTool(_ name: String, source: String) throws {
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

  func start(arguments: [String] = [], recordPID: Bool = false) throws -> RunningRelease {
    let process = Process()
    let outputFile = root.appending(path: "process-\(processes.count).log")
    try Data().write(to: outputFile)
    let output = try FileHandle(forWritingTo: outputFile)
    defer { try? output.close() }
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-x", root.appending(path: "scripts/build-zip.sh").path] + arguments
    process.currentDirectoryURL = root
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = "\(root.appending(path: "tools").path):/usr/bin:/bin"
    environment["PS4"] = "+ ${SECONDS}s ${BASH_SOURCE##*/}:${LINENO}: "
    process.environment = environment
    // A held process must not block Swift's cooperative executor or fill a pipe.
    process.standardOutput = output
    process.standardError = output
    let started = ContinuousClock.now
    try process.run()
    let running = RunningRelease(process: process, outputFile: outputFile, started: started)
    processes.append(running)
    if recordPID {
      try String(process.processIdentifier).write(to: pidFile, atomically: true, encoding: .utf8)
    }
    return running
  }

  func waitUntilReady(_ running: RunningRelease, timeout: Duration = .seconds(30)) async throws {
    do {
      try await TestSupport.waitUntil(timeout: timeout) {
        self.isReady || !running.process.isRunning
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw failure("timed out waiting for readiness", running: running)
    }
    guard running.process.isRunning else {
      throw failure("exited before readiness", running: running)
    }
  }

  func run(arguments: [String] = []) async throws -> (status: Int32, output: String) {
    try await result(of: start(arguments: arguments))
  }

  func result(of running: RunningRelease) async throws -> (status: Int32, output: String) {
    do {
      try await TestSupport.waitUntil { !running.process.isRunning }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw failure("timed out waiting for exit", running: running)
    }
    return try (
      running.process.terminationStatus,
      String(contentsOf: running.outputFile, encoding: .utf8),
    )
  }

  private func failure(_ reason: String, running: RunningRelease) -> ReleaseLockFailure {
    let process = running.process
    let status = process.isRunning ? "pending" : String(process.terminationStatus)
    let files = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
    let output = (try? String(
      contentsOf: running.outputFile,
      encoding: .utf8,
    )) ?? "No process output"
    return ReleaseLockFailure(
      description:
      """
      Release fixture \(reason) after \(running.started.duration(to: .now)).
      pid=\(process.processIdentifier), running=\(process.isRunning), status=\(status)
      root=\(root.path), ready=\(isReady), locked=\(isLocked), files=\(files.sorted())
      \(output)
      """,
    )
  }

  func release() throws {
    try Data().write(to: root.appending(path: "release"))
  }

  func remove() {
    try? release()
    for running in processes where running.process.isRunning {
      running.process.terminate()
    }
    for running in processes {
      running.process.waitUntilExit()
    }
    try? FileManager.default.removeItem(at: root)
  }
}

private struct ReleaseLockFailure: Error, CustomStringConvertible {
  let description: String
}
