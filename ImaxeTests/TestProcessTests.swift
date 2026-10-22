// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import Darwin
import Foundation
import Testing

@Suite("Test Process")
struct TestProcessTests {
  @Test func `captures both streams and nonzero status`() async throws {
    let result = try await TestProcess.run(
      "/bin/bash",
      ["-c", "printf stdout; printf stderr >&2; exit 23"],
    )
    #expect(result.status == 23)
    #expect(result.output.contains("stdout"))
    #expect(result.output.contains("stderr"))
  }

  @Test func `output larger than a pipe buffer completes`() async throws {
    let result = try await TestProcess.run("/usr/bin/head", ["-c", "131072", "/dev/zero"])
    #expect(result.status == 0)
    #expect(result.output.utf8.count == 131_072)
  }

  @Test func `launch failure propagates`() async {
    await #expect(throws: (any Error).self) {
      _ = try await TestProcess.run("/imaxe-missing-\(UUID().uuidString)", [])
    }
  }

  @Test func `cancellation waits for the child to exit`() async throws {
    let root = try TestSupport.temporaryDirectory(prefix: "imaxe-process-cancel")
    defer { try? FileManager.default.removeItem(at: root) }
    let pidFile = root.appending(path: "pid")
    let task = Task {
      try await TestProcess.run(
        "/bin/bash",
        ["-c", "echo $$ > \"$1\"; exec /bin/sleep 30", "test", pidFile.path],
      )
    }
    defer { task.cancel() }
    try await TestSupport.waitUntil { FileManager.default.fileExists(atPath: pidFile.path) }
    let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)))
    task.cancel()
    await #expect(throws: CancellationError.self) {
      _ = try await task.value
    }
    let probe = kill(pid, 0)
    let probeError = errno
    #expect(probe == -1)
    #expect(probeError == ESRCH)
  }
}
