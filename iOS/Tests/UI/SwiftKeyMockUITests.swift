import XCTest

final class SwiftKeyMockUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func launch(reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + (reset ? ["--reset-mock-state"] : [])
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["mock.mode.banner"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }
    @MainActor private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    @MainActor private func enterName(_ name: String, in app: XCUIApplication) {
        let field = app.textFields["mock.testName"]
        reveal(field, in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(name + "\n")
    }
    @MainActor private func beginRegistration(_ name: String, in app: XCUIApplication) {
        enterName(name, in: app)
        let create = app.buttons["mock.register"]
        reveal(create, in: app); create.tap()
        XCTAssertTrue(app.buttons["mock.approval.approve"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["mock.mode.banner"].exists)
    }
    @MainActor private func approveAndVerify(in app: XCUIApplication) {
        app.buttons["mock.approval.approve"].tap()
        let verify = app.buttons["mock.verification.succeed"]
        XCTAssertTrue(verify.waitForExistence(timeout: 5))
        reveal(verify, in: app)
        capture("explicit-simulated-verification", in: app)
        verify.tap()
        XCTAssertTrue(app.staticTexts["mock.result.title"].waitForExistence(timeout: 8))
    }
    @MainActor private func firstCredential(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "mock.credential.row.")).firstMatch
    }
    @MainActor private func openCredential(in app: XCUIApplication) {
        let row = firstCredential(in: app); reveal(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.buttons["mock.detail.signIn"].waitForExistence(timeout: 5))
    }

    @MainActor func testCreateSignInAndDeleteUsesRealLocalMockResponse() throws {
        let app = launch()
        capture("01-empty-mock-workspace", in: app)
        beginRegistration("UI Test Phone", in: app)
        capture("02-registration-review", in: app)
        approveAndVerify(in: app)
        XCTAssertEqual(app.staticTexts["mock.result.title"].label, "Passkey created")
        capture("03-passkey-created", in: app)
        openCredential(in: app)
        XCTAssertEqual(app.staticTexts["mock.detail.name"].label, "UI Test Phone")
        capture("04-public-credential-details", in: app)
        app.buttons["mock.detail.signIn"].tap()
        XCTAssertTrue(app.buttons["mock.approval.approve"].waitForExistence(timeout: 5))
        capture("05-sign-in-review", in: app)
        approveAndVerify(in: app)
        XCTAssertEqual(app.staticTexts["mock.result.title"].label, "Signature verified")
        capture("06-signature-verified", in: app)
        openCredential(in: app)
        let delete = app.buttons["mock.detail.delete"]; reveal(delete, in: app); delete.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        // iOS 26 exposes the destructive action as nested button wrappers.
        // Both represent the same action; use its stable ID and first wrapper.
        app.alerts.firstMatch.buttons.matching(identifier: "mock.delete.confirm").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["mock.result.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["mock.result.title"].label, "Test passkey deleted")
        XCTAssertFalse(firstCredential(in: app).exists)
        capture("07-test-passkey-deleted", in: app)
    }

    @MainActor func testCancelBeforeApprovalAndDuringVerificationNeverCreatesCredential() throws {
        let app = launch()
        beginRegistration("Cancelled Request", in: app)
        app.buttons["mock.approval.cancel"].tap()
        XCTAssertTrue(app.staticTexts["mock.result.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["mock.result.title"].label, "Request cancelled")
        XCTAssertFalse(firstCredential(in: app).exists)
        capture("08-request-cancelled-no-credential", in: app)
        // The same name remains editable, but a new request gets a fresh challenge.
        let create = app.buttons["mock.register"]; reveal(create, in: app); create.tap()
        XCTAssertTrue(app.buttons["mock.approval.approve"].waitForExistence(timeout: 5))
        app.buttons["mock.approval.approve"].tap()
        XCTAssertTrue(app.buttons["mock.verification.succeed"].waitForExistence(timeout: 5))
        app.buttons["mock.approval.cancel"].tap()
        XCTAssertTrue(app.staticTexts["mock.result.title"].waitForExistence(timeout: 5))
        XCTAssertFalse(firstCredential(in: app).exists)
    }

    @MainActor func testSimulatedVerificationFailureIsVisibleAndDoesNotCreateCredential() throws {
        let app = launch()
        beginRegistration("Failed Verification", in: app)
        app.buttons["mock.approval.approve"].tap()
        let fail = app.buttons["mock.verification.fail"]
        XCTAssertTrue(fail.waitForExistence(timeout: 5)); reveal(fail, in: app); fail.tap()
        XCTAssertTrue(app.staticTexts["mock.result.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["mock.result.title"].label, "Verification not completed")
        XCTAssertFalse(firstCredential(in: app).exists)
        capture("09-simulated-failure-no-credential", in: app)
    }

    @MainActor func testCredentialPersistsAcrossRestartAndCanSignIn() throws {
        let app = launch()
        beginRegistration("Persistent Test Phone", in: app)
        approveAndVerify(in: app)
        XCTAssertEqual(app.staticTexts["mock.result.title"].label, "Passkey created")
        app.terminate()
        let relaunched = launch(reset: false)
        openCredential(in: relaunched)
        XCTAssertEqual(relaunched.staticTexts["mock.detail.name"].label, "Persistent Test Phone")
        relaunched.buttons["mock.detail.signIn"].tap()
        XCTAssertTrue(relaunched.buttons["mock.approval.approve"].waitForExistence(timeout: 5))
        approveAndVerify(in: relaunched)
        XCTAssertEqual(relaunched.staticTexts["mock.result.title"].label, "Signature verified")
        capture("10-restarted-credential-signature-verified", in: relaunched)
    }
}
