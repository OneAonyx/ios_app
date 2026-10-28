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
        let checkIn = app.buttons["health.checkin"]
        if scrollTo(checkIn, in: app, attempts: 8) {
            snap(app, "41-einblicke-grosse-schrift")
            if tapIfPresent(checkIn) {
                snap(app, "42-checkin-grosse-schrift")
                tapIfPresent(app.buttons["Fertig"].firstMatch)
            }
        }
        tapTab("Training", in: app)
        snap(app, "16-training-grosse-schrift")
        tapTab("Ernährung", in: app)
        snap(app, "26-ernaehrung-grosse-schrift")
    }

    /// Ernährung: Tab, Mahlzeit, Auswahl, Lexikon, Lebensmittel, Zutaten, Einkauf, Rezepte, Plan, Muster, Beschwerden.
    @MainActor
    func testNutrition() {
        let app = launch(extraArguments: ["-forceLight"])
        tapTab("Ernährung", in: app)
        snap(app, "26-ernaehrung")

        // Mahlzeit eintragen: Editor mit DAO-Nachfrage, Auswahl, Lebensmittel übernehmen.
        if tapIfPresent(app.buttons["nutrition.add"]) {
            snap(app, "27-mahlzeit")
            if tapIfPresent(app.buttons["mealEditor.addFood"]) {
                snap(app, "28-auswahl")
                if !tapIfPresent(app.buttons.matching(identifier: "foodPicker.haehnchenbrust").firstMatch, timeout: 2) {
                    closeSheets(in: app)
                }
            }
            if tapIfPresent(app.buttons["mealEditor.save"], timeout: 2) == false {
                closeSheets(in: app)
            }
        }
        closeSheets(in: app)

        let links: [(String, String)] = [
            ("nutrition.ingredients", "32-zutaten"),
            ("nutrition.shopping", "33-einkauf"),
            ("nutrition.plan", "36-wochenplan"),
            ("nutrition.patterns", "37-muster"),
            ("nutrition.settings", "38-ziele"),
        ]
        // Lexikon und ein Lebensmittel.
        let lexicon = app.buttons["nutrition.lexicon"]
        if scrollTo(lexicon, in: app), tapIfPresent(lexicon) {
            snap(app, "30-lexikon")
            // Avocado steht weit oben und ist als „Meiden“ markiert.
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Avocado'")).firstMatch
            if tapIfPresent(row) {
                snap(app, "31-lebensmittel")
                tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
            }
            tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
        }
        // Rezepte und ein Rezept.
        let recipes = app.buttons["nutrition.recipes"]
        if scrollTo(recipes, in: app), tapIfPresent(recipes) {
            snap(app, "34-rezepte")
            let first = app.cells.element(boundBy: 1)
            if tapIfPresent(first) {
                snap(app, "35-rezept")
                tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
            }
            tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
        }
        for (identifier, name) in links {
            let link = app.buttons[identifier]
            if scrollTo(link, in: app), tapIfPresent(link) {
                snap(app, name)
                tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
            }
        }

        // Beschwerden eintragen.
        let symptom = app.buttons["nutrition.symptom.add"]
        for _ in 0..<4 where !(symptom.exists && symptom.isHittable) { app.swipeDown() }
        if scrollTo(symptom, in: app), tapIfPresent(symptom) {
            tapIfPresent(app.buttons["symptom.headache"], timeout: 2)
            snap(app, "39-beschwerden")
            closeSheets(in: app)
        }
    }

    /// Schließt offene Blätter über den Knopf „Abbrechen“ oder „Schließen“, der gerade antippbar ist.
    @MainActor
    private func closeSheets(in app: XCUIApplication) {
        for _ in 0..<3 {
            let cancel = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Abbrechen", "Schließen"))
            guard cancel.count > 0, tapHittable(cancel) else { return }
            Thread.sleep(forTimeInterval: 0.8)
        }
    }

    /// Einblicke: Gesundheit-Karte, Check-in, Befinden, Wochenrückblick, Arztbericht, Claude.
    @MainActor
    func testInsights() {
        let app = launch(extraArguments: ["-forceLight"])
        tapTab("Gesundheit", in: app)
        let checkIn = app.buttons["health.checkin"]
        if scrollTo(checkIn, in: app, attempts: 8) {
            snap(app, "41-einblicke")
        }
        if tapIfPresent(checkIn) {
            tapIfPresent(app.buttons["checkin.mood.4"], timeout: 2)
            snap(app, "42-checkin")
            tapIfPresent(app.buttons["Fertig"].firstMatch)
        }
        for (identifier, name) in [("health.mood", "43-befinden"), ("health.review", "44-rueckblick")] {
            let link = app.buttons[identifier]
            if scrollTo(link, in: app), tapIfPresent(link) {
                snap(app, name)
                tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
            }
        }
        let report = app.buttons["health.report"]
        if scrollTo(report, in: app), tapIfPresent(report) {
            snap(app, "45-arztbericht")
            let build = app.buttons["report.build"]
            if scrollTo(build, in: app), tapIfPresent(build) {
                Thread.sleep(forTimeInterval: 1.5)
                snap(app, "46-arztbericht-pdf")
                tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
            }
            tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
        }
        let claude = app.buttons["health.claude"]
        guard scrollTo(claude, in: app), tapIfPresent(claude) else { return }
        snap(app, "47-claude")
        let food = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Haferdrink")).firstMatch
        if scrollTo(food, in: app), tapIfPresent(food) {
            snap(app, "48-claude-lebensmittel")
            if tapIfPresent(app.buttons["claude.apply"], timeout: 2) {
                snap(app, "49-claude-uebernommen")
            }
            tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
        }
        let review = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Rückblick KW")).firstMatch
        if scrollTo(review, in: app), tapIfPresent(review) {
            snap(app, "50-claude-rueckblick")
            tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
        }
        for _ in 0..<3 { app.swipeDown() }
        if tapIfPresent(app.buttons["claude.task.trainingPlan"]) {
            snap(app, "51-claude-anfrage")
            let preview = app.buttons["Ganze Anfrage ansehen"].firstMatch
            if scrollTo(preview, in: app), tapIfPresent(preview) {
                snap(app, "52-claude-vorschau")
            }
        }
    }

    /// Tippt das erste antippbare Element einer Abfrage an.
    @MainActor
    @discardableResult
    private func tapHittable(_ query: XCUIElementQuery) -> Bool {
        for index in 0..<query.count {
            let element = query.element(boundBy: index)
            if element.exists, element.isHittable {
                element.tap()
                return true
            }
        }
        return false
    }

    /// Training: Tab, Plan, Statistik, Übungen, Körper, Einheit mit Pause, Satz, Zusammenfassung.
    @MainActor
    func testTraining() {
        let app = launch(extraArguments: ["-forceLight"])
        tapTab("Training", in: app)
        snap(app, "16-training")

        for (identifier, name) in [("training.plan", "17-plan"), ("training.stats", "18-statistik"), ("training.library", "19-uebungen"), ("training.body", "20-koerper")] {
            let link = app.buttons[identifier]
            if scrollTo(link, in: app), tapIfPresent(link) {
                snap(app, name)
                tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
            }
        }

        // Fortschritt: Tempo je Übung, Körpergewicht, Fotos mit Vergleich.
        let progress = app.buttons["training.progress"]
        if scrollTo(progress, in: app), tapIfPresent(progress) {
            snap(app, "61-fortschritt")
            let photos = app.buttons["progress.photos"]
            if scrollTo(photos, in: app), tapIfPresent(photos) {
                snap(app, "62-fotos")
                if tapIfPresent(app.buttons["photos.compare"]) {
                    snap(app, "63-fotovergleich")
                    dismissSheet(in: app, doneIdentifier: "compare.done")
                }
                tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
            }
            tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
        }

        // Nach oben und Einheit starten.
        let start = app.buttons["training.start"]
        for _ in 0..<4 where !(start.exists && start.isHittable) { app.swipeDown() }
        guard tapIfPresent(start) else { return }
        snap(app, "21-einheit")
        let checks = app.buttons.matching(identifier: "workout.set.check")
        if tapIfPresent(checks.element(boundBy: 0)) {
            snap(app, "22-pause")
        }
        tapIfPresent(app.buttons["workout.rest.skip"], timeout: 2)
        let edits = app.buttons.matching(identifier: "workout.set.edit")
        if tapIfPresent(edits.element(boundBy: 1)) {
            snap(app, "23-satz")
            tapIfPresent(app.buttons["setEditor.complete"])
        }
        tapIfPresent(app.buttons["workout.rest.skip"], timeout: 2)
        if tapIfPresent(app.buttons["workout.finish"]) {
            tapIfPresent(app.buttons["Beenden und speichern"].firstMatch)
            snap(app, "24-zusammenfassung")
            tapIfPresent(app.buttons["summary.done"])
        }
        tapTab("Heute", in: app)
        snap(app, "25-heute-nach-training")

        // Muskel-Karte: erst nach einer Einheit sichtbar.
        tapTab("Training", in: app)
        let stats = app.buttons["training.stats"]
        if scrollTo(stats, in: app), tapIfPresent(stats) {
            let map = app.descendants(matching: .any)["muscleMap.front"]
            if map.waitForExistence(timeout: 3) {
                XCTAssertTrue(map.label.contains("Brust") || map.label.contains("Bizeps"), map.label)
                snap(app, "64-muskelkarte")
            }
            tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
        }
    }

    /// Phase 10: aufgeräumte Startseite, anpassen, Funktions-Verzeichnis, Sprung aus der Suche, Einstellungen.
    @MainActor
    func testClarity() {
        let app = launch(extraArguments: ["-forceLight"])
        XCTAssertTrue(app.buttons["quick.meal"].waitForExistence(timeout: 5), "Schnell erfassen fehlt")
        snap(app, "80-heute-oben")
        app.swipeUp()
        snap(app, "81-heute-mitte")

        let customize = app.buttons["today.customize"]
        if scrollTo(customize, in: app, attempts: 8), tapIfPresent(customize) {
            XCTAssertTrue(app.switches["layout.nutrition"].waitForExistence(timeout: 3))
            snap(app, "82-startseite-anpassen")
            dismissSheet(in: app, doneIdentifier: "layout.done")
        }

        // Suche ohne Begriff: Verzeichnis aller Funktionen.
        for _ in 0..<6 where !app.buttons["today.search"].isHittable { app.swipeDown() }
        if tapIfPresent(app.buttons["today.search"]) {
            XCTAssertTrue(app.buttons["feature.doctorReport"].waitForExistence(timeout: 3) || app.buttons["feature.quickAdd"].exists)
            snap(app, "83-alle-funktionen")
            let field = app.searchFields.firstMatch
            if field.waitForExistence(timeout: 3) {
                field.tap()
                field.typeText("arzt")
            }
            let report = app.buttons["feature.doctorReport"]
            XCTAssertTrue(report.waitForExistence(timeout: 3), "Arztbericht nicht gefunden")
            snap(app, "84-suche-funktion")
            report.tap()
            // Öffnet im Tab „Gesundheit“ direkt den Bericht.
            XCTAssertTrue(app.navigationBars["Arztbericht"].waitForExistence(timeout: 5), "Bericht nicht geöffnet")
            snap(app, "85-sprung-arztbericht")
        }

        // Einstellungen: Unterseiten.
        tapTab("Heute", in: app)
        if tapIfPresent(app.buttons["today.settings"]) {
            XCTAssertTrue(app.buttons["settings.page.data"].waitForExistence(timeout: 3))
            snap(app, "86-einstellungen")
            tapIfPresent(app.buttons["settings.done"])
        }
    }

    /// Phase 9: Import aus Erinnerungen, Sicherung in einen zweiten Ordner, große Schrift.
    @MainActor
    func testImportAndBackup() {
        for (suffix, arguments) in [
            ("hell", ["-forceLight"]),
            ("gross", ["-forceLight", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]),
        ] {
            let app = launch(extraArguments: arguments)
            tapTab("Planer", in: app)
            let importLink = app.buttons["lists.importReminders"]
            if scrollTo(importLink, in: app, attempts: 6), tapIfPresent(importLink) {
                // Kein Tipp auf „Zugriff erlauben“: Die Systemabfrage würde den Test blockieren.
                XCTAssertTrue(app.buttons["reminderImport.allow"].waitForExistence(timeout: 3) || app.staticTexts["Erinnerungen werden gelesen …"].exists)
                snap(app, "65-erinnerungen-import-\(suffix)")
                tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
            }
            tapTab("Heute", in: app)
            if tapIfPresent(app.buttons["today.settings"]) {
                tapIfPresent(app.buttons["settings.page.data"])
                let external = app.buttons["backup.external"]
                if scrollTo(external, in: app, attempts: 8) {
                    snap(app, "66-sicherung-ordner-\(suffix)")
                }
                tapIfPresent(app.buttons["settings.done"])
            }
            app.terminate()
        }
    }

    /// Arzt-Tagebuch: Heute-Karte, Schmerz mit Körperkarte, Verlauf, Bewegung, Bericht mit Tabelle.
    @MainActor
    func testDiary() {
        let app = launch(extraArguments: ["-forceLight"])
        let card = app.descendants(matching: .any)["today.diary"]
        if scrollTo(card, in: app, attempts: 4) {
            snap(app, "70-heute-tagebuch")
        }
        tapTab("Gesundheit", in: app)
        let pains = app.buttons["health.pains"]
        guard scrollTo(pains, in: app, attempts: 6) else { return }
        snap(app, "71-gesundheit-tagebuch")

        if tapIfPresent(app.buttons["diary.pain"]) {
            tapIfPresent(app.buttons["body.shoulderRight"], timeout: 2)
            tapIfPresent(app.buttons["body.elbowRight"], timeout: 2)
            snap(app, "72-schmerz-eintragen")
            app.swipeUp()
            snap(app, "73-schmerz-details")
            dismissSheet(in: app, doneIdentifier: "pain.cancel")
        }
        if scrollTo(pains, in: app), tapIfPresent(pains) {
            snap(app, "74-schmerzen")
            tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
        }
        let activities = app.buttons["health.activities"]
        if scrollTo(activities, in: app), tapIfPresent(activities) {
            snap(app, "75-bewegung")
            if tapIfPresent(app.buttons["activities.add"]) {
                tapIfPresent(app.buttons["activity.cycling"], timeout: 2)
                snap(app, "76-bewegung-eintragen")
                dismissSheet(in: app, doneIdentifier: "activity.cancel")
            }
            tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
        }
        let bridge = app.buttons["health.bridge"]
        if scrollTo(bridge, in: app), tapIfPresent(bridge) {
            snap(app, "80-apple-health")
            let guide = app.buttons["healthBridge.guide"]
            if scrollTo(guide, in: app), tapIfPresent(guide) {
                snap(app, "81-health-anleitung")
                tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
            }
            tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
        }
        let report = app.buttons["health.report"]
        if scrollTo(report, in: app), tapIfPresent(report) {
            snap(app, "77-arztbericht")
            app.swipeUp()
            snap(app, "78-arztbericht-inhalt")
            let build = app.buttons["report.build"]
            if scrollTo(build, in: app), tapIfPresent(build) {
                Thread.sleep(forTimeInterval: 2)
                snap(app, "79-bericht-seite-1")
                for page in 2...8 {
                    app.swipeUp()
                    Thread.sleep(forTimeInterval: 0.5)
                    snap(app, "79-bericht-seite-\(page)")
                }
            }
        }
    }

    /// Leben: Übersicht, Routine, Gewohnheiten, Verträge, Geburtstage, Tagebuch.
    @MainActor
    func testLife() {
        let app = launch(extraArguments: ["-forceLight"])
        let habitsCard = app.descendants(matching: .any)["today.habits"]
        if scrollTo(habitsCard, in: app, attempts: 3) {
            snap(app, "50-heute-routinen")
        }
        tapTab("Planer", in: app)
        guard tapIfPresent(app.buttons["Leben"].firstMatch) else { return }
        snap(app, "51-leben")
        if tapIfPresent(app.buttons["habit.toggle.Morgenroutine"]) {
            snap(app, "52-routine")
            tapIfPresent(app.buttons["Fertig"].firstMatch)
        }
        let details = [
            ("life.habits", "53-gewohnheiten", "Lesen", "54-gewohnheit"),
            ("life.contracts", "55-vertraege", "Fitnessstudio", "56-vertrag"),
            ("life.birthdays", "57-geburtstage", "", ""),
        ]
        for (identifier, name, detail, detailName) in details {
            let link = app.buttons[identifier]
            guard scrollTo(link, in: app), tapIfPresent(link) else { continue }
            snap(app, name)
            if !detail.isEmpty {
                let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", detail)).firstMatch
                if tapIfPresent(row) {
                    snap(app, detailName)
                    tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
                }
            }
            tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
        }
        let journal = app.buttons["life.journal"]
        if scrollTo(journal, in: app), tapIfPresent(journal) {
            snap(app, "58-tagebuch")
            dismissSheet(in: app, doneIdentifier: "journal.done")
        }
        // Einstellungen: App-Sperre und Gym-Ankunft.
        tapTab("Heute", in: app)
        if tapIfPresent(app.buttons["today.settings"]) {
            tapIfPresent(app.buttons["settings.page.privacy"])
            let gym = app.buttons["settings.gym"]
            if scrollTo(gym, in: app, attempts: 4) {
                snap(app, "59-einstellungen-privat")
                if tapIfPresent(gym) {
                    snap(app, "60-gym-ankunft")
                    tapIfPresent(app.navigationBars.buttons.element(boundBy: 0))
                }
            }
            tapIfPresent(app.buttons["settings.done"])
        }
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

    /// Zwei Jahre Beispieldaten: misst Tagebuch, Bericht, Analyse, Sicherung. Die Zeiten landen im CI-Log.
    @MainActor
    func testPerformance() {
        let app = launch(extraArguments: ["-forceLight", "-perfTest"])
        let summary = app.staticTexts["perftest.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 30))
        let finished = NSPredicate(format: "label BEGINSWITH 'Alle' OR label BEGINSWITH 'Fehlgeschlagen'")
        expectation(for: finished, evaluatedWith: summary)
        waitForExpectations(timeout: 300)
        print((summary.value as? String) ?? "")
        snap(app, "16-tempo")
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

        tapTab("Training", in: app)
        snap(app, "16-training-\(suffix)")
        tapTab("Ernährung", in: app)
        snap(app, "26-ernaehrung-\(suffix)")
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
        // Nach dem Scrollen ist die Tab-Leiste eingeklappt: zurückscrollen, bis sie wieder da ist.
        for _ in 0..<3 where !(tabButton.exists && tabButton.isHittable) {
            app.swipeDown()
        }
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
