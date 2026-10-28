import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Eine Routine oder Gewohnheit für heute: Fortschritt, abhaken, hochzählen.
struct HabitTodayRow: View {
    let habit: Habit
    let now: Date

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query private var logs: [HabitLog]
    @State private var showsRoutine = false

    init(habit: Habit, now: Date) {
        self.habit = habit
        self.now = now
        _logs = Query(filter: HabitLogFilter.day(habitID: habit.stableID, day: now))
    }

    var body: some View {
        let calendar = AppModel.calendar
        let today = calendar.startOfDay(for: now)
        let entry = logs.first { $0.habitID == habit.stableID && calendar.isDate($0.day, inSameDayAs: today) }
        let fraction = habit.fact.fraction(entry?.habitDay)
        let done = fraction >= 1
        let tint = ListColor.color(named: habit.colorName)
        HStack(spacing: Spacing.s) {
            Button {
                if habit.kind == .routine, !done {
                    showsRoutine = true
                } else {
                    LifeActions.toggleDone(habit, on: now, calendar: calendar, in: context)
                    app.lifeChanged()
                }
            } label: {
                ProgressRing(fraction: fraction, tint: tint, lineWidth: 4) {
                    Image(systemName: done ? "checkmark" : habit.symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(done ? Color.green : tint)
                }
                .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "\(habit.name) erledigt" : "\(habit.name) abhaken")
            .accessibilityIdentifier("habit.toggle.\(habit.name)")
            .sensoryFeedback(.success, trigger: done) { old, new in !old && new }

            Button {
                if habit.kind == .routine { showsRoutine = true }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(done ? Color.secondary : Color.primary)
                        .strikethrough(done && habit.kind == .habit)
                    Text(detail(entry: entry))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if habit.kind == .habit, !done, habit.target > 1 {
                Button {
                    LifeActions.add(step, to: habit, on: now, calendar: calendar, in: context)
                    app.lifeChanged()
                } label: {
                    Text("+\(WeightFormat.number(step))")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, 6)
                        .background(tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(tint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(WeightFormat.number(step)) \(habit.unit) zu \(habit.name) hinzufügen")
            }
        }
        .sheet(isPresented: $showsRoutine) {
            RoutineSheet(habit: habit, day: now)
        }
    }

    private var step: Double {
        habit.target >= 10 ? 5 : 1
    }

    private func detail(entry: HabitLog?) -> String {
        switch habit.kind {
        case .routine:
            let steps = habit.steps
            let done = steps.filter { entry?.doneSteps.contains($0.id) == true }.count
            return steps.isEmpty ? habit.period.title : "\(done) von \(steps.count) Schritten"
        case .habit:
            let value = entry?.value ?? 0
            if habit.target <= 1 { return habit.schedule.summary }
            let unit = habit.unit.isEmpty ? "" : " \(habit.unit)"
            return "\(WeightFormat.number(value)) von \(WeightFormat.number(habit.target))\(unit)"
        }
    }
}

/// Schritte einer Routine abhaken.
struct RoutineSheet: View {
    let habit: Habit
    let day: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query private var logs: [HabitLog]

    init(habit: Habit, day: Date) {
        self.habit = habit
        self.day = day
        _logs = Query(filter: HabitLogFilter.day(habitID: habit.stableID, day: day))
    }

    var body: some View {
        let calendar = AppModel.calendar
        let entry = logs.first { $0.habitID == habit.stableID && calendar.isDate($0.day, inSameDayAs: day) }
        let done = Set(entry?.doneSteps ?? [])
        NavigationStack {
            List {
                Section {
                    ForEach(habit.steps) { step in
                        Button {
                            LifeActions.toggleStep(step.id, of: habit, on: day, calendar: calendar, in: context)
                            app.lifeChanged()
                        } label: {
                            HStack(spacing: Spacing.s) {
                                Image(systemName: done.contains(step.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(done.contains(step.id) ? Color.green : Color.secondary)
                                Text(step.title)
                                    .foregroundStyle(done.contains(step.id) ? Color.secondary : Color.primary)
                                    .strikethrough(done.contains(step.id))
                            }
                        }
                        .accessibilityIdentifier("routine.step.\(step.title)")
                    }
                } footer: {
                    if !habit.steps.isEmpty, done.count >= habit.steps.count {
                        Label("Geschafft!", systemImage: "party.popper")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle(habit.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: done.count >= habit.steps.count)
        }
        .presentationDetents([.medium, .large])
    }
}

/// Alle Routinen und Gewohnheiten, auch die heute nicht fälligen und archivierten.
struct HabitsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Habit.sortIndex), SortDescriptor(\Habit.createdAt)]) private var habits: [Habit]
    @State private var creating = false

    var body: some View {
        let active = habits.filter { !$0.isArchived }
        let archived = habits.filter(\.isArchived)
        List {
            ForEach(HabitKind.allCases) { kind in
                let items = active.filter { $0.kind == kind }
                if !items.isEmpty {
                    Section(kind == .routine ? "Routinen" : "Gewohnheiten") {
                        ForEach(items) { habit in
                            NavigationLink {
                                HabitDetailView(habit: habit)
                            } label: {
                                HabitListRow(habit: habit)
                            }
                        }
                    }
                }
            }
            if !archived.isEmpty {
                Section("Archiv") {
                    ForEach(archived) { habit in
                        NavigationLink {
                            HabitDetailView(habit: habit)
                        } label: {
                            HabitListRow(habit: habit)
                        }
                    }
                }
            }
        }
        .overlay {
            if habits.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Routinen", systemImage: "repeat")
                } description: {
                    Text("Starte mit einer Vorlage, z. B. Morgenroutine oder Dehnen.")
                } actions: {
                    Button("Hinzufügen") { creating = true }
                }
            }
        }
        .navigationTitle("Routinen & Gewohnheiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Routine oder Gewohnheit hinzufügen")
            }
        }
        .sheet(isPresented: $creating) {
            HabitTemplatePicker()
        }
    }
}

private struct HabitListRow: View {
    let habit: Habit

