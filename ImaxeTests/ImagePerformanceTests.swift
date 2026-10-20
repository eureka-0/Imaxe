// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import AppKit
import Darwin
@testable import Imaxe
import Testing
import UniformTypeIdentifiers

/// Run by itself for measurements: other suites share the test-host process and peak RSS.
@Suite("Image Performance", .serialized)
struct ImagePerformanceTests {
  @Test func `cold loader opens and draws registered formats at actual size and high zoom`(
  ) async throws {
    let samples = [
      "sample_1280×853.jpeg",
      "sample_1280×853.png",
      "sample_1280×853.tiff",
      "sample.heif",
      "sample.webp",
      "sample_384×512.gif",
      "sample_1280×853.svg",
    ]
    for name in samples {
      let loader = ImageLoader()
      let start = ContinuousClock.now
      let document = try await loader.loadDocument(from: TestSupport.sampleImageURL(name))
      let loaded = ContinuousClock.now
      let actual = try drawVisibleRegion(document, zoom: 1)
      let drawn = ContinuousClock.now
      let zoomed = try drawVisibleRegion(document, zoom: 4)
      #expect(actual.pixelsWide > 0 && zoomed.pixelsWide > 0)
      report("cold-open", values: [
        "sample": name,
        "load_ms": milliseconds(start.duration(to: loaded)),
        "first_draw_ms": milliseconds(start.duration(to: drawn)),
        "zoom_4x_draw_ms": milliseconds(drawn.duration(to: .now)),
        "retained_cost_bytes": document.cacheCost,
      ])
    }
  }

  @Test func `rapid switches and simulated slow directory retain current image`() async throws {
    let session = ImageSession()
    defer { session.close() }
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-rapid-large")
    defer { try? FileManager.default.removeItem(at: directory) }
    let data = try TestSupport.pngData(width: 5000, height: 4000)
    let samples = try (0 ..< 3).map { index in
      let url = directory.appending(path: "large-\(index).png")
      try data.write(to: url)
      return url
    }
    let loader = ImageLoader()
    session.loadImageDocument = { url, requestID in
      try await loader.loadDocument(from: url, requestID: requestID)
    }
    session.loadImageMetadata = { url, requestID in
      try await loader.loadMetadata(from: url, requestID: requestID)
    }
    let (gate, continuation) = AsyncStream<Void>.makeStream()
    defer { continuation.finish() }
    session.loadFolderImageURLs = { url in
      for await _ in gate {
        break
      }
      return [url]
    }
    let start = ContinuousClock.now
    for index in 0 ..< 30 {
      session.loadImage(
        from: samples[index % samples.count],
        addToRecent: false,
      )
    }
    let expectedURL = samples[29 % samples.count]
    try await TestSupport.waitUntil { session.displayedURL == expectedURL && !session.isLoading }
    let committed = ContinuousClock.now
    let document = try #require(session.currentDocument)
    #expect(document.metadata.rawPixelSize == IntSize(width: 5000, height: 4000))
    #expect(document.isDownsampled)
    _ = try drawVisibleRegion(document, zoom: 1)
    #expect(session.folderNavigator?.currentImageURL == expectedURL)
    report("rapid-switch-slow-scan", values: [
      "requests": 30,
      "source_width": 5000,
      "source_height": 4000,
      "commit_ms": milliseconds(start.duration(to: committed)),
      "first_draw_ms": milliseconds(start.duration(to: .now)),
      "scan_released": false,
    ])
    continuation.yield()
    continuation.finish()
  }

