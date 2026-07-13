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
}
