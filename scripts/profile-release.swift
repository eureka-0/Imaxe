// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import AppKit
import ApplicationServices
import AVFoundation
import CryptoKit
import Darwin
import Foundation
import ImageIO
import ScreenCaptureKit
import Synchronization

struct ProfileError: LocalizedError {
  let errorDescription: String?
  init(_ message: String) {
    errorDescription = message
  }
}

nonisolated func require(_ condition: Bool, _ message: String) throws {
  if !condition {
    throw ProfileError(message)
  }
}

@discardableResult
func run(_ executable: String, _ arguments: [String]) throws -> String {
  let process = Process()
  let pipe = Pipe()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.standardOutput = pipe
  process.standardError = pipe
  try process.run()
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  let output = String(data: data, encoding: .utf8) ?? "Non-UTF8 process output"
  try require(process.terminationStatus == 0, "\(executable): \(output.prefix(1000))")
  return output.trimmingCharacters(in: .whitespacesAndNewlines)
}

func save(_ object: Any, to url: URL) throws {
  let data = try JSONSerialization.data(
    withJSONObject: object,
    options: [.prettyPrinted, .sortedKeys],
  )
  try data.write(to: url, options: .atomic)
}

func digest(_ url: URL) throws -> String {
  try SHA256.hash(data: Data(contentsOf: url, options: .mappedIfSafe))
    .map { String(format: "%02x", $0) }.joined()
}

func sourceProvenance(in feed: XMLDocument, commit: String) throws -> String {
  let source = try feed.nodes(forXPath: "/rss/channel/item/*[local-name()='sourceCommit']")
  if source.isEmpty {
    return "legacy appcast has no source commit; caller commit matched to directory; "
      + "ZIP hash verified"
  }
  try require(source.count == 1 && source.first?.stringValue == commit, "Appcast/source mismatch")
  return "source commit matched to appcast and directory; ZIP hash verified"
}

func hostTime() -> Double {
  CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))
}

func processExists(_ pid: pid_t) -> Bool {
  kill(pid, 0) == 0 || errno == EPERM
}

func terminateApplication(_ application: NSRunningApplication) async throws {
  guard processExists(application.processIdentifier) else { return }
  application.terminate()
  let deadline = hostTime() + 5
  while processExists(application.processIdentifier), hostTime() < deadline {
    try await Task.sleep(for: .milliseconds(50))
  }
  try require(
    !processExists(application.processIdentifier),
    "Imaxe did not quit; no force termination attempted",
  )
}

func accessibleImages(pid: pid_t) -> [String] {
  var pending = [AXUIElementCreateApplication(pid)]
  var labels: [String] = []
  var visited = 0
  while let element = pending.popLast(), visited < 5000 {
    visited += 1
    var role: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    if role as? String == kAXImageRole {
      var label: CFTypeRef?
      AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &label)
      if let label = label as? String {
        labels.append(label)
      }
    }
    for key in [kAXChildrenAttribute, kAXWindowsAttribute] {
      var children: CFTypeRef?
      AXUIElementCopyAttributeValue(element, key as CFString, &children)
      if let children = children as? [AXUIElement] {
        pending.append(contentsOf: children)
      }
    }
  }
  return labels
}

nonisolated struct MemorySample: Sendable {
  let time: Double
  let rss: UInt64
  let footprint: UInt64
  let cpu: UInt64

  static func read(_ pid: pid_t) throws -> MemorySample {
    var usage = rusage_info_v4()
    let status = withUnsafeMutablePointer(to: &usage) { pointer in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
        proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
      }
    }
    guard status == 0 else { throw ProfileError("proc_pid_rusage failed for PID \(pid): \(errno)") }
    return MemorySample(
      time: CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock())),
      rss: usage.ri_resident_size,
      footprint: usage.ri_phys_footprint,
      cpu: usage.ri_user_time + usage.ri_system_time,
    )
  }
}

func median(_ values: [Double]) throws -> Double {
  try require(!values.isEmpty && values.allSatisfy(\.isFinite), "Invalid measurement values")
  let ordered = values.sorted()
  let middle = ordered.count / 2
  return ordered.count.isMultiple(of: 2)
    ? (ordered[middle - 1] + ordered[middle]) / 2 : ordered[middle]
}

