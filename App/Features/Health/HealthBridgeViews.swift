import Charts
import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Karte im Tab „Gesundheit“: Werte aus Apple Health (über Kurzbefehle).
struct HealthBridgeCard: View {
    let now: Date

    @Query(sort: \HealthDay.day, order: .reverse) private var days: [HealthDay]

    var body: some View {
        let calendar = AppModel.calendar
        let today = days.first { calendar.isDate($0.day, inSameDayAs: now) }?.fact
        Card {
            NavigationLink {
                HealthBridgeView()
            } label: {
                HStack(spacing: Spacing.s) {
                    IconBadge(systemImage: "heart.text.square.fill", tint: .pink)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Apple Health")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.primary)
                        Text(detail(today: today, calendar: calendar))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("health.bridge")
        }
    }

    private func detail(today: HealthDayFact?, calendar: Calendar) -> String {
        guard let last = HealthActions.lastImport else {
            return "Schritte, Schlaf und Gewicht über Kurzbefehle übernehmen. Einmal einrichten."
        }
        let steps = today?.stepsText ?? "heute noch keine Schritte"
        return "\(steps) · zuletzt \(HealthShortcut.lastImportText(last, now: now, calendar: calendar))"
    }
}

/// Werte aus Apple Health: heute, Verlauf, Kurzbefehl starten, Anleitung.
struct HealthBridgeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Query(sort: \HealthDay.day) private var days: [HealthDay]

    var body: some View {
        let calendar = AppModel.calendar
        let now = Date.now
        let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
        let recent = days.filter { $0.day >= start }.map(\.fact)
        let today = recent.first { calendar.isDate($0.day, inSameDayAs: now) }
        let summary = HealthSummary.compute(recent, from: start, to: now.addingTimeInterval(1))
        List {
            if let message = app.healthMessage {
                Section {
                    Label(message, systemImage: message.hasPrefix("Fehler") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(message.hasPrefix("Fehler") ? Color.orange : Color.green)
                }
            }
            Section {
                if let today {
                    value("Schritte", today.steps.map { GermanNumber.grouped($0) }, symbol: "figure.walk")
                    value("Strecke", today.distanceKm.map { "\(WeightFormat.number(($0 * 10).rounded() / 10)) km" }, symbol: "map")
                    value("Stockwerke", today.flights.map(String.init), symbol: "figure.stairs")
                    value("Schlaf", today.sleepHours.map { "\(WeightFormat.number(($0 * 10).rounded() / 10)) Std." }, symbol: "bed.double.fill")
                    value("Ruhepuls", today.restingHeartRate.map { "\($0) /min" }, symbol: "heart")
                } else {
                    Text("Für heute sind noch keine Werte da.")
                        .foregroundStyle(.secondary)
                }
                Button {
                    app.healthMessage = nil
                    openURL(HealthShortcut.runURL())
                } label: {
                    Label("Jetzt aus Health holen", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("healthBridge.run")
            } header: {
                Text("Heute")
            } footer: {
                Text("Zuletzt übernommen: \(HealthShortcut.lastImportText(HealthActions.lastImport, now: now, calendar: calendar)). Startet den Kurzbefehl „\(HealthShortcut.name)“.")
            }

            if !recent.isEmpty {
                Section {
                    Chart(recent) { day in
                        if let steps = day.steps {
                            BarMark(x: .value("Tag", day.day, unit: .day), y: .value("Schritte", steps))
                                .foregroundStyle(Color.pink.opacity(0.7))
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        }
                    }
                    .frame(height: 150)
                    .accessibilityLabel("Schritte der letzten 30 Tage")
                    if let text = summary.stepsText {
                        Text(text)
                            .font(.subheadline)
                    }
                    if let sleep = summary.averageSleepHours {
                        LabeledContent("Schlaf Ø", value: "\(WeightFormat.number((sleep * 10).rounded() / 10)) Std.")
                    }
                    if let pulse = summary.averageRestingHeartRate {
                        LabeledContent("Ruhepuls Ø", value: "\(pulse) /min")
                    }
                    if summary.totalDistanceKm > 0 {
                        LabeledContent("Strecke gesamt", value: "\(WeightFormat.number(summary.totalDistanceKm.rounded())) km")
                    }
                } header: {
                    Text("Letzte 30 Tage")
                }
            }

            Section {
                NavigationLink {
                    HealthShortcutGuideView()
                } label: {
                    Label("Kurzbefehl einrichten", systemImage: "list.number")
                }
                .accessibilityIdentifier("healthBridge.guide")
            } footer: {
                Text("Orbit darf Health ohne Developer-Account nicht selbst lesen. Die Kurzbefehle-App darf es und gibt die Werte an Orbit weiter. Schritte zählen im Tagebuch als Bewegung, Gewicht landet unter Körper, Schlaf im Check-in.")
            }
        }
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func value(_ title: String, _ text: String?, symbol: String) -> some View {
        if let text {
            LabeledContent {
                Text(text)
                    .monospacedDigit()
            } label: {
                Label(title, systemImage: symbol)
            }
        }
    }
}

/// Schritt-für-Schritt-Anleitung für den Kurzbefehl „Orbit Health“ und die tägliche Automation.
struct HealthShortcutGuideView: View {
    @Environment(\.openURL) private var openURL

    private struct Step: Identifiable {
        let id: Int
        let title: String
        let detail: String
    }

    private let shortcut: [Step] = [
        Step(id: 1, title: "Neuen Kurzbefehl anlegen",
             detail: "Kurzbefehle-App → „+“. Nenne ihn genau „\(HealthShortcut.name)“."),
        Step(id: 2, title: "Schritte von heute",
             detail: "Aktion „Health-Proben suchen“ (englisch „Find Health Samples“): Typ „Schritte“, Startdatum „ist heute“. Darunter „Statistik berechnen“ („Calculate Statistics“): „Summe“ der Health-Proben."),
        Step(id: 3, title: "Strecke (freiwillig)",
             detail: "Wie Schritt 2 mit Typ „Gehen + Laufen Distanz“ in Kilometern."),
        Step(id: 4, title: "Gewicht (freiwillig)",
             detail: "„Health-Proben suchen“: Typ „Gewicht“, sortiert nach Startdatum, neueste zuerst, Limit 1. Nur nötig, wenn eine Waage Werte in Health schreibt."),
        Step(id: 5, title: "Schlaf (freiwillig)",
             detail: "Nur wenn Health Schlafdaten hat (Schlafplan in der Health-App): „Health-Proben suchen“, Typ „Schlafanalyse“, Startdatum in den letzten 24 Stunden, dann die Dauer summieren. Orbit versteht Stunden oder Minuten."),
        Step(id: 6, title: "Werte an Orbit geben",
             detail: "Aktion „Health-Werte an Orbit“ (Orbit): Schritte = Ergebnis aus Schritt 2, dazu Strecke, Gewicht, Schlaf, falls vorhanden. Leere Felder sind kein Problem."),
        Step(id: 7, title: "Einmal ausführen",
             detail: "Auf ▶︎ tippen. Die Kurzbefehle-App fragt einmal nach dem Zugriff auf Health: erlauben. Orbit antwortet mit „Orbit hat übernommen: …“."),
    ]

    private let back: [Step] = [
        Step(id: 1, title: "Wasser",
             detail: "Am Ende des Kurzbefehls: „Wasser für Health“ (Orbit), dann „Health-Probe protokollieren“ („Log Health Sample“): Typ „Wasser“, Wert = Ergebnis, Einheit ml. Orbit liefert nur, was seit dem letzten Lauf dazukam."),
        Step(id: 2, title: "Gewicht",
             detail: "„Gewicht für Health“ (Orbit), dann „Wenn Ergebnis größer als 0“ → „Health-Probe protokollieren“: Typ „Gewicht“, Wert = Ergebnis, Einheit kg."),
    ]

    private let automation: [Step] = [
        Step(id: 1, title: "Automation anlegen",
             detail: "Kurzbefehle-App → „Automation“ → „+“ → „Tageszeit“: 21:30, täglich."),
        Step(id: 2, title: "Ohne Nachfrage",
             detail: "„Sofort ausführen“ wählen (nicht „Vor dem Ausführen bestätigen“)."),
        Step(id: 3, title: "Kurzbefehl wählen",
             detail: "Aktion „Kurzbefehl ausführen“ → „\(HealthShortcut.name)“. Fertig. Gern auch eine zweite Automation am Morgen für den Schlaf."),
    ]

    var body: some View {
        List {
            Section {
                Text("So kommen Schritte, Schlaf und Gewicht aus Apple Health in Orbit, ganz ohne Developer-Account und ohne Kosten. Einmal einrichten, dann läuft es jeden Abend von selbst.")
                    .font(.subheadline)
            }
            steps("Kurzbefehl „\(HealthShortcut.name)“", shortcut)
            steps("Zurück nach Health (freiwillig)", back)
            steps("Jeden Abend automatisch", automation)
            Section {
                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label("Kurzbefehle-App öffnen", systemImage: "square.stack.3d.up")
                }
                Button {
                    openURL(HealthShortcut.runURL())
                } label: {
                    Label("Kurzbefehl jetzt testen", systemImage: "play.circle")
                }
            } footer: {
                Text("Die Namen der Aktionen können je nach iOS-Version leicht abweichen. In der Suche der Kurzbefehle-App hilft „Health“ bzw. „Orbit“.")
            }
        }
        .navigationTitle("Kurzbefehl einrichten")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func steps(_ title: String, _ items: [Step]) -> some View {
        Section(title) {
            ForEach(items) { step in
                HStack(alignment: .top, spacing: Spacing.s) {
                    Text("\(step.id)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.pink)
                        .frame(width: 30, height: 30)
                        .background(Color.pink.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.headline)
                        Text(step.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
