import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Startseite: Was steht heute an, was ist als Nächstes dran, wie weit bin ich?
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(CalendarService.self) private var calendarService
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @Query(sort: \Medication.sortIndex) private var medications: [Medication]
    @Query(sort: \WorkoutPlan.createdAt) private var plans: [WorkoutPlan]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var workouts: [WorkoutSession]
    @AppStorage(SettingsKeys.userName) private var userName = ""
    @AppStorage(SettingsKeys.showCalendarEvents) private var showEvents = true
    @AppStorage(SettingsKeys.hiddenCalendarIDs) private var hiddenCalendarIDs = ""
    @State private var isPickingFocus = false

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                content(now: context.date)
            }
            .background(Color.tagwerkPage)
            .navigationTitle("Heute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $isPickingFocus) {
                FocusPickerView(allTasks: tasks)
            }
        }
    }

    private func content(now: Date) -> some View {
        let calendar = AppModel.calendar
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        let plan = plans.last(where: \.isActive) ?? plans.last
        let source = AgendaSource(
            tasks: tasks, medications: medications, training: (plan, workouts),
            calendarService: calendarService, showEvents: showEvents, hiddenCalendarIDsText: hiddenCalendarIDs
        )
        let todayItems = source.items(from: start, to: end, now: now)
        let doses = DayDoses(medications: medications.filter { $0.schedule.isScheduled }, day: now, now: now, calendar: calendar)
        let events = todayItems.filter { $0.kind == .event }.sorted { $0.start < $1.start }
        let progress = TodayProgress.compute(tasks.map(\.facts), now: now, calendar: calendar)
        let todayTasks = TaskOrdering.sorted(
            tasks.filter { SmartList.today.includes($0.facts, now: now, calendar: calendar) },
            facts: \.facts, now: now, calendar: calendar
        )
        let focusTasks = todayTasks.filter { $0.facts.isFocus(on: now, calendar: calendar) }
        let otherTasks = todayTasks.filter { !$0.facts.isFocus(on: now, calendar: calendar) }
        let nextUp = AgendaBuilder.nextUp(in: todayItems, now: now, calendar: calendar)

        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                TodayHeader(now: now, userName: userName)
                SigningBanner()
                if let storeError = app.storeError {
                    WarningCard(title: "Speicherproblem", message: storeError)
                }
                OverviewCard(progress: progress, doses: doses, eventCount: events.count, showsEvents: showEvents && calendarService.canRead)
                if let nextUp {
                    NextUpCard(item: nextUp, now: now, task: source.task(for: nextUp))
                }
                if doses.total > 0 {
                    TodayDosesCard(today: doses, now: now, title: "Medikamente", collapsesResolved: true)
                }
                if let plan {
                    TrainingTodayCard(plan: plan, workouts: workouts, now: now)
                }
                FocusCard(tasks: focusTasks, allTasks: tasks, onPick: { isPickingFocus = true })
                DueTodayCard(tasks: otherTasks, allTasks: tasks, hasFocus: !focusTasks.isEmpty)
                if showEvents {
                    EventsCard(events: events)
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xl)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                app.isShowingSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Suche")
            .accessibilityIdentifier("today.search")

            Button {
                app.isShowingSettings = true
            } label: {
                Image(systemName: "person.crop.circle")
            }
            .accessibilityLabel("Einstellungen")
            .accessibilityIdentifier("today.settings")
        }
        ToolbarItem(placement: .topBarLeading) {
            Button {
                app.openQuickAdd()
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Neue Aufgabe")
            .accessibilityIdentifier("today.quickadd")
        }
    }
}

// MARK: - Karten

private struct TodayHeader: View {
    let now: Date
    let userName: String

