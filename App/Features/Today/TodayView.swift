import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit
import TipKit

/// Startseite: Was steht heute an, was ist als Nächstes dran, wie weit bin ich?
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(CalendarService.self) private var calendarService
    // Offene Aufgaben und heute erledigte, dazu die letzten Einheiten: Alte Einträge braucht „Heute“ nicht.
    @Query private var tasks: [TaskItem]
    @Query(sort: \Medication.sortIndex) private var medications: [Medication]
    @Query(sort: \WorkoutPlan.createdAt) private var plans: [WorkoutPlan]
    @Query private var workouts: [WorkoutSession]
    @AppStorage(SettingsKeys.userName) private var userName = ""
    @AppStorage(SettingsKeys.showCalendarEvents) private var showEvents = true
    @AppStorage(SettingsKeys.hiddenCalendarIDs) private var hiddenCalendarIDs = ""
    @AppStorage(SettingsKeys.showCheckIns) private var showCheckIns = true
    @AppStorage(SettingsKeys.todayLayout) private var layoutText = ""
    @State private var isPickingFocus = false
    @State private var isCustomizing = false
    private let quickAddTip = QuickAddTip()
    private let widgetTip = WidgetTip()

    init() {
        let start = AppModel.calendar.startOfDay(for: .now)
        let past = Date.distantPast
        _tasks = Query(filter: #Predicate<TaskItem> { !$0.isDone || ($0.completedAt ?? past) >= start }, sort: \TaskItem.createdAt)
        var recent = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        recent.fetchLimit = 30
        _workouts = Query(recent)
    }

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
            .sheet(isPresented: $isCustomizing) {
                TodayLayoutEditor(layoutText: $layoutText, initial: layout)
            }
        }
    }

    private func content(now: Date) -> some View {
        let calendar = AppModel.calendar
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        let filter = app.focusFilter
        let plan = filter.hideTraining ? nil : (plans.last(where: \.isActive) ?? plans.last)
        let visibleTasks = filter.listID.map { listID in tasks.filter { $0.list?.stableID == listID } } ?? tasks
        let source = AgendaSource(
            tasks: visibleTasks, medications: medications, training: (plan, workouts),
            calendarService: calendarService, showEvents: showEvents, hiddenCalendarIDsText: hiddenCalendarIDs
        )
        let todayItems = source.items(from: start, to: end, now: now)
        let doses = DayDoses(medications: medications.filter { $0.schedule.isScheduled }, day: now, now: now, calendar: calendar)
        let events = todayItems.filter { $0.kind == .event }.sorted { $0.start < $1.start }
        let progress = TodayProgress.compute(visibleTasks.map(\.facts), now: now, calendar: calendar)
        let todayTasks = TaskOrdering.sorted(
            visibleTasks.filter { SmartList.today.includes($0.facts, now: now, calendar: calendar) },
            facts: \.facts, now: now, calendar: calendar
        )
        let focusTasks = todayTasks.filter { $0.facts.isFocus(on: now, calendar: calendar) }
        let otherTasks = todayTasks.filter { !$0.facts.isFocus(on: now, calendar: calendar) }
        let nextUp = AgendaBuilder.nextUp(in: todayItems, now: now, calendar: calendar)

        let data = TodayData(
            now: now, filter: filter, plan: plan, source: source, doses: doses, events: events,
            focusTasks: focusTasks, otherTasks: otherTasks, nextUp: nextUp
        )

        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                TodayHeader(now: now, userName: userName)
                SigningBanner()
                if filter.isActive {
                    FocusFilterBanner(filter: filter)
                }
                if let storeError = app.storeError {
                    WarningCard(title: "Speicherproblem", message: storeError)
                }
                TipView(widgetTip)
                OverviewCard(progress: progress, doses: doses, eventCount: events.count, showsEvents: showEvents && calendarService.canRead)
                ForEach(layout.visibleCards) { card in
                    cardView(card, data: data)
                }
                Button {
                    isCustomizing = true
                } label: {
                    Label("Startseite anpassen", systemImage: "rectangle.3.group")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .tint(.secondary)
                .padding(.top, Spacing.xs)
                .accessibilityIdentifier("today.customize")
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xl)
        }
    }

    /// Gespeicherte Anordnung; wer vor 1.1 den Check-in ausgeschaltet hatte, behält das.
    private var layout: TodayLayout {
        var layout = TodayLayout.decode(layoutText)
        if layoutText.isEmpty, !showCheckIns { layout.setVisible(.checkIn, false) }
        return layout
    }

    /// Eine Karte, nur wenn es dafür heute etwas gibt.
    @ViewBuilder
    private func cardView(_ card: TodayCard, data: TodayData) -> some View {
        switch card {
        case .quickCapture:
            QuickCaptureBar(showsNutrition: !data.filter.hideNutrition)
        case .nextUp:
            if let nextUp = data.nextUp {
                NextUpCard(item: nextUp, now: data.now, task: data.source.task(for: nextUp))
            }
        case .tasks:
            TodayTasksCard(focus: data.focusTasks, others: data.otherTasks, onPick: { isPickingFocus = true })
        case .medications:
            if data.doses.total > data.doses.done {
                TodayDosesCard(today: data.doses, now: data.now, title: "Medikamente", collapsesResolved: true)
            }
        case .training:
            if let plan = data.plan {
                TrainingTodayCard(plan: plan, workouts: workouts, now: data.now)
            }
        case .checkIn:
            CheckInTodayCard(now: data.now, hidesWhenDone: true)
        case .diary:
            DiaryTodayCard(now: data.now)
        case .events:
            if showEvents, calendarService.canRead, !data.events.isEmpty {
                EventsCard(events: data.events)
            }
        case .habits:
            HabitsTodayCard(now: data.now)
        case .nutrition:
            if !data.filter.hideNutrition {
                NutritionTodayCard(now: data.now)
            }
        case .upcoming:
            LifeTodayCard(now: data.now)
        case .review:
            ReviewTodayCard(now: data.now)
        case .journal:
            JournalTodayCard(now: data.now)
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
                app.openSettings()
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
            .popoverTip(quickAddTip)
        }
    }
}

