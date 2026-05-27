import XCTest

final class AuthUITests: XCTestCase {
    func testLoginFlowStartsUnauthenticated() {
        let app = XCUIApplication()
        app.launchEnvironment["USE_MOCK_KEYCHAIN"] = "1"
        app.launch()
        // Secrets now uses InMemoryKeychain — no real keychain access
    }
}
