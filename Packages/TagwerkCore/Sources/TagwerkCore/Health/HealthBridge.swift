import Foundation

/// Werte aus Apple Health, die ein Kurzbefehl an Orbit übergibt. Orbit selbst darf Health ohne
/// Developer-Account nicht lesen, die Kurzbefehle-App schon.
public struct HealthValues: Sendable, Equatable {
    public var steps: Int?
    public var distanceKm: Double?
    public var flights: Int?
    public var sleepHours: Double?
    public var restingHeartRate: Int?
    public var weightKg: Double?

    public init(steps: Int? = nil, distanceKm: Double? = nil, flights: Int? = nil, sleepHours: Double? = nil, restingHeartRate: Int? = nil, weightKg: Double? = nil) {
        self.steps = steps
        self.distanceKm = distanceKm
        self.flights = flights
        self.sleepHours = sleepHours
        self.restingHeartRate = restingHeartRate
        self.weightKg = weightKg
    }

    public var isEmpty: Bool {
        steps == nil && distanceKm == nil && flights == nil && sleepHours == nil && restingHeartRate == nil && weightKg == nil
    }

    /// Nur plausible Werte bleiben. 0 bei Schlaf, Puls und Gewicht heißt „nicht gemessen“.
    /// Schlaf über 24 kommt vor, wenn ein Kurzbefehl Minuten statt Stunden liefert: dann umrechnen.
    public func sanitized() -> (values: HealthValues, rejected: [String]) {
        var result = HealthValues()
        var rejected: [String] = []
        func check<T: Comparable>(_ value: T?, _ range: ClosedRange<T>, _ name: String) -> T? {
            guard let value else { return nil }
            if range.contains(value) { return value }
            rejected.append(name)
            return nil
        }
        result.steps = check(steps, 0...100_000, "Schritte")
        result.distanceKm = check(distanceKm, 0...200, "Strecke")
        result.flights = check(flights, 0...500, "Stockwerke")
        var sleep = sleepHours
        if let value = sleep, value > 24, value <= 24 * 60 { sleep = value / 60 }
        result.sleepHours = sleep == 0 ? nil : check(sleep, 0.5...24, "Schlaf")
        result.restingHeartRate = restingHeartRate == 0 ? nil : check(restingHeartRate, 25...220, "Ruhepuls")
        result.weightKg = weightKg == 0 ? nil : check(weightKg, 30...300, "Gewicht")
        return (result, rejected)
    }

    /// „8.432 Schritte, 6,1 km, Schlaf 7,2 Std.“
    public var summary: String {
        var parts: [String] = []
        if let steps { parts.append("\(GermanNumber.grouped(steps)) Schritte") }
        if let distanceKm { parts.append("\(WeightFormat.number((distanceKm * 10).rounded() / 10)) km") }
        if let flights { parts.append("\(flights) Stockwerke") }
        if let sleepHours { parts.append("Schlaf \(WeightFormat.number((sleepHours * 10).rounded() / 10)) Std.") }
        if let restingHeartRate { parts.append("Ruhepuls \(restingHeartRate)") }
        if let weightKg { parts.append("\(WeightFormat.number(weightKg)) kg") }
        return parts.isEmpty ? "keine Werte" : parts.joined(separator: ", ")
    }
}

/// Ein Tag mit Health-Werten.
public struct HealthDayFact: Sendable, Hashable, Identifiable {
    public var day: Date
    public var steps: Int?
    public var distanceKm: Double?
    public var flights: Int?
    public var sleepHours: Double?
    public var restingHeartRate: Int?
    public var id: Date { day }

    public init(day: Date, steps: Int? = nil, distanceKm: Double? = nil, flights: Int? = nil, sleepHours: Double? = nil, restingHeartRate: Int? = nil) {
        self.day = day
        self.steps = steps
        self.distanceKm = distanceKm
        self.flights = flights
        self.sleepHours = sleepHours
        self.restingHeartRate = restingHeartRate
    }

    /// Neue Werte ersetzen alte. Fehlende Werte lassen den bisherigen Stand stehen
    /// (der Kurzbefehl läuft oft mehrmals am Tag und liefert jedes Mal die Tagessumme).
    public func merging(_ values: HealthValues) -> HealthDayFact {
        var copy = self
        if let steps = values.steps { copy.steps = steps }
        if let distance = values.distanceKm { copy.distanceKm = distance }
        if let flights = values.flights { copy.flights = flights }
        if let sleep = values.sleepHours { copy.sleepHours = sleep }
        if let pulse = values.restingHeartRate { copy.restingHeartRate = pulse }
        return copy
    }

    /// „8.432 Schritte“ für die Tag-für-Tag-Tabelle, `nil` ohne Schritte.
    public var stepsText: String? {
        steps.map { "\(GermanNumber.grouped($0)) Schritte" }
    }
}

/// Auswertung über einen Zeitraum.
public struct HealthSummary: Sendable, Hashable {
    public var days: Int
    public var stepDays: Int
    public var averageSteps: Int?
    public var averageSleepHours: Double?
    public var averageRestingHeartRate: Int?
    public var totalDistanceKm: Double

