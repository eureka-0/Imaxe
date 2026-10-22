// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import Foundation

final class TestProcess {
  private let process = Process()

  static func run(
    _ executable: String,
    _ arguments: [String],
    environment: [String: String]? = nil,
    directory: URL? = nil,
  ) async throws -> (status: Int32, output: String) {
    let runner = TestProcess()
    let outputFile = FileManager.default.temporaryDirectory
      .appending(path: "imaxe-test-process-\(UUID().uuidString).log")
    try Data().write(to: outputFile)
    defer { try? FileManager.default.removeItem(at: outputFile) }
    let output = try FileHandle(forWritingTo: outputFile)
    defer { try? output.close() }
    runner.process.executableURL = URL(fileURLWithPath: executable)
    runner.process.arguments = arguments
    runner.process.environment = environment
    runner.process.currentDirectoryURL = directory
    // Files capture both streams without pipe backpressure or a blocked Swift worker.
    runner.process.standardOutput = output
    runner.process.standardError = output
    defer { runner.process.terminationHandler = nil }

    let status: Int32 = try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        runner.process.terminationHandler = { process in
          continuation.resume(returning: process.terminationStatus)
        }
        do {
          try runner.process.run()
        } catch {
          runner.process.terminationHandler = nil
          continuation.resume(throwing: error)
        }
      }
    } onCancel: {
      Task { await runner.terminate() }
    }
    try Task.checkCancellation()
    return try (status, String(contentsOf: outputFile, encoding: .utf8))
  }

  private func terminate() {
    if process.isRunning {
      process.terminate()
    }
  }
}