final nonisolated class CaptureLog: NSObject, SCStreamOutput, SCRecordingOutputDelegate {
  struct State {
    var frames: [[Double]] = []
    var started: Double?
    var finished = false
    var error: String?
    var reboundAt: Double?
  }

  let state = Mutex(State())

  func stream(
    _: SCStream,
    didOutputSampleBuffer sample: CMSampleBuffer,
    of type: SCStreamOutputType,
  ) {
    guard type == .screen, sample.isValid,
          let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sample,
            createIfNecessary: false,
          ) as? [[SCStreamFrameInfo: Any]],
          let rawStatus = attachments.first?[.status] as? Int,
          rawStatus == SCFrameStatus.complete.rawValue
    else { return }
    let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
    let received = CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))
    state.withLock { $0.frames.append([pts, received]) }
  }

  func recordingOutputDidStartRecording(_: SCRecordingOutput) {
    let now = CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))
    state.withLock { $0.started = now }
  }

  func recordingOutputDidFinishRecording(_: SCRecordingOutput) {
    state.withLock { $0.finished = true }
  }

  func recordingOutput(_: SCRecordingOutput, didFailWithError error: any Error) {
    state.withLock { $0.error = error.localizedDescription }
  }
}

struct Recording {
  let stream: SCStream
  let output: SCRecordingOutput
  let log: CaptureLog
  let directory: URL

  static func start(pid: pid_t, directory: URL) async throws -> Recording {
    try require(CGPreflightScreenCaptureAccess(), "Screen Recording permission is unavailable")
    let content = try await SCShareableContent.excludingDesktopWindows(
      true,
      onScreenWindowsOnly: true,
    )
    guard let application = content.applications.first(where: { $0.processID == pid }),
          let display = content.displays.first
    else { throw ProfileError("Cannot find target application or display for recording") }
    let filter = SCContentFilter(display: display, including: [application], exceptingWindows: [])
    let configuration = SCStreamConfiguration()
    configuration.width = min(display.width, 1920) / 2 * 2
    configuration.height = Int(Double(configuration.width) * Double(display.height)
      / Double(display.width)) / 2 * 2
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    configuration.queueDepth = 3
    configuration.showsCursor = false
    configuration.capturesAudio = false
    let log = CaptureLog()
    let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
    try stream.addStreamOutput(
      log,
      type: .screen,
      sampleHandlerQueue: DispatchQueue(label: "profile.frames"),
    )
    let outputConfiguration = SCRecordingOutputConfiguration()
    outputConfiguration.outputURL = directory.appending(path: "window.mp4")
    let output = SCRecordingOutput(configuration: outputConfiguration, delegate: log)
    try stream.addRecordingOutput(output)
    try await stream.startCapture()
    let deadline = hostTime() + 5
    while log.state.withLock({ $0.started == nil && $0.error == nil }), hostTime() < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    try require(
      log.state.withLock { $0.started != nil && $0.error == nil },
      "Recording did not start",
    )
    return Recording(stream: stream, output: output, log: log, directory: directory)
  }

  func finish() async throws {
    try await stream.stopCapture()
    let deadline = hostTime() + 5
    while log.state.withLock({ !$0.finished && $0.error == nil }), hostTime() < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    let state = log.state.withLock { $0 }
    let csv = "presentation_host_seconds,callback_host_seconds\n"
      + state.frames.map { "\($0[0]),\($0[1])" }.joined(separator: "\n") + "\n"
    try csv.write(to: directory.appending(path: "frames.csv"), atomically: true, encoding: .utf8)
    try save([
      "complete_frames": state.frames.count,
      "recording_started_host_seconds": state.started as Any? ?? NSNull(),
      "finished": state.finished,
      "error": state.error as Any? ?? NSNull(),
      "scope": "target PID windows only; other applications excluded; audio disabled",
      "first_visible_frame_ms": NSNull(),
      "video_to_host_clock_alignment": "pending calibration; frame CSV uses host-clock PTS",
      "target_window_rebound_host_seconds": state.reboundAt as Any? ?? NSNull(),
    ], to: directory.appending(path: "recording.json"))
    try require(state.finished && state.error == nil, state.error ?? "Recording did not finish")
  }

