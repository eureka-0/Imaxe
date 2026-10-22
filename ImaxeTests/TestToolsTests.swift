// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import Foundation
import Testing

@Suite("Test Tools")
struct TestToolsTests {
  @Test func `tools compile once and reject stale or changed products`() async throws {
    let root = try TestSupport.temporaryDirectory(prefix: "imaxe-tool-preparation")
    defer { try? FileManager.default.removeItem(at: root) }
    let manager = FileManager.default
    for name in ["scripts", "mock-tools"] {
      try manager.createDirectory(at: root.appending(path: name), withIntermediateDirectories: true)
    }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent()
    let script = root.appending(path: "scripts/prepare-test-tools.sh")
    try manager.copyItem(at: project.appending(path: "scripts/prepare-test-tools.sh"), to: script)
    for name in ["appcast", "validate-release", "profile-release"] {
      try "// test input\n".write(
        to: root.appending(path: "scripts/\(name).swift"),
        atomically: true,
        encoding: .utf8,
      )
    }
    for (name, contents) in [
      ("xcrun", Self.compiler),
      ("xcodebuild", "#!/bin/bash\necho \"${MOCK_XCODE_VERSION:-test-xcode}\"\n"),
    ] {
      let url = root.appending(path: "mock-tools/\(name)")
      try contents.write(to: url, atomically: true, encoding: .utf8)
      try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = root.appending(path: "mock-tools").path + ":/usr/bin:/bin"
    environment["MOCK_BUILD_LOG"] = root.appending(path: "builds").path
    let first = try await TestProcess.run("/bin/bash", [script.path], environment: environment)
    #expect(first.status == 0, "\(first.output)")
    let builds = try String(contentsOf: root.appending(path: "builds"), encoding: .utf8)
    #expect(builds.split(separator: "\n").count == 4)
    let reused = try await TestProcess.run("/bin/bash", [script.path], environment: environment)
    let verified = try await TestProcess.run(
      "/bin/bash",
      [script.path, "--verify"],
      environment: environment,
    )
    #expect(reused.status == 0 && verified.status == 0)
    #expect(try String(contentsOf: root.appending(path: "builds"), encoding: .utf8) == builds)
    environment["MOCK_SWIFT_HOST_TARGET"] = "consumer-os"
    let anotherHost = try await TestProcess.run(
      "/bin/bash",
      [script.path, "--verify"],
      environment: environment,
    )
    #expect(anotherHost.status == 0)

    let tool = root.appending(path: "build/Tools/Tests/appcast")
    try "changed".write(to: tool, atomically: true, encoding: .utf8)
    try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
    let changed = try await TestProcess.run(
      "/bin/bash",
      [script.path, "--verify"],
      environment: environment,
    )
    #expect(changed.status == 1)
    let rebuilt = try await TestProcess.run("/bin/bash", [script.path], environment: environment)
    #expect(rebuilt.status == 0)
    let originalTool = try Data(contentsOf: tool)
    try "// changed source".write(
      to: root.appending(path: "scripts/appcast.swift"),
      atomically: true,
      encoding: .utf8,
    )
    let stale = try await TestProcess.run(
      "/bin/bash",
      [script.path, "--verify"],
      environment: environment,
    )
    #expect(stale.status == 1)
    environment["MOCK_COMPILE_FAIL"] = "1"
    let failed = try await TestProcess.run("/bin/bash", [script.path], environment: environment)
    #expect(failed.status == 42)
    #expect(try Data(contentsOf: tool) == originalTool)
    environment["MOCK_COMPILE_FAIL"] = nil
    let recovered = try await TestProcess.run("/bin/bash", [script.path], environment: environment)
    #expect(recovered.status == 0)
    environment["MOCK_XCODE_VERSION"] = "another-xcode"
    let otherToolchain = try await TestProcess.run(
      "/bin/bash",
      [script.path, "--verify"],
      environment: environment,
    )
    #expect(otherToolchain.status == 1)
  }

  private static let compiler = """
  #!/bin/bash
  set -euo pipefail
  [[ "$1" != --sdk ]] || shift 2
  case "$1" in
    --show-sdk-version | --show-sdk-build-version) echo test-sdk ;;
    swiftc | clang)
      if [[ "$*" == *--version* ]]; then
        echo test-compiler
        [[ "$1" != swiftc ]] || echo "Target: ${MOCK_SWIFT_HOST_TARGET:-producer-os}"
        exit 0
      fi
      echo "$1" >> "$MOCK_BUILD_LOG"
      [[ "${MOCK_COMPILE_FAIL:-0}" != 1 ]] || exit 42
      while [[ "$1" != -o ]]; do shift; done
      printf '#!/bin/bash\\nexit 0\\n' > "$2"
      chmod +x "$2"
      ;;
    *) exit 64 ;;
  esac
  """
}
