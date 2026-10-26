import XCTest

/// Läuft im CI im Simulator und legt Screenshots der wichtigsten Seiten als Anhänge ab
/// (hell, dunkel, große Schrift, Onboarding). Die App startet mit Beispieldaten
/// (`-uiTesting`), damit die Screenshots echte Inhalte zeigen.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testLightMode() {
        captureMainFlow(suffix: "hell", extraArguments: ["-forceLight"])
    }

    @MainActor
    func testDarkMode() {
        captureMainFlow(suffix: "dunkel", extraArguments: ["-forceDark"])
    }

    @MainActor
    func testLargeText() {
        let app = launch(extraArguments: [
            "-forceLight",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL",
        ])
        snap(app, "01-heute-grosse-schrift")
        openTask(named: "Steuerunterlagen sortieren", in: app)
        snap(app, "07-editor-grosse-schrift")
        tapIfPresent(app.buttons["editor.done"])
        tapTab("Gesundheit", in: app)
        snap(app, "11-gesundheit-grosse-schrift")
    }

    /// Prüft im Simulator, was unter Linux nicht geht: Migration, Medikamenten-Aktionen, Sicherung.
    @MainActor
    func testSelfTest() {
        let app = launch(extraArguments: ["-forceLight", "-selfTest"])
        let summary = app.staticTexts["selftest.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 20))
        let finished = NSPredicate(format: "label BEGINSWITH 'Alle' OR label BEGINSWITH 'Fehlgeschlagen'")
        expectation(for: finished, evaluatedWith: summary)
        waitForExpectations(timeout: 30)
        snap(app, "15-selbsttest")
        XCTAssertTrue(summary.label.hasPrefix("Alle"), summary.label)
    }

    @MainActor
    func testOnboarding() {
        let app = launch(extraArguments: ["-forceLight", "-showOnboarding"])
        for page in 1...3 {
            snap(app, "10-onboarding-\(page)")
            tapIfPresent(app.buttons["onboarding.next"])
        }
    }

    // MARK: - Ablauf

    @MainActor
    private func captureMainFlow(suffix: String, extraArguments: [String]) {
        let app = launch(extraArguments: extraArguments)
        snap(app, "01-heute-\(suffix)")

        // Planer: Übersicht, Liste „Heute“, Agenda, Woche
        tapTab("Planer", in: app)
        snap(app, "02-planer-\(suffix)")
        if tapIfPresent(app.buttons["smartlist.today"]) {
            snap(app, "03-liste-heute-\(suffix)")
            tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
        }
        if tapIfPresent(app.buttons["Agenda"].firstMatch) {
            snap(app, "04-agenda-\(suffix)")
        }
        if tapIfPresent(app.buttons["Woche"].firstMatch) {
            snap(app, "05-woche-\(suffix)")
        }
        tapIfPresent(app.buttons["Aufgaben"].firstMatch)

        // Schnellerfassung mit erkanntem Datum, Uhrzeit, Priorität und Liste
        tapTab("Heute", in: app)
        if tapIfPresent(app.buttons["today.quickadd"]) {
            let field = app.textFields["quickadd.field"]
            if field.waitForExistence(timeout: 3) {
                field.typeText("morgen 10 uhr zahnarzt !! #Arbeit")
            }
            snap(app, "06-schnellerfassung-\(suffix)")
            tapIfPresent(app.buttons["quickadd.close"])
        }

        // Editor
        openTask(named: "Steuerunterlagen sortieren", in: app)
        snap(app, "07-editor-\(suffix)")
        tapIfPresent(app.buttons["editor.done"])

        // Suche
        if tapIfPresent(app.buttons["today.search"]) {
            let field = app.searchFields.firstMatch
            if field.waitForExistence(timeout: 3) {
                field.tap()
                field.typeText("Zahn")
            }
            snap(app, "08-suche-\(suffix)")
            dismissSheet(in: app, doneIdentifier: "search.done")
        }

        // Einstellungen
        if tapIfPresent(app.buttons["today.settings"]) {
            snap(app, "09-einstellungen-\(suffix)")
            tapIfPresent(app.buttons["settings.done"])
        }

        // Gesundheit: Übersicht, Medikament, Editor, neues Medikament
        tapTab("Gesundheit", in: app)
        snap(app, "11-gesundheit-\(suffix)")
        let dao = app.buttons["medication.DAO-Enzym"]
        if scrollTo(dao, in: app), tapIfPresent(dao) {
            snap(app, "12-medikament-\(suffix)")
            if tapIfPresent(app.buttons["medDetail.edit"]) {
                snap(app, "13-medikament-bearbeiten-\(suffix)")
                tapIfPresent(app.buttons["Abbrechen"].firstMatch)
            }
            tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
        }
        if tapIfPresent(app.buttons["health.add"]) {
            let name = app.textFields["medEditor.name"]
            if name.waitForExistence(timeout: 3) {
                name.tap()
                name.typeText("Magnesium")
            }
            snap(app, "14-neues-medikament-\(suffix)")
            tapIfPresent(app.buttons["Abbrechen"].firstMatch)
        }
    }

    // MARK: - Hilfen

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
            tapIfPresent(app.buttons[title].firstMatch)
        }
    }

    @MainActor
    private func openTask(named title: String, in app: XCUIApplication) {
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        if !tapIfPresent(row) {
            tapIfPresent(app.staticTexts[title].firstMatch)
        }
        _ = app.textFields["editor.title"].waitForExistence(timeout: 3)
    }

    /// Schließt ein Sheet: zuerst über den „Fertig“-Knopf, sonst Suche abbrechen und
    /// erneut versuchen, zuletzt per Wischen nach unten.
    @MainActor
    private func dismissSheet(in app: XCUIApplication, doneIdentifier: String) {
        if tapIfPresent(app.buttons[doneIdentifier]) { return }
        for label in ["Abbrechen", "Cancel", "Schließen", "Close"] {
            tapIfPresent(app.buttons[label].firstMatch, timeout: 1)
        }
        if tapIfPresent(app.buttons[doneIdentifier], timeout: 2) { return }
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
            .press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
    }

    /// Wischt nach oben, bis das Element sichtbar und antippbar ist.
    @MainActor
    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 5) -> Bool {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    @MainActor
    @discardableResult
    private func tapIfPresent(_ element: XCUIElement, timeout: TimeInterval = 4) -> Bool {
        guard element.waitForExistence(timeout: timeout), element.isHittable else { return false }
        element.tap()
        return true
    }

    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        // Kurz warten, bis Animationen fertig sind.
        Thread.sleep(forTimeInterval: 1.0)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