    public static func compute(_ facts: [HealthDayFact], from: Date, to: Date) -> HealthSummary {
        let inRange = facts.filter { $0.day >= from && $0.day < to }
        let steps = inRange.compactMap(\.steps).filter { $0 > 0 }
        let sleep = inRange.compactMap(\.sleepHours)
        let pulse = inRange.compactMap(\.restingHeartRate)
        return HealthSummary(
            days: inRange.count,
            stepDays: steps.count,
            averageSteps: steps.isEmpty ? nil : Int((Double(steps.reduce(0, +)) / Double(steps.count)).rounded()),
            averageSleepHours: sleep.isEmpty ? nil : sleep.reduce(0, +) / Double(sleep.count),
            averageRestingHeartRate: pulse.isEmpty ? nil : Int((Double(pulse.reduce(0, +)) / Double(pulse.count)).rounded()),
            totalDistanceKm: inRange.compactMap(\.distanceKm).reduce(0, +)
        )
    }

    public static let empty = HealthSummary(days: 0, stepDays: 0, averageSteps: nil, averageSleepHours: nil, averageRestingHeartRate: nil, totalDistanceKm: 0)

    /// „Ø 7.850 Schritte am Tag (26 Tage gemessen)“
    public var stepsText: String? {
        guard let averageSteps else { return nil }
        return "Ø \(GermanNumber.grouped(averageSteps)) Schritte am Tag (\(stepDays) \(stepDays == 1 ? "Tag" : "Tage") gemessen)"
    }
}

/// Werte, die zurück nach Health gehen, ohne doppelte Einträge.
public enum HealthExport {
    /// Merkt sich, wie viel Wasser an einem Tag schon nach Health ging.
    public struct WaterMarker: Codable, Sendable, Equatable {
        public var day: Date
        public var exportedML: Int

        public init(day: Date, exportedML: Int) {
            self.day = day
            self.exportedML = exportedML
        }
    }

    /// Neues Wasser seit dem letzten Lauf (nur heute). Ergebnis 0, wenn nichts dazukam.
    public static func water(todayTotal: Int, marker: WaterMarker?, now: Date, calendar: Calendar) -> (milliliters: Int, marker: WaterMarker) {
        let today = calendar.startOfDay(for: now)
        let already = marker.flatMap { calendar.isDate($0.day, inSameDayAs: today) ? $0.exportedML : nil } ?? 0
        let delta = max(0, todayTotal - already)
        return (delta, WaterMarker(day: today, exportedML: max(already, todayTotal)))
    }

    /// Neuester Gewichtswert, der noch nicht nach Health ging (nur aus Orbit, nicht aus Health).
    public static func weight(_ weights: [(date: Date, value: Double)], lastExported: Date?) -> (date: Date, value: Double)? {
        guard let newest = weights.max(by: { $0.date < $1.date }) else { return nil }
        // Toleranz: Die Marke liegt als Sekunden seit 1970 in den Einstellungen, `Date` rechnet ab 2001.
        // Beim Umrechnen kann sie um Bruchteile einer Millisekunde kleiner werden; ohne Toleranz ginge
        // dasselbe Gewicht dann ein zweites Mal an Health.
        if let lastExported, newest.date.timeIntervalSince(lastExported) <= 0.001 { return nil }
        return newest
    }
}

/// Aufruf und Rücksprung des Kurzbefehls „Orbit Health“.
public enum HealthShortcut {
    public static let name = "Orbit Health"

    /// Rücksprung-Host: `tagwerk://healthbridge/success|cancel|error`.
    public static let callbackHost = "healthbridge"

    /// `shortcuts://x-callback-url/run-shortcut?name=Orbit%20Health&x-success=tagwerk://healthbridge/success…`
    public static func runURL(scheme: String = TagwerkIDs.urlScheme) -> URL {
        let parameters = [
            ("name", name),
            ("x-success", "\(scheme)://\(callbackHost)/success"),
            ("x-cancel", "\(scheme)://\(callbackHost)/cancel"),
            ("x-error", "\(scheme)://\(callbackHost)/error"),
        ]
        let query = parameters.map { "\($0.0)=\(URLEncoding.strict($0.1))" }.joined(separator: "&")
        return URL(string: "shortcuts://x-callback-url/run-shortcut?\(query)")!
    }

    /// „vor 5 Min.“, „heute 21:30“, „gestern 21:30“, „am 12. Okt.“, „noch nie“
    public static func lastImportText(_ date: Date?, now: Date, calendar: Calendar) -> String {
        guard let date else { return "noch nie" }
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "gerade eben" }
        if minutes < 60 { return "vor \(minutes) Min." }
        if calendar.isDate(date, inSameDayAs: now) { return "heute \(GermanCalendar.time(date, calendar: calendar))" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "gestern \(GermanCalendar.time(date, calendar: calendar))"
        }
        return "am " + WeeklyReview.dayMonth(date, calendar: calendar)
    }
}

/// Ganze Zahlen mit Tausenderpunkt: 8432 → „8.432“.
public enum GermanNumber {
    public static func grouped(_ value: Int) -> String {
        let digits = String(abs(value))
        var result = ""
        for (index, character) in digits.reversed().enumerated() {
            if index > 0, index % 3 == 0 { result.append(".") }
            result.append(character)
        }
        return (value < 0 ? "-" : "") + String(result.reversed())
    }
}
