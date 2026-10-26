import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Startseite: Was steht heute an, was ist als Nächstes dran, wie weit bin ich?
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(CalendarService.self) private var calendarService
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
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
        let source = AgendaSource(tasks: tasks, calendarService: calendarService, showEvents: showEvents, hiddenCalendarIDsText: hiddenCalendarIDs)
        let todayItems = source.items(from: start, to: end)
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
                OverviewCard(progress: progress, eventCount: events.count, showsEvents: showEvents && calendarService.canRead)
                if let nextUp {
                    NextUpCard(item: nextUp, now: now, task: source.task(for: nextUp))
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
    let eventCount: Int
    let showsEvents: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Bei sehr großer Schrift steht der Ring über dem Text statt daneben.
        let large = typeSize.isAccessibilitySize
        let layout = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s)) : AnyLayout(HStackLayout(spacing: Spacing.m))
        Card {
            layout {
                ProgressRing(fraction: progress.fraction, tint: ModuleAccent.tasks, lineWidth: 9) {
                    VStack(spacing: 0) {
                        Text("\(progress.done)")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text("von \(progress.total)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .minimumScaleFactor(0.6)
                    .padding(Spacing.xs)
                }
                .frame(width: large ? 110 : 72, height: large ? 110 : 72)

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
                    IconBadge(
                        systemImage: item.kind == .event ? "calendar" : "checklist",
                        tint: item.kind == .event ? Color(hex: item.colorHex) : ModuleAccent.tasks
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text(timeText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let task {
                app.editingTask = task
            } else if let url = CalendarService.calendarAppURL(for: item.start) {
                openURL(url)
            }
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
        if minutes < 60 { return "\(start) · in \(max(minutes, 1)) Min." }
        let hours = minutes / 60
        return "\(start) · in \(hours) Std."
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
                message: "Signatur \(status.remainingText(now: .now)). Spiel Tagwerk über iloader oder SideStore neu auf, deine Daten bleiben erhalten."
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
