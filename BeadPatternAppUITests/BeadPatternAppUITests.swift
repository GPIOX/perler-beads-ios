import XCTest

final class BeadPatternAppUITests: XCTestCase {
    @MainActor
    func testDocumentBrowserLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    @MainActor
    func testCreateDocumentOpensWorkspace() throws {
        let app = XCUIApplication()
        app.launch()

        let createButton = app.buttons["创建文稿"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()

        XCTAssertFalse(app.alerts["无法导入文稿"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["导入"].waitForExistence(timeout: 5))
    }
}
