// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import AppKit
import XCTest

@MainActor
final class ImaxeUITests: XCTestCase {
  var app: XCUIApplication!

  override func setUp() async throws {
    try await super.setUp()

    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["--disable-updates-for-testing"]
    app.terminate()
    app.launch()
    app.activate()
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
    app.terminate()
    let options = XCTMeasureOptions()
    options.iterationCount = 3
    measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
      app.launch()
    }
  }

  func testVisibleImageZoomAndNavigation() throws {
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appending(
        path: "Build/UITestFixtures",
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
    let path = directory.appending(path: "a.png").path
    pastePath(path, into: pathField)
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
    let canvas = app.images["a.png"]
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
    XCTAssertTrue(app.images["b.png"].waitForExistence(timeout: 10))
    app.typeKey(.leftArrow, modifierFlags: [])
    XCTAssertTrue(canvas.waitForExistence(timeout: 10))
    let options = XCTMeasureOptions()
    options.iterationCount = 1
    measure(metrics: [XCTMemoryMetric(application: app), XCTClockMetric()], options: options) {
      for _ in 0 ..< 10 {
        app.typeKey(.rightArrow, modifierFlags: [])
      }
      for _ in 0 ..< 10 {
        app.typeKey(.leftArrow, modifierFlags: [])
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

  private func pastePath(_ path: String, into field: XCUIElement) {
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
    let didWrite = pasteboard.setString(path, forType: .string)
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
      predicate: NSPredicate(format: "value == %@", path),
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
