import EventKit
import Foundation
import SwiftData
import TagwerkCore

/// Einmaliger Import aus Apple Erinnerungen. Erinnerungen bleiben dabei unverändert,
/// es gibt keinen Abgleich in beide Richtungen.
@MainActor
public final class ReminderImporter {
    public struct ReminderList: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let colorHex: String?
    }

    public struct Result: Equatable, Sendable {
        public let imported: Int
        public let lists: Int
        public let skipped: Int

        public var summary: String {
            ReminderImport.summary(imported: imported, lists: lists, skipped: skipped)
        }
    }

    private let store = EKEventStore()

    public init() {}

    public static var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    public static var isDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        return status == .denied || status == .restricted
    }

    public func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    public func lists() -> [ReminderList] {
        store.calendars(for: .reminder)
            .map { calendar in
                ReminderList(id: calendar.calendarIdentifier, title: calendar.title, colorHex: calendar.cgColor.flatMap(Self.hex))
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Alle Erinnerungen, nach Listen-ID gruppiert und schon in testbare Werte übersetzt.
    public func remindersByList() async -> [String: [ExternalReminder]] {
        let calendars = store.calendars(for: .reminder)
        guard !calendars.isEmpty else { return [:] }
        let predicate = store.predicateForReminders(in: calendars)
        return await withCheckedContinuation { continuation in
            _ = store.fetchReminders(matching: predicate) { @Sendable reminders in
                var grouped: [String: [ExternalReminder]] = [:]
                for reminder in reminders ?? [] {
                    grouped[reminder.calendar?.calendarIdentifier ?? "", default: []].append(Self.external(reminder))
                }
                continuation.resume(returning: grouped)
            }
        }
    }

    /// Legt Listen (gleicher Name) und Aufgaben an. Schon importierte werden übersprungen.
    public func importReminders(_ reminders: [ExternalReminder], includeCompleted: Bool, calendar: Calendar, in context: ModelContext) -> Result {
        let existing = Set(((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).map(\.stableID))
        let plan = ReminderImport.plan(reminders, existingIDs: existing, includeCompleted: includeCompleted, calendar: calendar)
        var sortIndex = TaskActions.nextSortIndex(in: context)
        var lists: [String: TaskList] = [:]
        for item in plan {
            let list = lists[item.listName] ?? TaskActions.findOrCreateList(named: item.listName, in: context)
            lists[item.listName] = list
            let task = TaskItem(
                title: item.title, notes: item.notes, dueDate: item.dueDate, hasDueTime: item.hasDueTime,
                priority: item.priority, list: list, sortIndex: sortIndex, stableID: item.stableID
            )
            task.recurrence = item.recurrence
            if item.isDone {
                task.isDone = true
                task.completedAt = item.completedAt ?? .now
            }
            context.insert(task)
            sortIndex += 1
        }
        TaskActions.save(context)
        return Result(imported: plan.count, lists: Set(plan.map(\.listName)).count, skipped: reminders.count - plan.count)
    }

    nonisolated private static func external(_ reminder: EKReminder) -> ExternalReminder {
        let rule = reminder.recurrenceRules?.first
        let frequency: ExternalReminder.Frequency? = switch rule?.frequency {
        case .daily?: .daily
        case .weekly?: .weekly
        case .monthly?: .monthly
        case .yearly?: .yearly
        default: nil
        }
        return ExternalReminder(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes ?? "",
            listName: reminder.calendar?.title ?? "Erinnerungen",
            due: reminder.dueDateComponents,
            priority: reminder.priority,
            isCompleted: reminder.isCompleted,
            completedAt: reminder.completionDate,
            frequency: frequency,
            interval: rule?.interval ?? 1,
            weekdays: rule?.daysOfTheWeek?.map { $0.dayOfTheWeek.rawValue } ?? []
        )
    }

    nonisolated private static func hex(_ color: CGColor) -> String? {
        guard let components = color.components, components.count >= 3 else { return nil }
        return String(format: "#%02X%02X%02X", Int(components[0] * 255), Int(components[1] * 255), Int(components[2] * 255))
    }
}