    var body: some View {
        let calendar = AppModel.calendar
        let weekday = GermanCalendar.longWeekdays[calendar.component(.weekday, from: now) - 1]
        let dateText = "\(weekday), \(calendar.component(.day, from: now)). \(GermanCalendar.shortMonths[calendar.component(.month, from: now) - 1])"
        let greeting = DayPeriod(date: now, calendar: calendar).greeting
        let name = userName.trimmingCharacters(in: .whitespaces)
        VStack(alignment: .leading, spacing: 2) {
            Text(dateText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ModuleAccent.today)
                .textCase(.uppercase)
            Text(name.isEmpty ? greeting : "\(greeting), \(name)")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

private struct OverviewCard: View {
    let progress: TodayProgress
    let doses: DayDoses
    let eventCount: Int
    let showsEvents: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Bei sehr großer Schrift steht der Ring über dem Text statt daneben.
        let large = typeSize.isAccessibilitySize
        let layout = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s)) : AnyLayout(HStackLayout(spacing: Spacing.m))
        let ringSize: CGFloat = large ? 100 : (doses.total > 0 ? 60 : 72)
        Card {
            layout {
                HStack(spacing: Spacing.s) {
                    ring(done: progress.done, total: progress.total, fraction: progress.fraction, tint: ModuleAccent.tasks, label: "Aufgaben")
                        .frame(width: ringSize, height: ringSize)
                    if doses.total > 0 {
                        ring(done: doses.done, total: doses.total, fraction: doses.fraction, tint: ModuleAccent.medication, label: "Einnahmen")
                            .frame(width: ringSize, height: ringSize)
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(headline)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func ring(done: Int, total: Int, fraction: Double, tint: Color, label: String) -> some View {
        ProgressRing(fraction: fraction, tint: tint, lineWidth: 8) {
            VStack(spacing: 0) {
                Text("\(done)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text("von \(total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .minimumScaleFactor(0.5)
            .padding(Spacing.xs)
        }
        .accessibilityLabel("\(label): \(done) von \(total)")
    }

    private var headline: String {
        if progress.total == 0 { return "Heute ist nichts fällig" }
        if progress.open == 0 { return "Alles erledigt" }
        return progress.open == 1 ? "Noch 1 Aufgabe offen" : "Noch \(progress.open) Aufgaben offen"
    }

    private var detail: String {
        var parts: [String] = []
        if progress.done > 0 {
            parts.append("\(progress.done) erledigt")
        }
        if doses.total > 0 {
            let open = doses.total - doses.done
            parts.append(open == 0 ? "Medikamente erledigt" : (open == 1 ? "1 Einnahme offen" : "\(open) Einnahmen offen"))
        }
        if showsEvents {
            parts.append(eventCount == 1 ? "1 Termin" : "\(eventCount) Termine")
        }
        return parts.isEmpty ? "Plane deinen Tag mit „Neue Aufgabe“." : parts.joined(separator: " · ")
    }
}

private struct NextUpCard: View {
    let item: AgendaItem
    let now: Date
    let task: TaskItem?

    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionHeader("Als Nächstes", systemImage: "arrow.forward.circle", tint: ModuleAccent.today)
                HStack(spacing: Spacing.s) {
                    IconBadge(systemImage: symbol, tint: tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text(timeText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if item.kind == .medication {
                        DoseToggleButton(item: item)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let task {
                app.editingTask = task
            } else if item.kind == .medication {
                app.openMedications()
            } else if let url = CalendarService.calendarAppURL(for: item.start) {
                openURL(url)
            }
        }
    }

    private var symbol: String {
        switch item.kind {
        case .event: "calendar"
        case .task: "checklist"
        case .medication: "pills.fill"
        case .training: "dumbbell.fill"
        }
    }

    private var tint: Color {
        switch item.kind {
        case .event: Color(hex: item.colorHex)
        case .task: ModuleAccent.tasks
        case .medication: ModuleAccent.medication
        case .training: ModuleAccent.training
        }
    }

    private var timeText: String {
        let calendar = AppModel.calendar
        let start = GermanCalendar.time(item.start, calendar: calendar)
        if item.start <= now {
            if let end = item.end { return "Läuft bis \(GermanCalendar.time(end, calendar: calendar))" }
            return "Jetzt"
        }
        let minutes = Int(item.start.timeIntervalSince(now) / 60)
        let detail = item.kind == .medication ? (item.subtitle.map { " · \($0)" } ?? "") : ""
        if minutes < 60 { return "\(start) · in \(max(minutes, 1)) Min.\(detail)" }
        let hours = minutes / 60
        return "\(start) · in \(hours) Std.\(detail)"
    }
}

private struct FocusCard: View {
    let tasks: [TaskItem]
    let allTasks: [TaskItem]
    let onPick: () -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    SectionHeader("Fokus heute", systemImage: "scope", tint: ModuleAccent.today)
                    Button(tasks.isEmpty ? "Wählen" : "Ändern", action: onPick)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("today.focus.pick")
                }
                if tasks.isEmpty {
                    Text("Wähle bis zu drei Aufgaben, die heute wirklich zählen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tasks) { task in
                        TaskRow(task: task, onOpen: { app.editingTask = $0 })
                    }
                }
            }
        }
    }
}

private struct DueTodayCard: View {
    let tasks: [TaskItem]
    let allTasks: [TaskItem]
    let hasFocus: Bool

    @Environment(AppModel.self) private var app
    private let limit = 6

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionHeader(hasFocus ? "Außerdem heute" : "Heute fällig", systemImage: "checklist", tint: ModuleAccent.tasks)
                if tasks.isEmpty {
                    Text(hasFocus ? "Sonst steht heute nichts an." : "Für heute ist nichts offen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tasks.prefix(limit)) { task in
                        TaskRow(task: task, onOpen: { app.editingTask = $0 })
                    }
                    if tasks.count > limit {
                        NavigationLink {
                            TaskListScreen(scope: .smart(.today))
                        } label: {
                            Text("Alle \(tasks.count) anzeigen")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.top, Spacing.xxs)
                    }
                }
            }
        }
    }
}

private struct EventsCard: View {
    let events: [AgendaItem]

    @Environment(CalendarService.self) private var calendarService
    @Environment(AppModel.self) private var app

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionHeader("Termine heute", systemImage: "calendar", tint: ModuleAccent.calendar)
                if !calendarService.canRead {
                    CalendarAccessRow()
                } else if events.isEmpty {
                    Text("Keine Termine im Kalender.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(events) { event in
                        AgendaRow(item: event, task: nil, compact: true) { _ in }
                    }
                }
            }
        }
    }
}

