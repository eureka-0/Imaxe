// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import AppKit
import XCTest

@MainActor
final class ImaxeUITests: XCTestCase {
  var app: XCUIApplication!
  private var testDirectory: URL?

  private var clearRecentImagesButton: XCUIElement {
    app.windows.buttons["Clear Recent Images"]
  }

  private var cleanUpMissingImagesButton: XCUIElement {
    app.windows.buttons["Clean Up Missing Images"]
  }

  override func setUp() async throws {
    try await super.setUp()

    continueAfterFailure = false
    app = XCUIApplication()
    let directory = URL(fileURLWithPath: "/private/tmp/com.imaxe.ImaxeUITests", isDirectory: true)
      .appending(path: "imaxe-ui-\(UUID().uuidString)", directoryHint: .isDirectory)
    testDirectory = directory
    app.launchEnvironment = ["IMAXE_UI_TEST_DIRECTORY": directory.path]
    app.launchArguments = [
      "--disable-updates-for-testing",
      "-AppleLanguages",
      "(en)",
      "-AppleLocale",
      "en_US",
      "-recentImagesViewMode",
      "grid",
      "-recentImagesCountLimit",
      "100",
      "-enableLoopBrowsing",
      "YES",
    ]
    app.terminate()
    app.launch()
    app.activate()
  }

  override func tearDown() async throws {
    app.terminate()
    try await super.tearDown()
  }

  func testRecentImagesCleanupAndFilteredClearConfirmation() throws {
    showHomeWindow()
    XCTAssertTrue(clearRecentImagesButton.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertFalse(clearRecentImagesButton.isEnabled)
    XCTAssertFalse(cleanUpMissingImagesButton.isEnabled)
    let originals = try launchWithRecentImages()
    XCTAssertTrue(app.buttons["sample_1280×853.png"].waitForExistence(timeout: 5))
    XCTAssertLessThan(cleanUpMissingImagesButton.frame.midX, clearRecentImagesButton.frame.midX)
    keepScreenshot(clearRecentImagesButton, name: "Recent images actions in English")

    cleanUpMissingImagesButton.click()
    let cleanupMessage = """
    Missing image records removed: 1. Records kept because their files could not be verified: 1. \
    Original images are kept.
    """
    XCTAssertTrue(app.staticTexts[cleanupMessage].waitForExistence(timeout: 10))
    app.sheets.buttons["OK"].firstMatch.click()
    waitForDisappearance(app.sheets.firstMatch)

    setRecentImagesSearch(to: "png")
    waitForDisappearance(app.buttons["sample_1280×853.jpeg"])
    clearRecentImagesButton.click()
    let cancel = app.windows.buttons["Cancel"].firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: 5))
    keepScreenshot(cancel, name: "Clear confirmation includes filtered records")
    cancel.click()
    waitForDisappearance(app.sheets.firstMatch)
    app.buttons["Clear Search"].click()
    XCTAssertTrue(app.buttons["sample_1280×853.jpeg"].waitForExistence(timeout: 5))

    setRecentImagesSearch(to: "png")
    clearRecentImagesButton.click()
    let confirm = app.sheets.buttons["Clear Recent Images"].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    confirm.click()
    XCTAssertTrue(app.staticTexts["No recent images yet"].waitForExistence(timeout: 5))
    XCTAssertFalse(clearRecentImagesButton.isEnabled)
    XCTAssertFalse(cleanUpMissingImagesButton.isEnabled)
    for url in originals {
      XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
  }

  private func setRecentImagesSearch(to text: String) {
    if !app.textFields["Search"].isHittable {
      app.windows.buttons["Search"].click()
    }
    let field = app.textFields["Search"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.click()
    field.typeKey("a", modifierFlags: .command)
    pasteText(text, into: field)
  }

  private func waitForDisappearance(_ element: XCUIElement) {
    let disappeared = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"),
      object: element,
    )
    wait(for: [disappeared], timeout: 5)
  }

