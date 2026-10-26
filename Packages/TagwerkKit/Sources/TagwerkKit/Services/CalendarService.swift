import EventKit
import Foundation
import Observation
import TagwerkCore
import UIKit

/// Zugriff auf Apple Kalender (EventKit): Termine lesen und anlegen.
@MainActor
@Observable
public final class CalendarService {
    public enum Access: Equatable {
        case notDetermined
        case denied
        case writeOnly
        case full
    }

    public struct CalendarInfo: Identifiable, Hashable {
        public let id: String
        public let title: String
        public let colorHex: String
        public let sourceTitle: String
    }

    public private(set) var access: Access = .notDetermined
    /// Ändert sich, wenn sich Kalenderdaten ändern. Ansichten lesen den Wert, um neu zu laden.
    public private(set) var changeCounter = 0

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?

    public init() {
        refreshAccess()
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.changeCounter += 1
            }
        }
    }

    public var canRead: Bool { access == .full }

    public func refreshAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .full
        case .writeOnly:
            access = .writeOnly
        case .notDetermined:
            access = .notDetermined
        default:
            access = .denied
        }
    }

    @discardableResult
    public func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        refreshAccess()
        changeCounter += 1
        return granted
    }

    public func calendars() -> [CalendarInfo] {
        guard canRead else { return [] }
        return store.calendars(for: .event)
            .map { calendar in
                CalendarInfo(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    colorHex: Self.hex(from: calendar.cgColor),
                    sourceTitle: calendar.source?.title ?? ""
                )
            }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    /// Termine im Zeitraum als Agenda-Einträge, ohne ausgeblendete Kalender.
    public func items(from start: Date, to end: Date, hiddenCalendarIDs: Set<String>) -> [AgendaItem] {
        guard canRead else { return [] }
        let visible = store.calendars(for: .event).filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: visible)
        return store.events(matching: predicate).map { event in
            AgendaItem(
                id: "event-\(event.calendarItemIdentifier)-\(Int(event.startDate.timeIntervalSince1970))",
                kind: .event,
                title: event.title ?? "Termin",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                colorHex: Self.hex(from: event.calendar.cgColor),
                subtitle: event.location?.isEmpty == false ? event.location : event.calendar.title
            )
        }
    }

    /// Legt einen Termin im Standardkalender an.
    public func createEvent(title: String, start: Date, end: Date, isAllDay: Bool) throws {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = isAllDay
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent)
        changeCounter += 1
    }

    /// Öffnet die Kalender-App an diesem Zeitpunkt.
    public static func calendarAppURL(for date: Date) -> URL? {
        URL(string: "calshow:\(date.timeIntervalSinceReferenceDate)")
    }

    static func hex(from cgColor: CGColor?) -> String {
        guard let cgColor else { return "#5E5CE6" }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(cgColor: cgColor).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}