  @Test func `multiple canvases animated frames and cache eviction remain usable`() async throws {
    let loader = ImageLoader()
    let url = TestSupport.sampleImageURL("sample_384×512.gif")
    let start = ContinuousClock.now
    let document = try await loader.loadDocument(from: url)
    let first = try #require(document.makeAnimatedBitmapRepresentation())
    let second = try #require(document.makeAnimatedBitmapRepresentation())
    let frameCount = try #require(first.gifFrameCount)
    let actualWindow = makeCanvasWindow(document, zoom: 1)
    let zoomedWindow = makeCanvasWindow(document, zoom: 4)
    defer {
      actualWindow.window.contentView = nil
      zoomedWindow.window.contentView = nil
    }
    #expect(actualWindow.canvas.window !== zoomedWindow.canvas.window)
    #expect(actualWindow.canvas.document.id == zoomedWindow.canvas.document.id)
    for index in 0 ..< frameCount {
      first.setProperty(.currentFrame, withValue: index)
      let image = NSImage(size: document.nsImage.size)
      image.addRepresentation(first)
      _ = try ImageFixtureMatrix.render(image, size: NSSize(width: 64, height: 64))
    }
    #expect(second.currentGIFFrame == 0)
    _ = try drawVisibleRegion(actualWindow.canvas)
    _ = try drawVisibleRegion(zoomedWindow.canvas)
    await loader.clearCache()
    let reloaded = try await loader.loadDocument(from: url)
    #expect(reloaded.metadata == document.metadata)
    #expect(reloaded.renderedPixelSize == document.renderedPixelSize)
    report("animation-canvases-eviction", values: [
      "frames_drawn": frameCount,
      "simultaneous_windows": 2,
      "elapsed_ms": milliseconds(start.duration(to: .now)),
      "retained_cost_bytes": document.cacheCost,
    ])
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["IMAXE_SLOW_VOLUME_IMAGE"] != nil))
  func `optional slow volume image opens and draws`() async throws {
    guard let path = ProcessInfo.processInfo.environment["IMAXE_SLOW_VOLUME_IMAGE"] else { return }
    let url = URL(fileURLWithPath: path)
    let start = ContinuousClock.now
    let document = try await ImageLoader().loadDocument(from: url)
    _ = try drawVisibleRegion(document, zoom: 1)
    report("external-slow-volume", values: [
      "first_draw_ms": milliseconds(start.duration(to: .now)),
      "retained_cost_bytes": document.cacheCost,
    ])
  }

  private func drawVisibleRegion(
    _ document: ImageDocument,
    zoom: CGFloat,
  ) throws -> NSBitmapImageRep {
    let pair = makeCanvasWindow(document, zoom: zoom)
    defer { pair.window.contentView = nil }
    return try drawVisibleRegion(pair.canvas)
  }

  private func makeCanvasWindow(
    _ document: ImageDocument,
    zoom: CGFloat,
  ) -> (window: NSWindow, canvas: ImageCanvasView) {
    let defaults = UserDefaults.standard
    let key = AppSettings.Keys.imageActualSizeStrategy.rawValue
    let previous = defaults.object(forKey: key)
    defaults.set(ImageActualSizeStrategy.pixelSize.rawValue, forKey: key)
    defer {
      if let previous {
        defaults.set(previous, forKey: key)
      } else {
        defaults.removeObject(forKey: key)
      }
    }
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false,
    )
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
    let canvas = ImageCanvasView(document: document)
    scrollView.allowsMagnification = true
    scrollView.maxMagnification = 20
    scrollView.documentView = canvas
    window.contentView = scrollView
    let backingSize = window.convertToBacking(canvas.frame).size
    #expect(abs(backingSize.width - document.pixelSize.width) < 1)
    #expect(abs(backingSize.height - document.pixelSize.height) < 1)
    scrollView.magnification = zoom
    scrollView.layoutSubtreeIfNeeded()
    return (window, canvas)
  }

  private func drawVisibleRegion(_ canvas: ImageCanvasView) throws -> NSBitmapImageRep {
    let rect = canvas.visibleRect
    let rep = try #require(canvas.bitmapImageRepForCachingDisplay(in: rect))
    canvas.cacheDisplay(in: rect, to: rep)
    return rep
  }

  @Test func `long GIF respects total frame budget during playback preparation`() async throws {
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-long-gif")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "long.gif")
    let frame = try ImageFixtureMatrix.image(width: 512, height: 512)
    try ImageFixtureMatrix.write(Array(repeating: frame, count: 96), to: url, type: .gif)
    let start = ContinuousClock.now
    let document = try await ImageLoader().loadDocument(from: url)
    #expect(document.metadata.imageCount == 96)
    #expect(document.isDownsampled)
    let representation = try #require(document.makeAnimatedBitmapRepresentation())
    for index in 0 ..< 96 {
      representation.setProperty(.currentFrame, withValue: index)
      let image = NSImage(size: document.nsImage.size)
      image.addRepresentation(representation)
      _ = try ImageFixtureMatrix.render(image, size: NSSize(width: 32, height: 32))
    }
    if case let .animatedGIF(_, data) = document.content {
      #expect(document.cacheCost - data.count <= ImageLoadingPolicy.animationBytes)
    } else {
      Issue.record("Expected animated GIF content")
    }
    report("long-gif-budget", values: [
      "frames_drawn": 96,
      "elapsed_ms": milliseconds(start.duration(to: .now)),
      "rendered_width": document.renderedPixelSize.width,
      "retained_cost_bytes": document.cacheCost,
    ])
  }

  private func milliseconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
  }

  private func report(_ scenario: String, values: [String: Any]) {
    var usage = rusage()
    let status = getrusage(RUSAGE_SELF, &usage)
    var record = values
    record["scenario"] = scenario
    record["process_peak_rss_bytes"] = status == 0 ? usage.ru_maxrss : -1
    record["os"] = ProcessInfo.processInfo.operatingSystemVersionString
    if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
       let json = String(data: data, encoding: .utf8)
    {
      print("IMAXE_PERF \(json)")
    }
  }
}