/// Training auf „Heute“: läuft gerade, heute erledigt oder als Nächstes.
private struct TrainingTodayCard: View {
    let plan: WorkoutPlan
    let workouts: [WorkoutSession]
    let now: Date

    @Environment(AppModel.self) private var app

    var body: some View {
        let calendar = AppModel.calendar
        let active = workouts.first(where: \.isActive)
        let doneToday = workouts.first { !$0.isActive && calendar.isDate($0.startedAt, inSameDayAs: now) }
        let isTrainingDay = plan.preferredWeekdays.contains(calendar.component(.weekday, from: now))
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionHeader("Training", systemImage: "dumbbell", tint: ModuleAccent.training)
                if let active {
                    HStack(spacing: Spacing.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Läuft: \(active.title)")
                                .font(.headline)
                            Text(active.startedAt, style: .timer)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button("Weiter") { app.isShowingWorkout = true }
                            .buttonStyle(.borderedProminent)
                            .tint(ModuleAccent.training)
                    }
                } else if let doneToday {
                    Label("Heute erledigt: \(doneToday.title)", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    if let next = plan.nextDay {
                        Text("Als Nächstes: \(next.title)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let next = plan.nextDay {
                    HStack(spacing: Spacing.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(next.title)
                                .font(.headline)
                            Text([isTrainingDay ? "Heute ist Trainingstag" : nil, "ca. \(next.estimatedMinutes(week: plan.currentWeek, cycle: plan.cycle)) Min.", plan.isDeloadWeek ? "Deload" : nil]
                                .compactMap { $0 }
                                .joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(isTrainingDay ? ModuleAccent.training : Color.secondary)
                        }
                        Spacer(minLength: 0)
                        Button {
                            app.startWorkout()
                        } label: {
                            Label("Start", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ModuleAccent.training)
                        .accessibilityIdentifier("today.training.start")
                    }
                }
            }
        }
    }
}

private struct WarningCard: View {
    let title: String
    let message: String

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: Spacing.s) {
                IconBadge(systemImage: "exclamationmark.triangle.fill", tint: .orange)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title).font(.headline)
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Hinweis, wenn die kostenlose Signatur bald abläuft.
private struct SigningBanner: View {
    private let status = SigningInfo.currentStatus()

    var body: some View {
        let level = status.level(now: .now)
        if status.kind == .freeAppleID, level != .ok {
            WarningCard(
                title: level == .expired ? "Signatur abgelaufen" : "App läuft bald ab",
                message: "Signatur \(status.remainingText(now: .now)). Spiel Orbit über iloader oder SideStore neu auf, deine Daten bleiben erhalten."
            )
        }
    }
}

// MARK: - Fokus wählen

/// Bis zu drei Aufgaben für heute in den Fokus nehmen.
struct FocusPickerView: View {
    let allTasks: [TaskItem]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        let now = Date.now
        let calendar = AppModel.calendar
        let candidates = TaskOrdering.sorted(allTasks.filter { !$0.isDone }, facts: \.facts, now: now, calendar: calendar)
        let focusCount = candidates.filter { $0.facts.isFocus(on: now, calendar: calendar) }.count

        NavigationStack {
            List {
                Section {
                    ForEach(candidates) { task in
                        let isFocus = task.facts.isFocus(on: now, calendar: calendar)
                        Button {
                            TaskActions.toggleFocus(task, allTasks: allTasks, in: context, calendar: calendar)
                        } label: {
                            HStack {
                                Image(systemName: isFocus ? "scope" : "circle")
                                    .foregroundStyle(isFocus ? ModuleAccent.today : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .foregroundStyle(Color.primary)
                                    if let due = task.dueDate {
                                        Text(DueFormatter.label(due: due, hasTime: task.hasDueTime, now: now, calendar: calendar))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .disabled(!isFocus && !FocusRules.canAddFocus(currentCount: focusCount))
                    }
                } footer: {
                    Text("\(focusCount) von \(FocusRules.maximum) gewählt")
                }
            }
            .overlay {
                if candidates.isEmpty {
                    ContentUnavailableView("Keine offenen Aufgaben", systemImage: "checklist", description: Text("Lege zuerst Aufgaben an."))
                }
            }
            .navigationTitle("Fokus heute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
