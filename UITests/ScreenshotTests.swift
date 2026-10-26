import XCTest

/// Läuft im CI im Simulator und legt Screenshots aller Hauptseiten als Anhänge ab
/// (hell, dunkel und mit großer Schrift). So lässt sich das Design ohne Mac prüfen.
final class ScreenshotTests: XCTestCase {
    private let tabs = ["Planer", "Training", "Ernährung", "Gesundheit"]

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testLightMode() {
        captureAllScreens(suffix: "hell", extraArguments: ["-forceLight"])
    }

    @MainActor
    func testDarkMode() {
        captureAllScreens(suffix: "dunkel", extraArguments: ["-forceDark"])
    }

    @MainActor
    func testLargeText() {
        let app = launch(extraArguments: [
            "-forceLight",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL",
        ])
        snap(app, "01-heute-grosse-schrift")
        openSystemCheck(in: app)
        snap(app, "07-systemcheck-grosse-schrift")
    }

    // MARK: - Hilfen

    @MainActor
    private func captureAllScreens(suffix: String, extraArguments: [String]) {
        let app = launch(extraArguments: extraArguments)
        snap(app, "01-heute-\(suffix)")

        for (index, title) in tabs.enumerated() {
            tapTab(title, in: app)
            snap(app, "0\(index + 2)-\(title.lowercased())-\(suffix)")
        }

        tapTab("Heute", in: app)

        let search = app.buttons["today.search"]
        if search.waitForExistence(timeout: 3) {
            search.tap()
            snap(app, "06-suche-\(suffix)")
            tapIfPresent(app.buttons["search.done"])
        }

        openSystemCheck(in: app)
        snap(app, "07-systemcheck-\(suffix)")

        tapIfPresent(app.navigationBars["Systemcheck"].buttons.element(boundBy: 0))
        let settings = app.buttons["today.settings"]
        if settings.waitForExistence(timeout: 3) {
            settings.tap()
            snap(app, "08-einstellungen-\(suffix)")
        }
    }

    @MainActor
    private func tapIfPresent(_ element: XCUIElement) {
        if element.waitForExistence(timeout: 3) {
            element.tap()
        }
    }

    @MainActor
    private func launch(extraArguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"] + extraArguments
        app.launch()
        return app
    }

    @MainActor
    private func tapTab(_ title: String, in app: XCUIApplication) {
        let tabButton = app.tabBars.buttons[title]
        if tabButton.waitForExistence(timeout: 3) {
            tabButton.tap()
        } else {
            app.buttons[title].firstMatch.tap()
        }
    }

    @MainActor
    private func openSystemCheck(in app: XCUIApplication) {
        let button = app.buttons["today.systemcheck"]
        if button.waitForExistence(timeout: 5) {
            button.tap()
        }
        _ = app.navigationBars["Systemcheck"].waitForExistence(timeout: 3)
    }

    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        // Kurz warten, bis Animationen fertig sind.
        _ = app.wait(for: .runningForeground, timeout: 2)
        Thread.sleep(forTimeInterval: 0.8)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