    var body: some View {
        HStack(spacing: Spacing.s) {
            IconBadge(systemImage: habit.symbol, tint: ListColor.color(named: habit.colorName))
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.body.weight(.semibold))
                Text([habit.schedule.summary, habit.period == .anytime ? nil : habit.period.title, habit.kind == .habit && habit.target > 1 ? habit.targetText : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Serie, Quote und die letzten 12 Wochen.
struct HabitDetailView: View {
    let habit: Habit

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Query private var logs: [HabitLog]
    @State private var editing = false
    @State private var confirmDelete = false

    init(habit: Habit) {
        self.habit = habit
        let id = habit.stableID
        _logs = Query(filter: #Predicate<HabitLog> { $0.habitID == id })
    }

    /// „1 Tag“, „3 Tage“, „1 Woche“
    static func unit(_ count: Int, weeks: Bool) -> String {
        if weeks { return count == 1 ? "Woche" : "Wochen" }
        return count == 1 ? "Tag" : "Tage"
    }

    var body: some View {
        let calendar = AppModel.calendar
        let now = Date.now
        let own = logs.filter { $0.habitID == habit.stableID }
        let days = Dictionary(own.map { (calendar.startOfDay(for: $0.day), $0.habitDay) }, uniquingKeysWith: { lhs, _ in lhs })
        let stats = HabitProgress.stats(habit.fact, days: days, today: now, calendar: calendar)
        List {
            Section {
                HStack {
                    StatTile(title: "Serie", value: "\(stats.current)", detail: Self.unit(stats.current, weeks: stats.unitIsWeeks), tint: ListColor.color(named: habit.colorName))
                    StatTile(title: "Beste", value: "\(stats.best)", detail: Self.unit(stats.best, weeks: stats.unitIsWeeks), tint: .primary)
                    StatTile(title: "30 Tage", value: stats.rate.map { "\(Int(($0 * 100).rounded())) %" } ?? "–", detail: "erledigt", tint: .primary)
                }
                .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.s, bottom: Spacing.xs, trailing: Spacing.s))
                LabeledContent("Diese Woche", value: "\(stats.thisWeek) von \(stats.weekTarget)")
            }
            Section("Letzte 12 Wochen") {
                HabitHeatmap(fact: habit.fact, days: days, now: now, tint: ListColor.color(named: habit.colorName))
                    .padding(.vertical, Spacing.xxs)
            }
            Section {
                LabeledContent("Rhythmus", value: habit.schedule.summary)
                LabeledContent("Tageszeit", value: habit.period.title)
                if habit.kind == .habit {
                    LabeledContent("Ziel", value: habit.targetText)
                }
                LabeledContent("Erinnerung", value: habit.reminderMinute >= 0 ? String(format: "%02d:%02d Uhr", habit.reminderMinute / 60, habit.reminderMinute % 60) : "aus")
                if habit.kind == .routine {
                    ForEach(habit.steps) { step in
                        Label(step.title, systemImage: "circle")
                            .font(.subheadline)
                    }
                }
            }
            Section {
                Button(habit.isArchived ? "Wieder aktivieren" : "Archivieren") {
                    habit.isArchived.toggle()
                    LifeActions.save(context)
                    app.lifeChanged()
                }
                Button("Löschen", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Archivierte Einträge erinnern nicht mehr, der Verlauf bleibt.")
            }
        }
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Bearbeiten") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            HabitEditorView(habit: habit, template: nil)
        }
        .confirmationDialog("„\(habit.name)“ löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                LifeActions.delete(habit, in: context)
                app.lifeChanged()
                dismiss()
            }
        } message: {
            Text("Der Verlauf wird ebenfalls gelöscht.")
        }
    }
}

/// Kästchen je Tag, Montag oben, älteste Woche links.
struct HabitHeatmap: View {
    let fact: HabitFact
    let days: [Date: HabitDay]
    let now: Date
    let tint: Color

    var body: some View {
        let calendar = AppModel.calendar
        let thisWeek = AgendaBuilder.startOfWeek(containing: now, calendar: calendar)
        let weeks = (0..<12).reversed().compactMap { calendar.date(byAdding: .day, value: -7 * $0, to: thisWeek) }
        HStack(alignment: .top, spacing: 3) {
            VStack(spacing: 3) {
                ForEach(["M", "D", "M", "D", "F", "S", "S"].indices, id: \.self) { index in
                    Text(["M", "D", "M", "D", "F", "S", "S"][index])
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, height: 14)
                }
            }
            ForEach(weeks, id: \.self) { monday in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { offset in
                        let day = calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
                        let fraction = fact.fraction(days[day])
                        let future = day > now
                        let due = fact.schedule.isDue(on: day, calendar: calendar) && day >= calendar.startOfDay(for: fact.createdAt)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(future ? Color.clear : (fraction > 0 ? tint.opacity(0.25 + 0.75 * fraction) : Color.primary.opacity(due ? 0.1 : 0.04)))
                            .frame(maxWidth: .infinity)
                            .frame(height: 14)
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Verlauf der letzten 12 Wochen")
    }
}

/// Vorlagen oder eigene Routine bzw. Gewohnheit.
struct HabitTemplatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var custom: HabitKind?

    var body: some View {
        NavigationStack {
            List {
                Section("Vorlagen") {
                    ForEach(LifeTemplates.habits) { template in
                        Button {
                            LifeActions.createHabit(from: template, in: context)
                            app.lifeChanged()
                            dismiss()
                        } label: {
                            HStack(spacing: Spacing.s) {
                                IconBadge(systemImage: template.symbol, tint: template.kind == .routine ? .indigo : .orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name)
                                        .foregroundStyle(Color.primary)
                                    Text(template.kind == .routine ? template.steps.joined(separator: " · ") : "\(template.schedule.summary) · \(template.target > 1 ? "\(WeightFormat.number(template.target)) \(template.unit)" : "1×")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .accessibilityIdentifier("habitTemplate.\(template.name)")
                    }
                }
                Section("Eigene") {
                    Button {
                        custom = .routine
                    } label: {
                        Label("Eigene Routine (Schritte)", systemImage: "checklist")
                    }
                    Button {
                        custom = .habit
                    } label: {
                        Label("Eigene Gewohnheit (Ziel je Tag)", systemImage: "target")
                    }
                }
            }
            .navigationTitle("Hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .navigationDestination(item: $custom) { kind in
                HabitEditorView(habit: nil, template: kind, onDone: { dismiss() })
            }
        }
    }
}

/// Neue oder bestehende Routine bzw. Gewohnheit bearbeiten.
struct HabitEditorView: View {
    let habit: Habit?
    /// Art bei neuen Einträgen.
    let template: HabitKind?
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var name = ""
    @State private var kind: HabitKind = .habit
    @State private var symbol = "checkmark.circle"
    @State private var colorName = ListColor.orange.rawValue
    @State private var period: HabitPeriod = .anytime
    @State private var scheduleKind: HabitSchedule.Kind = .daily
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var timesPerWeek = 3
    @State private var target = 1.0
    @State private var unit = ""
    @State private var steps: [RoutineStep] = []
    @State private var newStep = ""
    @State private var remind = false
    @State private var reminderTime = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now
    @State private var loaded = false

    private static let symbols = [
        "checkmark.circle", "sunrise.fill", "moon.stars.fill", "figure.flexibility", "figure.walk", "book", "drop.fill",
        "brain.head.profile", "bed.double", "pills", "leaf", "pencil", "music.note", "dumbbell", "fork.knife", "sparkles",
    ]

    var body: some View {
        let isNew = habit == nil
        let content = Form {
            Section {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("habit.name")
                if isNew {
                    Picker("Art", selection: $kind) {
                        ForEach(HabitKind.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            Section("Symbol und Farbe") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: Spacing.xs) {
                    ForEach(Self.symbols, id: \.self) { item in
                        Button {
                            symbol = item
                        } label: {
                            Image(systemName: item)
                                .frame(width: 34, height: 34)
                                .background(symbol == item ? ListColor.color(named: colorName).opacity(0.2) : Color.clear, in: Circle())
                                .foregroundStyle(symbol == item ? ListColor.color(named: colorName) : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(ListColor.allCases) { item in
                            Button {
                                colorName = item.rawValue
                            } label: {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().strokeBorder(Color.primary, lineWidth: colorName == item.rawValue ? 2 : 0))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.rawValue)
                        }
                    }
                }
            }
            Section("Wann") {
                Picker("Tageszeit", selection: $period) {
                    ForEach(HabitPeriod.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                Picker("Rhythmus", selection: $scheduleKind) {
                    Text("Täglich").tag(HabitSchedule.Kind.daily)
                    Text("Bestimmte Tage").tag(HabitSchedule.Kind.weekdays)
                    Text("x pro Woche").tag(HabitSchedule.Kind.timesPerWeek)
                }
                if scheduleKind == .weekdays {
                    HStack(spacing: 4) {
                        ForEach(GermanCalendar.weekdayOrder, id: \.self) { weekday in
                            let isOn = weekdays.contains(weekday)
                            Button {
                                if isOn { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
                            } label: {
                                Text(GermanCalendar.shortWeekdays[weekday - 1])
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 34)
                                    .background(isOn ? ListColor.color(named: colorName).opacity(0.2) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(isOn ? ListColor.color(named: colorName) : Color.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if scheduleKind == .timesPerWeek {
                    Stepper("\(timesPerWeek)× pro Woche", value: $timesPerWeek, in: 1...7)
                }
            }
            if kind == .habit {
                Section {
                    Stepper(value: $target, in: 1...500, step: target >= 10 ? 5 : 1) {
                        HStack {
                            Text("Ziel je Tag")
                            Spacer()
                            Text(WeightFormat.number(target))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextField("Einheit (z. B. Min., Seiten)", text: $unit)
                } footer: {
                    Text("Ziel 1 ohne Einheit heißt: einmal am Tag abhaken.")
                }
            } else {
                Section {
                    ForEach(steps) { step in
                        Text(step.title)
                    }
                    .onDelete { steps.remove(atOffsets: $0) }
                    .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
                    HStack {
                        TextField("Neuer Schritt", text: $newStep)
                            .onSubmit(addStep)
                            .accessibilityIdentifier("habit.newStep")
                        Button("Hinzufügen", action: addStep)
                            .disabled(newStep.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Schritte")
                }
            }
            Section {
                Toggle("Erinnern", isOn: $remind)
                if remind {
                    DatePicker("Uhrzeit", selection: $reminderTime, displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("Erinnert nur an fälligen Tagen und nur, solange noch nichts erledigt ist.")
            }
        }
        .navigationTitle(isNew ? (kind == .routine ? "Neue Routine" : "Neue Gewohnheit") : "Bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("habit.save")
            }
        }
        .onAppear(perform: load)

        if habit == nil {
            content
        } else {
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Abbrechen") { dismiss() }
                        }
                    }
            }
        }
    }

    private func addStep() {
        let title = newStep.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        steps.append(RoutineStep(title: title))
        newStep = ""
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let habit {
            name = habit.name
            kind = habit.kind
            symbol = habit.symbol
            colorName = habit.colorName
            period = habit.period
            let schedule = habit.schedule
            scheduleKind = schedule.kind
            if !schedule.weekdays.isEmpty { weekdays = Set(schedule.weekdays) }
            timesPerWeek = schedule.timesPerWeek
            target = habit.target
            unit = habit.unit
            steps = habit.steps
            remind = habit.reminderMinute >= 0
            if remind {
                reminderTime = Calendar.current.date(bySettingHour: habit.reminderMinute / 60, minute: habit.reminderMinute % 60, second: 0, of: .now) ?? reminderTime
            }
        } else if let template {
            kind = template
            symbol = template == .routine ? "checklist" : "checkmark.circle"
            colorName = template == .routine ? ListColor.indigo.rawValue : ListColor.orange.rawValue
        }
    }

    private func save() {
        let schedule: HabitSchedule = switch scheduleKind {
        case .daily: .daily
        case .weekdays: .weekdays(Array(weekdays))
        case .timesPerWeek: .times(timesPerWeek)
        }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let minute = remind ? (parts.hour ?? 8) * 60 + (parts.minute ?? 0) : -1
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let habit {
            habit.name = trimmed
            habit.symbol = symbol
            habit.colorName = colorName
            habit.period = period
            habit.schedule = schedule
            habit.target = kind == .habit ? target : 1
            habit.unit = kind == .habit ? unit.trimmingCharacters(in: .whitespaces) : ""
            habit.steps = steps
            habit.reminderMinute = minute
            LifeActions.save(context)
        } else {
            LifeActions.createHabit(
                name: trimmed, kind: kind, symbol: symbol, colorName: colorName, period: period, schedule: schedule,
                target: kind == .habit ? target : 1, unit: kind == .habit ? unit.trimmingCharacters(in: .whitespaces) : "",
                steps: steps.map(\.title), reminderMinute: minute, in: context
            )
        }
        app.lifeChanged()
        if let onDone { onDone() } else { dismiss() }
    }
}

/// Abfragen für Routine-Einträge: nur eine Routine an einem Tag statt aller Einträge.
enum HabitLogFilter {
    static func day(habitID: String, day: Date) -> Predicate<HabitLog> {
        let start = AppModel.calendar.startOfDay(for: day)
        let end = AppModel.calendar.date(byAdding: .day, value: 1, to: start) ?? day
        return #Predicate<HabitLog> { $0.habitID == habitID && $0.day >= start && $0.day < end }
    }
}