  func followImageWindow(pid: pid_t, name: String) async throws {
    let deadline = hostTime() + 5
    while hostTime() < deadline {
      let content = try await SCShareableContent.excludingDesktopWindows(
        true,
        onScreenWindowsOnly: false,
      )
      if let window = content.windows.first(where: {
        $0.owningApplication?.processID == pid && $0.title?.contains(name) == true
      }) {
        try await stream.updateContentFilter(SCContentFilter(desktopIndependentWindow: window))
        log.state
          .withLock { $0.reboundAt = CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock())) }
        return
      }
      try await Task.sleep(for: .milliseconds(20))
    }
    throw ProfileError("Unable to bind recording to target image window")
  }
}

enum ReleaseProfile {
  static let sampleNames = [
    "sample_1280×853.jpeg",
    "sample_1280×853.png",
    "sample_1280×853.tiff",
    "sample.heif",
    "sample.webp",
    "sample_384×512.gif",
    "sample_1280×853.svg",
  ]

  static let toolDigest = try? digest(URL(fileURLWithPath: CommandLine.arguments[0]))

  static func main() async {
    do {
      let arguments = Array(CommandLine.arguments.dropFirst())
      guard let command = arguments.first else { throw ProfileError(usage) }
      switch command {
      case "prepare":
        try require(arguments.count == 5, usage)
        try prepare(
          release: URL(fileURLWithPath: arguments[1]),
          images: URL(fileURLWithPath: arguments[2]),
          output: URL(fileURLWithPath: arguments[3]),
          commit: arguments[4],
        )
      case "open", "record", "trace", "baseline":
        try require(arguments.count == 4 && arguments[3] == "--current-account", usage)
        let root = URL(fileURLWithPath: arguments[1])
        if command == "baseline" {
          guard let count = Int(arguments[2]), (1 ... 10).contains(count) else {
            throw ProfileError("Baseline repetitions must be between 1 and 10")
          }
          for iteration in 1 ... count {
            for name in sampleNames {
              try await measure(
                root: root,
                name: name,
                record: false,
                trace: nil,
                iteration: iteration,
              )
            }
          }
        } else if command == "trace" {
          try await measure(
            root: root,
            name: "sample_1280×853.jpeg",
            record: false,
            trace: arguments[2],
          )
        } else {
          let names = arguments[2] == "all" ? sampleNames : [arguments[2]]
          for name in names {
            try require(sampleNames.contains(name), "Unknown sample: \(name)")
            try await measure(root: root, name: name, record: command == "record", trace: nil)
          }
        }
      case "self-test":
        try selfTest()
      case "summarize":
        try require(arguments.count == 3, usage)
        try summarize(root: URL(fileURLWithPath: arguments[1]), tool: arguments[2])
      default:
        throw ProfileError(usage)
      }
    } catch {
      FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
      exit(1)
    }
  }

  static let usage = """
  Usage (run with bash scripts/profile-release.sh):
    prepare RELEASE_DIRECTORY IMAGES_DIRECTORY NEW_OUTPUT_DIRECTORY SOURCE_COMMIT
    open PREPARED_DIRECTORY SAMPLE_NAME|all --current-account
    record PREPARED_DIRECTORY SAMPLE_NAME|all --current-account
    baseline PREPARED_DIRECTORY REPETITIONS_1_TO_10 --current-account
    trace PREPARED_DIRECTORY 'Time Profiler'|'System Trace'|'Allocations' --current-account
    self-test
    summarize PREPARED_DIRECTORY TOOL_SHA256
  open/record/trace gracefully quit existing Imaxe instances before launch and add recent records.
  No preferences or caches are reset. Recordings and traced timings are separate from open baselines.
  """

