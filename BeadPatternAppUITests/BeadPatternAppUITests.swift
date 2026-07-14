import XCTest

final class BeadPatternAppUITests: XCTestCase {
    @MainActor
    func testDocumentBrowserLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }
}
