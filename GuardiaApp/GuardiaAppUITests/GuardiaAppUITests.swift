import XCTest

final class GuardiaAppUITests: XCTestCase {
    @MainActor
    func testLaunchKeepsPrivateDataLocked() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Unlock Guardia"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.buttons["Trips"].exists)
    }
}