  static func prepare(release: URL, images: URL, output: URL, commit: String) throws {
    let manager = FileManager.default
    try require(commit.count == 40 && commit.allSatisfy(\.isHexDigit), "Invalid source commit")
    try require(
      release.lastPathComponent.hasSuffix("-" + commit.prefix(12)),
      "Release/source mismatch",
    )
    try require(!manager.fileExists(atPath: output.path), "Refusing to overwrite output directory")
    let entries = try manager.contentsOfDirectory(at: release, includingPropertiesForKeys: nil)
    let zips = entries.filter { $0.pathExtension == "zip" }
    try require(zips.count == 1, "Expected exactly one Release ZIP")
    guard let zip = zips.first else { throw ProfileError("Missing ZIP") }
    let checksum = try digest(zip)
    let checksums = try String(
      contentsOf: release.appending(path: "SHA256SUMS.txt"),
      encoding: .utf8,
    )
    try require(checksums.split(separator: "\n").contains {
      $0 == "\(checksum)  \(zip.lastPathComponent)"
    }, "ZIP checksum mismatch")
    let feed = try XMLDocument(
      contentsOf: release.appending(path: "appcast.xml"),
      options: .nodeLoadExternalEntitiesNever,
    )
    let provenance = try sourceProvenance(in: feed, commit: commit)
    let members = try run("/usr/bin/unzip", ["-Z1", zip.path]).split(separator: "\n")
    try require(!members.isEmpty && members.allSatisfy {
      !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..")
    }, "Unsafe ZIP member path")
    try manager.createDirectory(at: output, withIntermediateDirectories: true)
    try run("/usr/bin/ditto", ["-x", "-k", zip.path, output.appending(path: "extracted").path])
    let app = output.appending(path: "extracted/Imaxe.app")
    try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    let info = try PropertyListSerialization.propertyList(
      from: Data(contentsOf: app.appending(path: "Contents/Info.plist")),
      format: nil,
    ) as? [String: Any] ?? [:]
    guard let executable = info["CFBundleExecutable"] as? String,
          let identifier = info["CFBundleIdentifier"] as? String
    else { throw ProfileError("Missing application identity") }
    let samples = try sampleNames.map { name in
      try prepareSample(name: name, images: images, output: output)
    }
    let screenRecords: [[String: Any]] = NSScreen.screens.map { screen in
      [
        "name": screen.localizedName,
        "frame": NSStringFromRect(screen.frame),
        "backing_scale": screen.backingScaleFactor,
        "maximum_fps": screen.maximumFramesPerSecond,
      ]
    }
    let settings = UserDefaults.standard.persistentDomain(forName: identifier) ?? [:]
    let settingsXML = try PropertyListSerialization.data(
      fromPropertyList: settings,
      format: .xml,
      options: 0,
    )
    try save([
      "schema": 1,
      "created_at": ISO8601DateFormatter().string(from: Date()),
      "source_commit": commit,
      "zip_sha256": checksum,
      "zip_name": zip.lastPathComponent,
      "version": info["CFBundleShortVersionString"] ?? NSNull(),
      "build": info["CFBundleVersion"] ?? NSNull(),
      "bundle_identifier": identifier,
      "executable": executable,
      "executable_sha256": digest(app.appending(path: "Contents/MacOS/\(executable)")),
      "signature": run("/usr/bin/codesign", ["-dvvv", app.path]),
      "os": run("/usr/bin/sw_vers", []),
      "hardware": run("/usr/sbin/sysctl", ["hw.model", "hw.memsize", "machdep.cpu.brand_string"]),
      "power": run("/usr/bin/pmset", ["-g", "batt"]),
      "xcode": run("/usr/bin/xcodebuild", ["-version"]),
      "thermal_state": ProcessInfo.processInfo.thermalState.rawValue,
      "screens": screenRecords,
      "samples": samples,
      "accessibility": AXIsProcessTrusted(),
      "screen_recording": CGPreflightScreenCaptureAccess(),
      "cache_condition": "copied samples inspected; OS disk cache retained",
      "settings": String(data: settingsXML, encoding: .utf8) ?? "unavailable",
      "first_visible_frame_ms": NSNull(),
      "source_provenance": provenance,
    ], to: output.appending(path: "manifest.json"))
    print("Prepared \(output.path)")
  }