  func testFileMenuClearRequiresConfirmationInImageWindow() throws {
    _ = try launchWithRecentImages()
    let image = app.buttons["sample_1280×853.png"]
    XCTAssertTrue(image.waitForExistence(timeout: 5))
    image.click()
    XCTAssertTrue(app.images["sample_1280×853.png"].waitForExistence(timeout: 10))
    let fileMenu = app.menuBars.menuBarItems.element(boundBy: 2)
    fileMenu.click()
    fileMenu.menuItems["Open Recent"].hover()
    let clearMenu = app.menuItems["Clear Menu"]
    XCTAssertTrue(clearMenu.waitForExistence(timeout: 5))
    clearMenu.click()
    let cancel = app.windows.buttons["Cancel"].firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: 5))
    cancel.click()
    XCTAssertTrue(app.images["sample_1280×853.png"].exists)
  }

  func testChineseRecentImagesAndSettings() throws {
    if let languages = app.launchArguments.firstIndex(of: "-AppleLanguages") {
      app.launchArguments[languages + 1] = "(zh-Hans)"
    }
    if let locale = app.launchArguments.firstIndex(of: "-AppleLocale") {
      app.launchArguments[locale + 1] = "zh_CN"
    }
    _ = try launchWithRecentImages()
    let clear = app.buttons["清空最近图片记录"]
    XCTAssertTrue(clear.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertTrue(app.buttons["清理失效图片"].exists)
    keepScreenshot(clear, name: "Recent images actions in Simplified Chinese")
    clear.click()
    let cancel = app.windows.buttons["取消"].firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: 5))
    keepScreenshot(cancel, name: "Clear confirmation in Simplified Chinese")
    cancel.click()
    app.windows.buttons["设置"].firstMatch.click()
    XCTAssertTrue(app.staticTexts["外观："].waitForExistence(timeout: 5))
    keepScreenshot(app.staticTexts["外观："], name: "General settings in Simplified Chinese")
  }

  private func launchWithRecentImages() throws -> [URL] {
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appending(path: "Images")
    let originals = [
      directory.appending(path: "sample_1280×853.png"),
      directory.appending(path: "sample_1280×853.jpeg"),
    ]
    let testDirectory = try XCTUnwrap(testDirectory)
    let paths = originals.map(\.path) + [
      testDirectory.appending(path: "missing.png").path,
      "/Volumes/imaxe-offline-\(UUID().uuidString)/image.png",
    ]
    let data = try JSONEncoder().encode(paths)
    app.terminate()
    app.launchEnvironment["IMAXE_UI_TEST_RECENT_IMAGES"] = String(data: data, encoding: .utf8)
    app.launch()
    app.activate()
    showHomeWindow()
    return originals
  }

  private func showHomeWindow() {
    if !app.windows.firstMatch.waitForExistence(timeout: 3) {
      app.typeKey("n", modifierFlags: .command)
    }
    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    keepScreenshot(app.windows.firstMatch, name: "Home window after launch")
  }

  func testWindowAndFileMenuAreAvailable() {
    if !app.windows.firstMatch.waitForExistence(timeout: 3) {
      app.typeKey("n", modifierFlags: .command)
    }
    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))

    let fileMenu = app.menuBars.menuBarItems.element(boundBy: 2)
    XCTAssertTrue(fileMenu.waitForExistence(timeout: 5))
    fileMenu.click()

    let openImageCommand = fileMenu.menus.firstMatch.menuItems.element(boundBy: 2)
    XCTAssertTrue(openImageCommand.waitForExistence(timeout: 2))
    app.typeKey(.escape, modifierFlags: [])
  }

  func testRevealInFinderCommandIsPresent() {
    let fileMenu = app.menuBars.menuBarItems.element(boundBy: 2)
    XCTAssertTrue(fileMenu.waitForExistence(timeout: 5))
    fileMenu.click()

    let revealInFinderCommand = fileMenu.menus.firstMatch.menuItems.element(boundBy: 6)
    XCTAssertTrue(revealInFinderCommand.waitForExistence(timeout: 2))
    app.typeKey(.escape, modifierFlags: [])
  }

  func testColdProcessLaunchPerformance() {
    let options = XCTMeasureOptions()
    options.iterationCount = 3
    options.invocationOptions = [.manuallyStart, .manuallyStop]
    // Observe the launch() call's wall time consistently across supported systems.
    // This includes UI automation overhead, not the system's first-frame metric.
    print(
      "IMAXE_COLD_LAUNCH_METRIC app_launch_call_wall_time;",
      "iterations=3; excludes_termination=true",
    )
    measure(metrics: [XCTClockMetric()], options: options) {
      app.terminate()
      XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
      startMeasuring()
      app.launch()
      stopMeasuring()
      XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
      XCTAssertTrue(app.menuBars.firstMatch.waitForExistence(timeout: 5))
    }
  }

  func testVisibleImageZoomAndNavigation() throws {
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appending(
        path: "Images",
        directoryHint: .isDirectory,
      )
    if !app.windows.firstMatch.exists {
      app.typeKey("n", modifierFlags: .command)
    }
    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    app.typeKey("o", modifierFlags: .command)
    XCTAssertTrue(app.buttons["CancelButton"].waitForExistence(timeout: 10))
    app.typeKey("g", modifierFlags: [.command, .shift])
    let pathField = app.textFields["PathTextField"]
    XCTAssertTrue(pathField.waitForExistence(timeout: 5))
    pathField.click()
    pathField.typeKey("a", modifierFlags: .command)
    let path = directory.appending(path: "sample_1280×853.jpeg").path
    pasteText(path, into: pathField)
    XCTAssertEqual(pathField.value as? String, path)
    let pathSuggestion = app.sheets["GoToWindow"].tables.cells
      .containing(.other, identifier: path).firstMatch
    XCTAssertTrue(pathSuggestion.waitForExistence(timeout: 5))
    pathSuggestion.doubleClick()
    let openButton = app.buttons["OKButton"]
    let enabled = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "enabled == true"),
      object: openButton,
    )
    wait(for: [enabled], timeout: 5)
    let start = ContinuousClock.now
    openButton.click()
    let canvas = app.images["sample_1280×853.jpeg"]
    XCTAssertTrue(canvas.waitForExistence(timeout: 10))
    let openedAt = ContinuousClock.now
    app.typeKey("1", modifierFlags: .command)
    let actualSizeFrame = canvas.frame
    keepScreenshot(canvas, name: "Image at 100 percent")
    for _ in 0 ..< 6 {
      app.typeKey("+", modifierFlags: .command)
    }
    XCTAssertTrue(canvas.exists)
    XCTAssertGreaterThan(canvas.frame.width, actualSizeFrame.width)
    keepScreenshot(canvas, name: "Image after six zoom increments")
    app.typeKey("0", modifierFlags: .command)
    app.typeKey(.rightArrow, modifierFlags: [])
    XCTAssertTrue(app.images["sample_1280×853.jpg"].waitForExistence(timeout: 10))
    app.typeKey(.leftArrow, modifierFlags: [])
    XCTAssertTrue(canvas.waitForExistence(timeout: 10))
    let options = XCTMeasureOptions()
    options.iterationCount = 1
    measure(metrics: [XCTMemoryMetric(application: app), XCTClockMetric()], options: options) {
      for _ in 0 ..< 10 {
        app.activate()
        canvas.click()
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(app.images["sample_1280×853.jpg"].waitForExistence(timeout: 10))
        app.images["sample_1280×853.jpg"].click()
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
      }
      XCTAssertTrue(canvas.waitForExistence(timeout: 10))
    }
    XCTAssertTrue(canvas.waitForExistence(timeout: 10))
    keepScreenshot(canvas, name: "Image after navigation returns to first file")
    XCTAssertEqual(app.alerts.count, 0)
    let elapsed = start.duration(to: openedAt).components
    let firstAccessibleMilliseconds = Double(elapsed.seconds) * 1000
      + Double(elapsed.attoseconds) / 1e15
    let record: [String: Any] = [
      "first_accessible_ms": firstAccessibleMilliseconds,
    ]
    let data = try JSONSerialization.data(withJSONObject: record, options: .sortedKeys)
    let line = try XCTUnwrap(String(data: data, encoding: .utf8))
    print("IMAXE_VISIBLE_PERF \(line)")
  }

  private func pasteText(_ text: String, into field: XCUIElement) {
    let pasteboard = NSPasteboard.general
    let savedItems = (pasteboard.pasteboardItems ?? []).map { item in
      let copy = NSPasteboardItem()
      for type in item.types {
        if let data = item.data(forType: type) {
          copy.setData(data, forType: type)
        }
      }
      return copy
    }
    pasteboard.clearContents()
    let didWrite = pasteboard.setString(text, forType: .string)
    let changeCount = pasteboard.changeCount
    defer {
      if pasteboard.changeCount == changeCount {
        pasteboard.clearContents()
        if !savedItems.isEmpty {
          pasteboard.writeObjects(savedItems)
        }
      }
    }
    XCTAssertTrue(didWrite)
    field.typeKey("v", modifierFlags: .command)
    let entered = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", text),
      object: field,
    )
    wait(for: [entered], timeout: 5)
  }

  private func keepScreenshot(_ element: XCUIElement, name: String) {
    XCTAssertTrue(element.exists)
    let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