// MARK: - Karten

/// Hinweis, solange ein Fokus-Filter etwas ausblendet.
private struct FocusFilterBanner: View {
    let filter: FocusFilterState

    var body: some View {
        Label {
            Text("Fokus: \(filter.summary)")
                .font(.subheadline)
        } icon: {
            Image(systemName: "moon.circle.fill")
                .foregroundStyle(.indigo)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityIdentifier("today.focusFilter")
    }
}

private struct TodayHeader: View {
    let now: Date
    let userName: String

    @AppStorage(SettingsKeys.weekFocus) private var weekFocus = ""

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
            if let focus = WeekFocus.current(weekFocus, now: now, calendar: calendar) {
                Label(focus, systemImage: "scope")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .accessibilityLabel("Fokus der Woche: \(focus)")
            }
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
        case .birthday: "gift.fill"
        case .deadline: "doc.badge.clock"
        }
    }

    private var tint: Color {
        switch item.kind {
        case .event: Color(hex: item.colorHex)
        case .task: ModuleAccent.tasks
        case .medication: ModuleAccent.medication
        case .training: ModuleAccent.training
        case .birthday: .pink
        case .deadline: .orange
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

/// Was „Heute“ einmal berechnet und an die Karten weitergibt.
private struct TodayData {
    let now: Date
    let filter: FocusFilterState
    let plan: WorkoutPlan?
    let source: AgendaSource
    let doses: DayDoses
    let events: [AgendaItem]
    let focusTasks: [TaskItem]
    let otherTasks: [TaskItem]
    let nextUp: AgendaItem?
}

/// Fokus und fällige Aufgaben in einer Karte: erst bis zu drei Fokus-Aufgaben, dann der Rest.
private struct TodayTasksCard: View {
    let focus: [TaskItem]
    let others: [TaskItem]
    let onPick: () -> Void

    @Environment(AppModel.self) private var app
    private let limit = 5

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    SectionHeader("Aufgaben heute", systemImage: "checklist", tint: ModuleAccent.tasks)
                    if !focus.isEmpty || !others.isEmpty {
                        Button(focus.isEmpty ? "Fokus wählen" : "Fokus ändern", action: onPick)
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("today.focus.pick")
                    }
                }
                if focus.isEmpty && others.isEmpty {
                    Text("Für heute ist nichts offen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !focus.isEmpty {
                    Label("Fokus", systemImage: "scope")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ModuleAccent.today)
                        .padding(.top, 2)
                    ForEach(focus) { task in
                        TaskRow(task: task, onOpen: { app.editingTask = $0 })
                    }
                    if !others.isEmpty {
                        Text("Außerdem")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, Spacing.xxs)
                    }
                }
                ForEach(others.prefix(limit)) { task in
                    TaskRow(task: task, onOpen: { app.editingTask = $0 })
                }
                if others.count > limit {
                    NavigationLink {
                        TaskListScreen(scope: .smart(.today))
                    } label: {
                        Text("Alle \(focus.count + others.count) anzeigen")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.top, Spacing.xxs)
                }
            }
        }
        .accessibilityIdentifier("today.tasks")
    }
}

/// Eine Zeile zum schnellen Eintragen, statt Knöpfen in vielen Karten.
private struct QuickCaptureBar: View {
    let showsNutrition: Bool

