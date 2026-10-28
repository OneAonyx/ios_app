import Foundation

/// Eine Tabelle als CSV, so dass Excel und Numbers auf deutschen Geräten sie direkt öffnen:
/// Semikolon als Trenner, Komma als Dezimalzeichen, UTF-8 mit BOM, Zeilenende CRLF.
public struct CSVTable: Sendable, Equatable {
    public var name: String
    public var header: [String]
    public var rows: [[String]]

    public init(name: String, header: [String], rows: [[String]] = []) {
        self.name = name
        self.header = header
        self.rows = rows
    }

    public var fileName: String { "\(name).csv" }

    public var isEmpty: Bool { rows.isEmpty }

    public var text: String {
        ([header] + rows).map { $0.map(Self.escape).joined(separator: ";") }.joined(separator: "\r\n") + "\r\n"
    }

    /// Mit BOM, damit Excel die Umlaute richtig liest.
    public var data: Data {
        Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
    }

    /// Anführungszeichen, wenn nötig; innere Anführungszeichen verdoppelt.
    static func escape(_ value: String) -> String {
        guard value.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Werte für Tabellen: Datum und Zahlen im deutschen Format.
public enum CSVFormat {
    /// „28.10.2026“
    public static func date(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.day, .month, .year], from: date)
        return String(format: "%02d.%02d.%04d", c.day ?? 0, c.month ?? 0, c.year ?? 0)
    }

    /// „07:45“
    public static func time(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    public static func optionalDate(_ date: Date?, calendar: Calendar) -> String {
        date.map { self.date($0, calendar: calendar) } ?? ""
    }

    public static func optionalTime(_ date: Date?, calendar: Calendar) -> String {
        date.map { time($0, calendar: calendar) } ?? ""
    }

    /// „82,5“, ganze Zahlen ohne Nachkomma.
    public static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        return WeightFormat.number((value * 100).rounded() / 100)
    }

    public static func int(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }

    public static func bool(_ value: Bool) -> String {
        value ? "ja" : "nein"
    }

    /// „orbit-arztpaket-2026-10-28“: Datum für Dateinamen.
    public static func fileDate(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.day, .month, .year], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
