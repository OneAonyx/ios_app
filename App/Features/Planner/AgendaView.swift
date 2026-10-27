import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Gemeinsame Datenquelle für Agenda, Woche und „Heute“: Aufgaben, Einnahmen, Kalendertermine.
struct AgendaSource {
    let tasks: [TaskItem]
    let medications: [Medication]
    /// Trainingstage und Einheiten (schon für den Zeitraum berechnet).
    let training: (WorkoutPlan?, [WorkoutSession])
    let calendarService: CalendarService
    let showEvents: Bool
    let hiddenCalendarIDs: Set<String>

    init(
        tasks: [TaskItem], medications: [Medication] = [], training: (WorkoutPlan?, [WorkoutSession]) = (nil, []),
        calendarService: CalendarService, showEvents: Bool, hiddenCalendarIDsText: String
    ) {
        self.tasks = tasks
        self.medications = medications
        self.training = training
        self.calendarService = calendarService
        self.showEvents = showEvents
        self.hiddenCalendarIDs = Set(hiddenCalendarIDsText.split(separator: "\n").map(String.init))
    }

    @MainActor
    func items(from start: Date, to end: Date, now: Date = .now) -> [AgendaItem] {
        // Liest den Zähler, damit Ansichten bei Kalenderänderungen neu zeichnen.
        _ = calendarService.changeCounter
        let taskItems = tasks.compactMap { $0.agendaItem() }
        let doseItems = medications.flatMap { $0.agendaItems(from: start, to: end, now: now, calendar: AppModel.calendar) }
        let trainingItems = TrainingActions.agendaItems(plan: training.0, sessions: training.1, from: start, to: end, now: now, calendar: AppModel.calendar)
        let lifeItems = LifeActions.agendaItems(from: start, to: end, now: now, calendar: AppModel.calendar, in: AppModel.shared.context)
        guard showEvents else { return taskItems + doseItems + trainingItems + lifeItems }
        return taskItems + doseItems + trainingItems + lifeItems + calendarService.items(from: start, to: end, hiddenCalendarIDs: hiddenCalendarIDs)
    }

    /// Medikament einer Einnahme in Agenda oder Woche.
    func medication(for item: AgendaItem) -> Medication? {
        guard item.kind == .medication, let parsed = DoseID.parse(String(item.id.dropFirst("dose-".count))) else { return nil }
        return medications.first { $0.stableID == parsed.medicationID }
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
    @Query(sort: \Medication.sortIndex) private var medications: [Medication]
    @Query(sort: \WorkoutPlan.createdAt) private var plans: [WorkoutPlan]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var workouts: [WorkoutSession]
    @AppStorage(SettingsKeys.showCalendarEvents) private var showEvents = true
    @AppStorage(SettingsKeys.hiddenCalendarIDs) private var hiddenCalendarIDs = ""

    private let dayCount = 14

    var body: some View {
        let now = Date.now
        let calendar = AppModel.calendar
        let source = AgendaSource(
            tasks: tasks, medications: medications, training: (plans.last(where: \.isActive) ?? plans.last, workouts),
            calendarService: calendarService, showEvents: showEvents, hiddenCalendarIDsText: hiddenCalendarIDs
        )
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
            } else if item.kind == .medication {
                DoseToggleButton(item: item)
                    .frame(width: 28)
            } else if item.kind == .training {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "dumbbell.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(item.isDone ? Color.green : ModuleAccent.training)
                    .frame(width: 28)
            } else if item.kind == .birthday || item.kind == .deadline {
                Image(systemName: item.kind == .birthday ? "gift.fill" : "doc.badge.clock")
                    .font(.system(size: 18))
                    .foregroundStyle(item.kind == .birthday ? Color.pink : Color.orange)
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
            } else if item.kind == .medication {
                app.openMedications()
            } else if item.kind == .training {
                app.openTraining()
            } else if item.kind == .birthday || item.kind == .deadline {
                app.openLife()
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

/// Abhak-Knopf für eine Einnahme in Agenda, Woche und „Als Nächstes“.
struct DoseToggleButton: View {
    let item: AgendaItem

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            MedicationActions.toggleTaken(doseID: String(item.id.dropFirst("dose-".count)), in: context, calendar: AppModel.calendar)
            app.medicationsChanged()
        } label: {
            Image(systemName: item.isDone ? "checkmark.circle.fill" : "pills.circle")
                .font(.system(size: 22))
                .foregroundStyle(item.isDone ? Color.green : ModuleAccent.medication)
                .frame(width: TouchTarget.standard, height: TouchTarget.standard)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.isDone ? "Einnahme zurücksetzen" : "Einnahme abhaken")
    }
}

/// Hinweis, wenn Orbit noch keinen Kalenderzugriff hat.
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
