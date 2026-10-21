// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import Foundation
@testable import Imaxe
import Testing

@Suite("Updates Pipeline")
struct UpdatesPipelineTests {
  @Test func `aggregate retains seven numeric builds and removes withdrawn releases`() async throws {
    let result = try await Task.detached {
      let fixture = try UpdatesFixture()
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      var releases: [[String: Any]] = []
      for build in 9 ... 20 {
        try fixture.record(build)
        if build != 20 {
          releases.append(fixture.release(build, draft: build == 18, prerelease: build == 19))
        }
      }
      let feed = fixture.root.appending(path: "appcast.xml")
      let catalog = fixture.root.appending(path: "releases.json")
      try JSONSerialization.data(withJSONObject: [releases]).write(to: catalog)
      let first = try fixture.run(["merge", fixture.root.path, catalog.path, feed.path])
      guard first.status == 0 else { throw UpdatesTestError(first.output) }
      let original = try Data(contentsOf: feed)
      let document = try XMLDocument(data: original)
      let builds = try document.nodes(forXPath: "/rss/channel/item/*[local-name()='version']")
        .compactMap(\.stringValue)
      let second = try fixture.run(["merge", fixture.root.path, catalog.path, feed.path])
      return try (builds, second.status, original == Data(contentsOf: feed))
    }.value
    #expect(result.0 == ["17", "16", "15", "14", "13", "12", "11"])
    #expect(result.1 == 0 && result.2)
  }

  @Test func `aggregate rejects duplicate builds and missing history before publishing`(
  ) async throws {
    let outputs = try await Task.detached {
      let fixture = try UpdatesFixture()
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      try fixture.record(12)
      try fixture.record(13, build: 12)
      let catalog = fixture.root.appending(path: "releases.json")
      try JSONSerialization.data(withJSONObject: [[fixture.release(12), fixture.release(13)]])
        .write(to: catalog)
      let duplicate = try fixture.run(["catalog", fixture.root.path, catalog.path])
      try FileManager.default.removeItem(at: fixture.root.appending(path: "v1.0.13"))
      let missing = try fixture.run(["catalog", fixture.root.path, catalog.path])
      return (duplicate, missing)
    }.value
    #expect(outputs.0.status != 0 && outputs.0.output.contains("Duplicate stable build"))
    #expect(outputs.1.status != 0)
  }

  @Test func `public verification waits for propagation and preserves failure evidence`(
  ) async throws {
    let results = try await Task.detached {
      let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      let expected = root.appending(path: "expected.xml")
      try "<rss>new feed</rss>".write(to: expected, atomically: true, encoding: .utf8)
      let curl = root.appending(path: "curl")
      let mock = """
      #!/bin/bash
      set -eu
      headers=''
      output=''
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --dump-header) headers="$2"; shift ;;
          --output) output="$2"; shift ;;
        esac
        shift
      done
      count=0
      if [[ -f "$MOCK_COUNT" ]]; then count="$(cat "$MOCK_COUNT")"; fi
      count=$((count + 1))
      echo "$count" > "$MOCK_COUNT"
      printf 'HTTP/2 200\\nAge: 599\\nETag: old\\nX-Cache: HIT\\n' > "$headers"
      if [[ "$count" -le 2 || "$MOCK_ALWAYS_OLD" == true ]]; then
        echo '<rss>old feed</rss>' > "$output"
      else
        cp "$MOCK_EXPECTED" "$output"
      fi
      exit "${MOCK_CURL_ERROR:-0}"
      """
      try mock.write(to: curl, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: curl.path)
      var environment = ProcessInfo.processInfo.environment
      environment["PATH"] = root.path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
      environment["MOCK_COUNT"] = root.appending(path: "count").path
      environment["MOCK_EXPECTED"] = expected.path
      environment["MOCK_ALWAYS_OLD"] = "false"
      environment["FEED_VERIFY_ATTEMPTS"] = "3"
      environment["FEED_VERIFY_DELAY"] = "0"
      environment["FEED_VERIFY_TIMEOUT"] = "10"
      let script = UpdatesFixture.project.appending(path: "scripts/verify-feed.sh").path
      let args = [
        script,
        expected.path,
        "https://example.invalid/appcast.xml",
        root.appending(path: "diagnostics").path,
      ]
      let propagated = try updatesRun("/bin/bash", args, environment: environment)
      environment["MOCK_ALWAYS_OLD"] = "true"
      let stale = try updatesRun("/bin/bash", args, environment: environment)
      environment["MOCK_ALWAYS_OLD"] = "false"
      environment["MOCK_CURL_ERROR"] = "28"
      let networkFailure = try updatesRun("/bin/bash", args, environment: environment)
      let evidence = FileManager.default
        .fileExists(atPath: root.appending(path: "diagnostics/attempt-3-canonical.headers").path)
      return (propagated, stale, networkFailure, evidence)
    }.value
    #expect(results.0.status == 0 && results.0.output.contains("attempt=2/3"))
    #expect(results.0.output.contains("Age: 599"))
    #expect(results.1.status != 0 && results.1.output.contains("did not converge"))
    #expect(results.2.status != 0 && results.2.output.contains("curl_status=28"))
    #expect(results.3)
  }
}

private nonisolated struct UpdatesTestError: Error {
  let message: String; init(_ message: String) {
    self.message = message
  }
}

private nonisolated struct UpdatesFixture {
  static var project: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
  }

  let root: URL
  let tool: URL

  init() throws {
    root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    tool = root.appending(path: "appcast")
    let result = try updatesRun(
      "/usr/bin/xcrun",
      ["swiftc", Self.project.appending(path: "scripts/appcast.swift").path, "-o", tool.path],
    )
    guard result.status == 0 else { throw UpdatesTestError(result.output) }
  }

  func record(_ version: Int, build: Int? = nil) throws {
    let directory = root.appending(path: "v1.0.\(version)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let xml = """
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
      xmlns:imaxe="https://github.com/eureka-0/Imaxe/appcast"><channel><item>
    <sparkle:version>\(build ?? version)</sparkle:version>
    <sparkle:shortVersionString>1.0.\(version)</sparkle:shortVersionString>
    <imaxe:sourceCommit>\(String(repeating: "a", count: 40))</imaxe:sourceCommit>
    </item></channel></rss>
    """
    try xml.write(to: directory.appending(path: "appcast.xml"), atomically: true, encoding: .utf8)
  }

  func release(_ version: Int, draft: Bool = false, prerelease: Bool = false) -> [String: Any] {
    [
      "tag_name": "v1.0.\(version)",
      "draft": draft,
      "prerelease": prerelease,
      "assets": [["name": "Imaxe-1.0.\(version).zip"], ["name": "SHA256SUMS.txt"]],
    ]
  }

  func run(_ arguments: [String]) throws -> (status: Int32, output: String) {
    try updatesRun(tool.path, arguments)
  }
}

private nonisolated func updatesRun(
  _ executable: String,
  _ arguments: [String],
  environment: [String: String]? = nil,
) throws -> (status: Int32, output: String) {
  let process = Process()
  let pipe = Pipe()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.environment = environment
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
