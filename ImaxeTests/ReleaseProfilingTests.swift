// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import Foundation
@testable import Imaxe
import Testing

@Suite("Release Profiling")
struct ReleaseProfilingTests {
  @Test func `sampler reads real process memory and validates measurement input`() async throws {
    let result = try await Task.detached { try Self.invoke(["self-test"]) }.value
    #expect(result.status == 0, "\(result.output)")
    #expect(result.output.contains("Release profiling self-check passed"))
  }

  @Test func `preparation rejects a source mismatch without creating output`() async throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-profile-source")
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appending(path: "output")
    let result = try await Task.detached {
      try Self.invoke([
        "prepare",
        directory.path,
        directory.path,
        output.path,
        String(repeating: "a", count: 40),
      ])
    }.value
    #expect(result.status == 1)
    #expect(result.output.contains("Release/source mismatch"))
    #expect(!FileManager.default.fileExists(atPath: output.path))
  }

  @Test func `preparation never replaces an existing measurement directory`() async throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-profile-existing")
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appending(path: "output")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
    let sentinel = output.appending(path: "keep.txt")
    try Data([42]).write(to: sentinel)
    let arguments = [
      "prepare",
      directory.appending(path: "release-aaaaaaaaaaaa").path,
      directory.path,
      output.path,
      String(repeating: "a", count: 40),
    ]
    let result = try await Task.detached {
      try Self.invoke(arguments)
    }.value
    #expect(result.status == 1)
    #expect(result.output.contains("Refusing to overwrite"))
    #expect(try Data(contentsOf: sentinel) == Data([42]))
  }

  @Test func `summary separates observer versions recording and traced runs`() async throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-profile-summary")
    defer { try? FileManager.default.removeItem(at: directory) }
    let tool = String(repeating: "a", count: 64)
    for index in 0 ..< 6 {
      let run = directory.appending(path: "runs/\(index)")
      try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
      var result: [String: Any] = [
        "sample": "sample.jpeg",
        "tool_sha256": tool,
        "recorded": index == 2,
        "trace_template": index == 3 ? "Time Profiler" : NSNull(),
        "target_accessible_image_found": true,
        "first_memory_sample_since_input_ms": 0.1,
        "rss_median_bytes": index == 0 ? 100 : 300,
        "footprint_median_bytes": index == 0 ? 200 : 400,
        "rss_sampled_peak_bytes": 500,
        "footprint_sampled_peak_bytes": 600,
      ]
      if index == 4 {
        result["tool_sha256"] = String(repeating: "b", count: 64)
      }
      if index == 5 {
        result.removeValue(forKey: "first_memory_sample_since_input_ms")
      }
      try JSONSerialization.data(withJSONObject: result)
        .write(to: run.appending(path: "result.json"))
    }
    let response = try await Task.detached { try Self.invoke(["summarize", directory.path, tool]) }
      .value
    #expect(response.status == 0, "\(response.output)")
    let data = try Data(contentsOf: directory.appending(path: "summary-aaaaaaaaaaaa.json"))
    let summary = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let rows = try #require(summary["rows"] as? [[String: Any]])
    #expect(rows.count == 1)
    #expect(rows.first?["n"] as? Int == 2)
    #expect(rows.first?["rss_median_bytes"] as? Double == 200)
    #expect(rows.first?["footprint_median_bytes"] as? Double == 300)
    #expect(rows.first?["first_visible_frame_ms"] is NSNull)
  }

  private nonisolated static func invoke(_ arguments: [String]) throws
    -> (status: Int32, output: String)
  {
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent()
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [project.appending(path: "scripts/profile-release.sh").path] + arguments
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (
      process.terminationStatus,
      String(data: data, encoding: .utf8) ?? "Non-UTF8 process output",
    )
  }
}