  static func prepareSample(name: String, images: URL, output: URL) throws -> [String: Any] {
    let source = images.appending(path: name)
    let destination = output.appending(path: "samples/\(name)")
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )
    try FileManager.default.copyItem(at: source, to: destination)
    var result: [String: Any] = try [
      "name": name,
      "sha256": digest(destination),
      "bytes": destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0,
    ]
    if let imageSource = CGImageSourceCreateWithURL(destination as CFURL, nil),
       CGImageSourceGetCount(imageSource) > 0
    {
      result["metadata_reader"] = "ImageIO"
      result["container_count"] = CGImageSourceGetCount(imageSource)
      let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [
        String: Any
      ] ??
        [:]
      for key in [
        kCGImagePropertyPixelWidth,
        kCGImagePropertyPixelHeight,
        kCGImagePropertyDepth,
        kCGImagePropertyOrientation,
        kCGImagePropertyDPIWidth,
        kCGImagePropertyDPIHeight,
        kCGImagePropertyProfileName,
        kCGImagePropertyColorModel,
        kCGImagePropertyHasAlpha,
      ] {
        result[key as String] = properties[key as String] ?? NSNull()
      }
    } else if destination.pathExtension.lowercased() == "svg" {
      let document = try XMLDocument(
        contentsOf: destination,
        options: .nodeLoadExternalEntitiesNever,
      )
      guard let svg = document.rootElement(), svg.localName == "svg" else {
        throw ProfileError("Invalid SVG root element")
      }
      result["metadata_reader"] = "SVG root attributes; no raster page count"
      result["container_count"] = NSNull()
      for attribute in ["width", "height", "viewBox"] {
        result["svg_" + attribute] = svg.attribute(forName: attribute)?.stringValue ?? NSNull()
      }
    }
    return result
  }

  static func measure(
    root: URL,
    name: String,
    record: Bool,
    trace: String?,
    iteration: Int = 1,
  ) async throws {
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root
        .appending(path: "manifest.json"))) as? [String: Any] ?? [:]
    guard let identifier = manifest["bundle_identifier"] as? String,
          let executable = manifest["executable"] as? String,
          let expectedHash = manifest["executable_sha256"] as? String,
          let sample = (manifest["samples"] as? [[String: Any]])?
            .first(where: { $0["name"] as? String == name }),
          let sampleHash = sample["sha256"] as? String
    else { throw ProfileError("Invalid prepared manifest") }
    let appURL = root.appending(path: "extracted/Imaxe.app")
    let executableURL = appURL.appending(path: "Contents/MacOS/\(executable)")
    let sampleURL = root.appending(path: "samples/\(name)")
    try require(digest(executableURL) == expectedHash, "Executable changed since prepare")
    try require(digest(sampleURL) == sampleHash, "Sample changed since prepare")
    for application in NSRunningApplication.runningApplications(withBundleIdentifier: identifier) {
      try await terminateApplication(application)
    }
    let directory = root.appending(path: "runs/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    let launchStart = hostTime()
    let app = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    defer { app.terminate() }
    try require(
      app.executableURL?.resolvingSymlinksInPath() == executableURL.resolvingSymlinksInPath(),
      "Launched the wrong application",
    )
    let launched = hostTime()
    try await Task.sleep(for: .seconds(1))
    let recording = record ? try await Recording.start(
      pid: app.processIdentifier,
      directory: directory,
    ) : nil
    let tracer = try trace
      .map { try startTrace($0, pid: app.processIdentifier, directory: directory) }
    if tracer != nil {
      try await Task.sleep(for: .seconds(3))
    }
    let baseline = try MemorySample.read(app.processIdentifier)
    let inputTime = hostTime()
    let pid = app.processIdentifier
    let samplingDeadline = inputTime + (tracer == nil ? 12 : 16)
    let sampling = Task.detached { try await sampleMemory(pid: pid, until: samplingDeadline) }
    defer { sampling.cancel() }
    let receiver = try await NSWorkspace.shared.open(
      [sampleURL],
      withApplicationAt: appURL,
      configuration: .init(),
    )
    try require(
      receiver.processIdentifier == app.processIdentifier,
      "File opened in another process",
    )
    app.activate()
    if let recording {
      try await recording.followImageWindow(pid: pid, name: name)
    }
    let samples = try await sampling.value
    let targetFound = try await finishEvidence(
      app: app,
      name: name,
      recording: recording,
      tracer: tracer,
    )
    var result: [String: Any] = [
      "sample": name,
      "iteration": iteration,
      "tool_sha256": toolDigest as Any? ?? NSNull(),
      "thermal_state": ProcessInfo.processInfo.thermalState.rawValue,
      "sample_sha256": sampleHash,
      "pid": app.processIdentifier,
      "executable": executableURL.path,
      "launch_start_host_seconds": launchStart,
      "application_open_return_ms": (launched - launchStart) * 1000,
      "input_host_seconds": inputTime,
      "home_rss_bytes": baseline.rss,
      "home_footprint_bytes": baseline.footprint,
      "recorded": record,
      "trace_template": trace as Any? ?? NSNull(),
      "trace_exit_status": tracer?.terminationStatus as Any? ?? NSNull(),
      "first_visible_frame_ms": NSNull(),
      "correctness": "pending video/visual verification",
      "target_accessible_image_found": targetFound,
      "cache_condition": "first file in fresh process; Home initialized for 1s; OS cache retained",
      "account": "current account; existing preferences/caches retained; recent records may be added",
    ]
    try result
      .merge(memoryMetrics(samples, inputTime: inputTime, directory: directory)) { _, value in
        value
      }
    try save(result, to: directory.appending(path: "result.json"))
    if let tracer {
      try require(tracer.terminationStatus == 0, "Instruments recording failed; see xctrace.log")
    }
    try require(targetFound, "Target image was not accessible at end of measurement")
    try await terminateApplication(app)
    FileHandle.standardOutput.write(Data("Measured \(name): \(directory.path)\n".utf8))
  }

  static func finishEvidence(
    app: NSRunningApplication,
    name: String,
    recording: Recording?,
    tracer: Process?,
  ) async throws -> Bool {
    let targetFound = accessibleImages(pid: app.processIdentifier).contains(name)
    if let recording {
      try await recording.finish()
      try await saveFinalWindow(
        pid: app.processIdentifier,
        name: name,
        directory: recording.directory,
      )
    }
    if let tracer {
      while tracer.isRunning {
        try await Task.sleep(for: .milliseconds(100))
      }
    }
    return targetFound
  }

  static func memoryMetrics(
    _ samples: [MemorySample],
    inputTime: Double,
    directory: URL,
  ) throws -> [String: Any] {
    let csv = "host_seconds,since_input_ms,rss_bytes,footprint_bytes,cpu_ns\n"
      + samples
      .map { "\($0.time),\(($0.time - inputTime) * 1000),\($0.rss),\($0.footprint),\($0.cpu)" }
      .joined(separator: "\n") + "\n"
    try csv.write(to: directory.appending(path: "memory.csv"), atomically: true, encoding: .utf8)
    let stable = samples.filter { $0.time - inputTime >= 2 }
    return try [
      "sample_period_requested_ms": 100,
      "samples": samples.count,
      "rss_median_bytes": median(stable.map { Double($0.rss) }),
      "footprint_median_bytes": median(stable.map { Double($0.footprint) }),
      "rss_sampled_peak_bytes": samples.map(\.rss).max() ?? 0,
      "footprint_sampled_peak_bytes": samples.map(\.footprint).max() ?? 0,
      "sampling_window": "2 seconds after input through end; not proof of steady state",
      "first_memory_sample_since_input_ms": ((samples.first.map(\.time) ?? inputTime) - inputTime) *
        1000,
    ]
  }

  nonisolated static func sampleMemory(
    pid: pid_t,
    until deadline: Double,
  ) async throws -> [MemorySample] {
    var samples: [MemorySample] = []
    while CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock())) < deadline {
      try Task.checkCancellation()
      try samples.append(MemorySample.read(pid))
      try await Task.sleep(for: .milliseconds(100))
    }
    return samples
  }

  static func startTrace(_ template: String, pid: pid_t, directory: URL) throws -> Process {
    try require(
      ["Time Profiler", "System Trace", "Allocations"].contains(template),
      "Unknown trace template",
    )
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = [
      "xctrace",
      "record",
      "--template",
      template,
      "--attach",
      String(pid),
      "--time-limit",
      "15s",
      "--no-prompt",
      "--output",
      directory.appending(path: "diagnostic.trace").path,
    ]
    let log = directory.appending(path: "xctrace.log")
    FileManager.default.createFile(atPath: log.path, contents: nil)
    let handle = try FileHandle(forWritingTo: log)
    defer { try? handle.close() }
    process.standardOutput = handle
    process.standardError = handle
    try process.run()
    return process
  }

  static func saveFinalWindow(pid: pid_t, name: String, directory: URL) async throws {
    let content = try await SCShareableContent.excludingDesktopWindows(
      true,
      onScreenWindowsOnly: false,
    )
    guard let window = content.windows.first(where: {
      $0.owningApplication?.processID == pid && $0.title?.contains(name) == true
    }) else { throw ProfileError("Missing target window for final screenshot") }
    let configuration = SCStreamConfiguration()
    configuration.width = Int(window.frame.width) * 2
    configuration.height = Int(window.frame.height) * 2
    let image = try await SCScreenshotManager.captureImage(
      contentFilter: SCContentFilter(desktopIndependentWindow: window),
      configuration: configuration,
    )
    let snapshot = directory.appending(path: "final-window.png")
    guard let destination = CGImageDestinationCreateWithURL(
      snapshot as CFURL,
      "public.png" as CFString,
      1,
      nil,
    )
    else { throw ProfileError("Unable to create screenshot destination") }
    CGImageDestinationAddImage(destination, image, nil)
    try require(CGImageDestinationFinalize(destination), "Unable to save final window")
  }

  static func selfTest() throws {
    try require(median([3, 1, 2]) == 2, "Odd median failed")
    try require(median([4, 1, 3, 2]) == 2.5, "Even median failed")
    do {
      _ = try median([])
      throw ProfileError("Empty measurements accepted")
    } catch let error as ProfileError {
      try require(
        error.errorDescription == "Invalid measurement values",
        "Empty-value validation failed",
      )
    }
    let commit = String(repeating: "a", count: 40)
    let legacy = try XMLDocument(xmlString: "<rss><channel><item/></channel></rss>")
    try require(
      sourceProvenance(in: legacy, commit: commit).hasPrefix("legacy appcast"),
      "Legacy appcast rejected",
    )
    let current = try XMLDocument(
      xmlString: "<rss><channel><item><sourceCommit>\(commit)</sourceCommit></item></channel></rss>",
    )
    try require(
      sourceProvenance(in: current, commit: commit).hasPrefix("source commit matched"),
      "Appcast source not verified",
    )
    do {
      _ = try sourceProvenance(in: current, commit: String(repeating: "b", count: 40))
      throw ProfileError("Mismatched source accepted")
    } catch let error as ProfileError {
      try require(error.errorDescription == "Appcast/source mismatch", "Source validation failed")
    }
    let sample = try MemorySample.read(getpid())
    try require(
      sample.rss > 0 && sample.footprint > 0 && sample.time.isFinite,
      "Process memory sampler returned invalid values",
    )
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try child.run()
    child.waitUntilExit()
    try require(!processExists(child.processIdentifier), "Exited process reported as still running")
    let fixture = FileManager.default.temporaryDirectory
      .appending(path: "imaxe-profile-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: fixture) }
    let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" "
      + "width=\"8pt\" height=\"6pt\" viewBox=\"0 0 8 6\"/>"
    try svg.write(to: fixture.appending(path: "sample.svg"), atomically: true, encoding: .utf8)
    let metadata = try prepareSample(
      name: "sample.svg",
      images: fixture,
      output: fixture.appending(path: "output"),
    )
    try require(
      metadata["container_count"] is NSNull && metadata["svg_width"] as? String == "8pt",
      "SVG metadata incorrectly treated as an empty raster container",
    )
    print("Release profiling self-check passed")
  }

  static func summarize(root: URL, tool: String) throws {
    try require(tool.count == 64 && tool.allSatisfy(\.isHexDigit), "Invalid tool digest")
    let runs = try FileManager.default.contentsOfDirectory(
      at: root.appending(path: "runs"),
      includingPropertiesForKeys: nil,
    )
    var groups: [String: [[String: Any]]] = [:]
    for directory in runs {
      let file = directory.appending(path: "result.json")
      guard let data = try? Data(contentsOf: file),
            let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            result["tool_sha256"] as? String == tool,
            result["recorded"] as? Bool == false,
            result["trace_template"] is NSNull,
            result["target_accessible_image_found"] as? Bool == true,
            result["first_memory_sample_since_input_ms"] is NSNumber,
            let name = result["sample"] as? String
      else { continue }
      groups[name, default: []].append(result)
    }
    try require(!groups.isEmpty, "No valid untraced baseline for the requested tool")
    let rows = try groups.keys.sorted().map { name -> [String: Any] in
      let records = groups[name] ?? []
      func values(_ key: String) throws -> [Double] {
        let values = records.compactMap { ($0[key] as? NSNumber)?.doubleValue }
        try require(values.count == records.count, "Incomplete memory result")
        return values
      }
      return try [
        "sample": name,
        "n": records.count,
        "rss_median_bytes": median(values("rss_median_bytes")),
        "footprint_median_bytes": median(values("footprint_median_bytes")),
        "rss_sampled_peak_bytes": values("rss_sampled_peak_bytes").max() ?? 0,
        "footprint_sampled_peak_bytes": values("footprint_sampled_peak_bytes").max() ?? 0,
        "first_visible_frame_ms": NSNull(),
      ]
    }
    let output = root.appending(path: "summary-\(tool.prefix(12)).json")
    try save(["tool_sha256": tool, "rows": rows], to: output)
    print("Summary: \(output.path)")
  }
}

await ReleaseProfile.main()
