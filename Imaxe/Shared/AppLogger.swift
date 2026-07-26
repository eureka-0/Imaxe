//
//  AppLogger.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/10.
//

import Foundation
import OSLog

// MARK: - Global Logging Function

nonisolated func appLog(
  _ message: String,
  level: AppLogLevel = .notice,
  category: AppLogCategory = .general,
  file: String = #fileID,
  function: String = #function,
  line: Int = #line,
) {
  AppLogger.shared.log(
    message,
    level: level,
    category: category,
    file: file,
    function: function,
    line: line,
  )
}

// MARK: - Enums

nonisolated enum AppLogCategory: String, Sendable {
  case general = "General"
  case imageLoading = "ImageLoading"
  case persistence = "Persistence"
  case userInterface = "UserInterface"
  case windowing = "Windowing"
}

nonisolated enum AppLogDestination: Sendable {
  case console
  case file
  case consoleAndFile
}

nonisolated enum AppLogLevel: String, Sendable {
  case debug
  case info
  case notice
  case error
  case fault

  var osLogType: OSLogType {
    switch self {
    case .debug: .debug
    case .info: .info
    case .notice: .default
    case .error: .error
    case .fault: .fault
    }
  }
}

// MARK: - AppLogger

actor AppLogger {
  static let shared = AppLogger()

  private struct Entry: Sendable {
    let message: String
    let level: AppLogLevel
    let category: AppLogCategory
    let file: String
    let function: String
    let line: Int
  }

  private static let subsystem = Bundle.main.identifier
  private static let maximumLogFileSize: UInt64 = 2 * 1024 * 1024

  private var destination: AppLogDestination = .console
  private var loggers: [AppLogCategory: Logger] = [:]
  private var logFileHandle: FileHandle?

  private init() {}

  deinit {
    try? logFileHandle?.close()
    logFileHandle = nil
  }

  nonisolated func log(
    _ message: String,
    level: AppLogLevel = .notice,
    category: AppLogCategory = .general,
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
  ) {
    let entry = Entry(
      message: message,
      level: level,
      category: category,
      file: file,
      function: function,
      line: line,
    )
    Task {
      await write(entry)
    }
  }

  nonisolated func setDestination(to destination: AppLogDestination) {
    Task {
      await setDestination(destination)
    }
  }

  private func setDestination(_ destination: AppLogDestination) {
    self.destination = destination
  }

  private func write(_ entry: Entry) {
    let source = "[\(entry.file):\(entry.line) \(entry.function)]"
    let formattedMessage = "\(source) \(entry.message)"

    switch destination {
    case .console:
      logToConsole(formattedMessage, level: entry.level, category: entry.category)
    case .file:
      logToFile(formattedMessage, level: entry.level, category: entry.category)
    case .consoleAndFile:
      logToConsole(formattedMessage, level: entry.level, category: entry.category)
      logToFile(formattedMessage, level: entry.level, category: entry.category)
    }
  }

  private func logger(for category: AppLogCategory) -> Logger {
    if let logger = loggers[category] {
      return logger
    }

    let logger = Logger(subsystem: Self.subsystem, category: category.rawValue)
    loggers[category] = logger
    return logger
  }

  private func logToConsole(
    _ message: String,
    level: AppLogLevel,
    category: AppLogCategory,
  ) {
    #if DEBUG
      logger(for: category).log(level: level.osLogType, "\(message, privacy: .public)")
    #else
      logger(for: category).log(level: level.osLogType, "\(message, privacy: .private)")
    #endif
  }

  private func logToFile(
    _ message: String,
    level: AppLogLevel,
    category: AppLogCategory,
  ) {
    do {
      let timestamp = Date.now.ISO8601Format()
      let line = "[\(timestamp)] [\(category.rawValue)] [\(level.rawValue)] \(message)\n"
      if let data = line.data(using: .utf8) {
        if UInt64(data.count) > Self.maximumLogFileSize {
          let truncatedLine =
            "[\(timestamp)] [\(category.rawValue)] [\(level.rawValue)] Log entry truncated.\n"
          guard let truncatedData = truncatedLine.data(using: .utf8) else { return }
          let fileHandle = try fileHandle(for: UInt64(truncatedData.count))
          try fileHandle.write(contentsOf: truncatedData)
          logger(for: .general).error("App log entry exceeded the file size limit.")
        } else {
          let fileHandle = try fileHandle(for: UInt64(data.count))
          try fileHandle.write(contentsOf: data)
        }
      }
    } catch {
      logger(for: .general).error(
        "Failed to write app log: \(error.localizedDescription, privacy: .public)",
      )
    }
  }

  private var logDirectory: URL {
    URL.dataDirectory.appendingPathComponent("Logs", isDirectory: true)
  }

  private func fileHandle(for lineSize: UInt64) throws -> FileHandle {
    if let logFileHandle {
      let currentSize = try logFileHandle.offset()
      if currentSize + lineSize <= Self.maximumLogFileSize {
        return logFileHandle
      }

      try logFileHandle.close()
      self.logFileHandle = nil
    }

    let fileHandle = try makeLogFileHandle(minimumAvailableBytes: lineSize)
    logFileHandle = fileHandle
    return fileHandle
  }

  private func makeLogFileHandle(minimumAvailableBytes: UInt64) throws -> FileHandle {
    try FileManager.default.ensureExists(for: logDirectory)

    let logFileURL = try availableLogFileURL(minimumAvailableBytes: minimumAvailableBytes)
    try FileManager.default.ensureExists(for: logFileURL, isDirectory: false)
    pruneOldLogFiles()

    let fileHandle = try FileHandle(forWritingTo: logFileURL)
    try fileHandle.seekToEnd()
    logger(for: .general).info(
      "Log file created.",
    )
    return fileHandle
  }

  private func availableLogFileURL(minimumAvailableBytes: UInt64) throws -> URL {
    let fileDate = Date.now.ISO8601Format(.iso8601Date(timeZone: .current))
    var index = 0

    while true {
      let suffix = index == 0 ? "" : "-\(index)"
      let url = logDirectory.appendingPathComponent("log-\(fileDate)\(suffix).txt")
      guard url.fileExists else { return url }

      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      if UInt64(size) + minimumAvailableBytes <= Self.maximumLogFileSize {
        return url
      }
      index += 1
    }
  }

  /// Prunes old log files to keep only the most recent 7 log files.
  private func pruneOldLogFiles() {
    do {
      let logFiles = try FileManager.default.contentsOfDirectory(
        at: logDirectory,
        includingPropertiesForKeys: [.creationDateKey],
        options: .skipsHiddenFiles,
      ).filter { $0.pathExtension == "txt" }

      let sortedLogFiles = try logFiles.sorted { file1, file2 in
        let date1 = try file1.resourceValues(forKeys: [.creationDateKey])
          .creationDate ?? .distantPast
        let date2 = try file2.resourceValues(forKeys: [.creationDateKey])
          .creationDate ?? .distantPast
        return date1 > date2
      }

      let filesToDelete = sortedLogFiles.dropFirst(7)
      for fileURL in filesToDelete {
        try FileManager.default.removeItem(at: fileURL)
        logger(for: .general).info(
          "Deleted an old log file.",
        )
      }
    } catch {
      logger(for: .general).error(
        "Failed to prune old log files.",
      )
    }
  }
}
