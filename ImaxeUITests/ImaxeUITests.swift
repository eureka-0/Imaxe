import XCTest

@MainActor
final class ImaxeUITests: XCTestCase {
  var app: XCUIApplication!

  override func setUp() async throws {
    try await super.setUp()

    continueAfterFailure = false
    app = XCUIApplication()
    app.terminate()
    app.launch()
    app.activate()
  }

  func testWindowAndFileMenuAreAvailable() {
    if !app.windows.firstMatch.waitForExistence(timeout: 3) {
      app.typeKey("n", modifierFlags: .command)
    }
    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))

    let fileMenu = app.menuBars.menuBarItems["File"]
    XCTAssertTrue(fileMenu.waitForExistence(timeout: 5))
    fileMenu.click()

    XCTAssertTrue(app.menuItems["Open Image..."].waitForExistence(timeout: 2))
    app.typeKey(.escape, modifierFlags: [])
  }

  func testRevealInFinderCommandIsPresent() {
    let fileMenu = app.menuBars.menuBarItems["File"]
    fileMenu.click()

    XCTAssertTrue(app.menuItems["Reveal in Finder"].waitForExistence(timeout: 2))
    app.typeKey(.escape, modifierFlags: [])
  }
}
