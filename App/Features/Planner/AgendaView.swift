import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Gemeinsame Datenquelle für Agenda, Woche und „Heute“: Aufgaben + Kalendertermine.
struct AgendaSource {
    let tasks: [TaskItem]
    let calendarService: CalendarService
    let showEvents: Bool
    let hiddenCalendarIDs: Set<String>

    init(tasks: [TaskItem], calendarService: CalendarService, showEvents: Bool, hiddenCalendarIDsText: String) {
        self.tasks = tasks
        self.calendarService = calendarService
        self.showEvents = showEvents
        self.hiddenCalendarIDs = Set(hiddenCalendarIDsText.split(separator: "\n").map(String.init))
    }

    @MainActor
    func items(from start: Date, to end: Date) -> [AgendaItem] {
        // Liest den Zähler, damit Ansichten bei Kalenderänderungen neu zeichnen.
        _ = calendarService.changeCounter
        let taskItems = tasks.compactMap { $0.agendaItem() }
        guard showEvents else { return taskItems }
        return taskItems + calendarService.items(from: start, to: end, hiddenCalendarIDs: hiddenCalendarIDs)
    }

    func task(for item: AgendaItem) -> TaskItem? {
        guard item.kind == .task else { return nil }
        return tasks.first { "task-\($0.stableID)" == item.id }
    }
}

/// Die nächsten 14 Tage: Termine und Aufgaben, Tag für Tag.
struct AgendaView: View {
    @Environment(AppModel.self) private var app
    @Environment(CalendarService.self) private var calendarService
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @AppStorage(SettingsKeys.showCalendarEvents) private var showEvents = true
    @AppStorage(SettingsKeys.hiddenCalendarIDs) private var hiddenCalendarIDs = ""

    private let dayCount = 14

    var body: some View {
        let now = Date.now
        let calendar = AppModel.calendar
        let source = AgendaSource(tasks: tasks, calendarService: calendarService, showEvents: showEvents, hiddenCalendarIDsText: hiddenCalendarIDs)
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: dayCount, to: start) ?? now
        let days = AgendaBuilder.build(items: source.items(from: start, to: end), from: now, days: dayCount, now: now, calendar: calendar)

        List {
            if showEvents && !calendarService.canRead {
                CalendarAccessRow()
            }
            ForEach(days) { day in
                Section {
                    if day.isEmpty {
                        Text("Nichts geplant")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(day.allDay + day.timed) { item in
                            AgendaRow(item: item, task: source.task(for: item)) { task in
                                app.editingTask = task
                            }
                        }
                    }
                } header: {
                    DayHeader(date: day.date, now: now)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct DayHeader: View {
    let date: Date
    let now: Date

    var body: some View {
        let calendar = AppModel.calendar
        let relative = DueFormatter.dayLabel(for: date, now: now, calendar: calendar)
        let full = GermanCalendar.shortDate(date, calendar: calendar)
        HStack(spacing: Spacing.xs) {
            Text(relative == full ? full : "\(relative) · \(full)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(calendar.isDate(date, inSameDayAs: now) ? ModuleAccent.today : Color.primary)
            Spacer()
        }
        .textCase(nil)
    }
}

/// Termin oder Aufgabe in Agenda und Woche.
struct AgendaRow: View {
    let item: AgendaItem
    let task: TaskItem?
    var compact = false
    var onOpenTask: (TaskItem) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: Spacing.s) {
            timeColumn
            if let task {
                CompletionButton(isDone: task.isDone, priority: task.priority) {
                    TaskActions.toggleCompletion(task, in: context, calendar: AppModel.calendar)
                    app.tasksChanged()
                }
                .frame(width: 28)
            } else {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(hex: item.colorHex))
                    .frame(width: 4, height: compact ? 18 : 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(compact ? .subheadline : .body)
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                    .lineLimit(compact ? 1 : 2)
                if !compact, let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if item.isOverdue {
                Text("überfällig")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let task {
                onOpenTask(task)
            } else if let url = CalendarService.calendarAppURL(for: item.start) {
                openURL(url)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var timeColumn: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if item.isAllDay {
                Text("ganztägig")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(GermanCalendar.time(item.start, calendar: AppModel.calendar))
                    .font(.caption.monospacedDigit().weight(.semibold))
                if !compact, let end = item.end {
                    Text(GermanCalendar.time(end, calendar: AppModel.calendar))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 52, alignment: .trailing)
    }
}

/// Hinweis, wenn Tagwerk noch keinen Kalenderzugriff hat.
struct CalendarAccessRow: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: Spacing.s) {
            IconBadge(systemImage: "calendar.badge.plus", tint: ModuleAccent.calendar)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kalender verbinden")
                    .font(.headline)
                Text("Dann erscheinen deine Termine hier zwischen den Aufgaben.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(calendarService.access == .denied ? "Einstellungen" : "Erlauben") {
                if calendarService.access == .denied {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } else {
                    Task { await calendarService.requestAccess() }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}