    @Environment(AppModel.self) private var app
    @State private var waterAdded = 0
    @State private var showsWaterDone = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                chip("Aufgabe", "checklist", ModuleAccent.tasks, id: "quick.task") { app.openQuickAdd() }
                if showsNutrition {
                    chip("Mahlzeit", "fork.knife", ModuleAccent.nutrition, id: "quick.meal") { app.logMeal() }
                    chip(showsWaterDone ? "+250 ml" : "Wasser", showsWaterDone ? "checkmark" : "drop.fill", .cyan, id: "quick.water") { addWater() }
                }
                chip("Beschwerde", "bandage", ModuleAccent.health, id: "quick.symptom") { app.openSymptomEntry() }
                chip("Schmerz", "figure.stand", .red, id: "quick.pain") { app.openPainEntry() }
                chip("Bewegung", "figure.walk", .green, id: "quick.activity") { app.openActivityEntry() }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .sensoryFeedback(.success, trigger: waterAdded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Schnell erfassen")
    }

    private func chip(_ title: String, _ symbol: String, _ tint: Color, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, Spacing.xs)
                .background(tint.opacity(0.14), in: Capsule())
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func addWater() {
        app.addWater(NutritionTargets.glassML)
        waterAdded += 1
        withAnimation(.snappy) { showsWaterDone = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.snappy) { showsWaterDone = false }
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
    @Environment(\.modelContext) private var context

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
                            if isTrainingDay, let gaps = CoachActions.weeklyGapText(now: now, calendar: calendar, in: context) {
                                Text(gaps)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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

/// Histamin-Tageslast, Eiweiß und Wasser auf einen Blick.
private struct NutritionTodayCard: View {
    let now: Date

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    // Nur heute und das letzte Gewicht laden, nicht die ganze Geschichte.
    @Query private var meals: [MealEntry]
    @Query private var water: [WaterLog]
    @Query private var preferences: [FoodPreference]
    @Query private var metrics: [BodyMetric]
    @AppStorage(SettingsKeys.proteinPerKg) private var proteinPerKg = NutritionTargets.defaultProteinPerKg
    @AppStorage(SettingsKeys.waterTarget) private var waterTarget = NutritionTargets.defaultWaterML

    init(now: Date) {
        self.now = now
        let start = AppModel.calendar.startOfDay(for: now)
        let end = AppModel.calendar.date(byAdding: .day, value: 1, to: start) ?? now
        _meals = Query(filter: #Predicate<MealEntry> { $0.date >= start && $0.date < end }, sort: \MealEntry.date, order: .reverse)
        _water = Query(filter: #Predicate<WaterLog> { $0.date >= start && $0.date < end })
        let weight = BodyMetricType.weight.rawValue
        var latest = FetchDescriptor<BodyMetric>(predicate: #Predicate { $0.typeRaw == weight }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        latest.fetchLimit = 1
        _metrics = Query(latest)
    }

    var body: some View {
        let calendar = AppModel.calendar
        let catalog = NutritionActions.catalog(in: context)
        let tolerances = Dictionary(preferences.map { ($0.foodID, $0.tolerance) }, uniquingKeysWith: { $1 })
        let todayMeals = meals.filter { calendar.isDate($0.date, inSameDayAs: now) }
        let day = NutritionDay(
            day: calendar.startOfDay(for: now),
            meals: todayMeals.map { $0.fact(catalog: catalog) { tolerances[$0] ?? .unknown } },
            waterML: water.filter { calendar.isDate($0.date, inSameDayAs: now) }.reduce(0) { $0 + $1.milliliters },
            proteinTarget: NutritionTargets.proteinTarget(bodyweight: metrics.first { $0.type == .weight }?.value, perKg: proteinPerKg),
            waterTarget: waterTarget
        )
        let load = day.load
        Card {
            Button {
                app.openNutrition()
            } label: {
                HStack(spacing: Spacing.s) {
                    IconBadge(systemImage: "fork.knife", tint: ModuleAccent.nutrition)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Spacing.xs) {
                            Text("Ernährung")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.primary)
                            Label(load.level.title, systemImage: load.level.symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(load.level.color)
                        }
                        Text(summary(day))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Ernährung: Histamin \(load.level.title), \(summary(day))")
        }
        .accessibilityIdentifier("today.nutrition")
    }

    /// „2 Mahlzeiten · Eiweiß 74/148 g · Wasser 1/2,5 l“
    private func summary(_ day: NutritionDay) -> String {
        let meals = day.meals.count
        let mealText = meals == 0 ? "Noch keine Mahlzeit" : (meals == 1 ? "1 Mahlzeit" : "\(meals) Mahlzeiten")
        let protein = "Eiweiß \(Int(day.protein.rounded()))/\(Int(day.proteinTarget.rounded())) g"
        let water = "Wasser \(WeightFormat.number((Double(day.waterML) / 100).rounded() / 10))/\(WeightFormat.number(Double(day.waterTarget) / 1_000)) l"
        return [mealText, protein, water].joined(separator: " · ")
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
