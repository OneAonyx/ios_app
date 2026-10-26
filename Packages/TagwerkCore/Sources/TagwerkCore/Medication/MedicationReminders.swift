import Foundation

/// Mitteilungen für Medikamente: Einnahme, Nachfrage nach 30 Minuten, Nachfüllen.
public enum MedicationReminders {
    /// Nachfrage, falls die Einnahme nach so vielen Minuten noch offen ist.
    public static let followUpMinutes = 30
    /// Uhrzeit für Nachfüll-Hinweise.
    public static let refillHour = 9

    /// - Parameters:
    ///   - doses: offene Einnahmen (bereits protokollierte nicht übergeben)
    ///   - detail: z. B. „1 Tablette · vor dem Essen“
    ///   - includeMain: `false`, wenn ein Wecker die eigentliche Erinnerung übernimmt
    public static func candidates(
        doses: [ScheduledDose],
        name: String,
        detail: (ScheduledDose) -> String,
        includeMain: Bool = true,
        includeFollowUp: Bool = true,
        calendar: Calendar
    ) -> [ReminderCandidate] {
        doses.flatMap { dose -> [ReminderCandidate] in
            let time = GermanCalendar.time(dose.date, calendar: calendar)
            var result: [ReminderCandidate] = []
            if includeMain {
                result.append(ReminderCandidate(
                    id: NotificationIDs.Prefix.medication + dose.id,
                    kind: .medication,
                    fireDate: dose.date,
                    title: name,
                    body: "\(detail(dose)) · \(time)",
                    referenceID: dose.id
                ))
            }
            if includeFollowUp {
                result.append(ReminderCandidate(
                    id: NotificationIDs.Prefix.medicationFollowUp + dose.id,
                    kind: .medicationFollowUp,
                    fireDate: dose.date.addingTimeInterval(TimeInterval(followUpMinutes * 60)),
                    title: "Noch offen: \(name)",
                    body: "Geplant um \(time) – schon genommen?",
                    referenceID: dose.id
                ))
            }
            return result
        }
    }

    /// Nachfüll-Hinweis zur nächsten vollen `refillHour`, solange der Vorrat knapp ist.
    public static func refillCandidate(
        medicationID: String,
        name: String,
        stockText: String,
        forecast: StockForecast,
        now: Date,
        calendar: Calendar
    ) -> ReminderCandidate? {
        guard forecast.needsRefill || forecast.isEmpty else { return nil }
        guard var fire = calendar.date(bySettingHour: refillHour, minute: 0, second: 0, of: now) else { return nil }
        if fire <= now, let tomorrow = calendar.date(byAdding: .day, value: 1, to: fire) {
            fire = tomorrow
        }
        let range = forecast.rangeLabel(calendar: calendar).map { " – \($0)" } ?? ""
        return ReminderCandidate(
            id: NotificationIDs.Prefix.refill + medicationID,
            kind: .refill,
            fireDate: fire,
            title: "Vorrat: \(name)",
            body: "Noch \(stockText)\(range). Zeit für Nachschub.",
            referenceID: medicationID
        )
    }
}

/// Erzeugt aus einem Text immer dieselbe UUID (für Wecker-IDs, die sich wiederfinden lassen).
public enum StableUUID {
    public static func make(from text: String) -> UUID {
        let first = fnv1a(Array(text.utf8))
        let second = fnv1a(Array("tagwerk:\(text):\(text.count)".utf8))
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8(truncatingIfNeeded: first >> (UInt64(index) * 8))
            bytes[index + 8] = UInt8(truncatingIfNeeded: second >> (UInt64(index) * 8))
        }
        // Version 8 (frei definiert) und RFC-4122-Variante setzen.
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func fnv1a(_ bytes: [UInt8]) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
