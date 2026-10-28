import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Aufgabe bearbeiten. Änderungen werden sofort gespeichert.
struct TaskEditorView: View {
    @Bindable var task: TaskItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: \TaskList.sortIndex) private var lists: [TaskList]
    @Query(sort: \TaskItem.createdAt) private var allTasks: [TaskItem]
    @State private var newSubtask = ""
    @State private var confirmDelete = false
    @State private var focusLimitReached = false
    @State private var isDeleted = false

    private var calendar: Calendar { AppModel.calendar }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titel", text: $task.title, axis: .vertical)
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("editor.title")
                    TextField("Notizen", text: $task.notes, axis: .vertical)
                        .lineLimit(2...8)
                        .foregroundStyle(.secondary)
                }

                scheduleSection
                detailsSection
                subtasksSection

                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Aufgabe löschen", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(task.isDone ? "Erledigt" : "Aufgabe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        TaskActions.toggleCompletion(task, in: context, calendar: calendar)
                        app.tasksChanged()
                        if task.isDone { dismiss() }
                    } label: {
                        Label(task.isDone ? "Wieder öffnen" : "Erledigt", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("editor.done")
                }
            }
            .confirmationDialog("Aufgabe löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    isDeleted = true
                    TaskActions.delete(task, in: context)
                    app.tasksChanged()
                    dismiss()
                }
            }
            .alert("Fokus ist voll", isPresented: $focusLimitReached) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Es sind schon \(FocusRules.maximum) Aufgaben im Fokus.")
            }
        }
        .onDisappear(perform: finishEditing)
    }

    // MARK: Abschnitte

    private var scheduleSection: some View {
        Section {
            Toggle(isOn: hasDateBinding) {
                Label("Datum", systemImage: "calendar")
            }
            if task.dueDate != nil {
                DatePicker("Tag", selection: dayBinding, displayedComponents: .date)
                Toggle(isOn: hasTimeBinding) {
                    Label("Uhrzeit", systemImage: "clock")
                }
                if task.hasDueTime {
                    DatePicker("Uhrzeit", selection: timeBinding, displayedComponents: .hourAndMinute)
                }
                Picker(selection: reminderBinding) {
                    Text("Keine").tag(-1)
                    ForEach(TaskReminders.presets.map { $0.minutes }, id: \.self) { minutes in
                        Text(TaskReminders.label(forOffset: minutes)).tag(minutes)
                    }
                } label: {
                    Label("Erinnerung", systemImage: "bell")
                }
            }
            NavigationLink {
                RecurrenceEditorView(task: task)
            } label: {
                HStack {
                    Label("Wiederholen", systemImage: "repeat")
                    Spacer()
                    Text(task.recurrence?.summary(calendar: calendar) ?? "Nie")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } header: {
            Text("Termin")
        } footer: {
            if task.recurrence != nil, task.dueDate == nil {
                Text("Ohne Datum startet die Wiederholung beim Erledigen ab heute.")
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            Picker(selection: $task.list) {
                Text("Keine (Eingang)").tag(nil as TaskList?)
                ForEach(lists) { list in
                    Label(list.name, systemImage: list.symbol).tag(Optional(list))
                }
            } label: {
                Label("Liste", systemImage: "list.bullet")
            }
            Picker(selection: $task.priority) {
                Text("Keine").tag(0)
                Text("Niedrig !").tag(1)
                Text("Mittel !!").tag(2)
                Text("Hoch !!!").tag(3)
            } label: {
                Label("Priorität", systemImage: "exclamationmark.circle")
            }
            Toggle(isOn: $task.isFlagged) {
                Label("Markiert", systemImage: "flag")
            }
            Toggle(isOn: focusBinding) {
                Label("Fokus heute", systemImage: "scope")
            }
        }
    }

    private var subtasksSection: some View {
        Section {
            ForEach(task.sortedSubtasks) { subtask in
                SubtaskRow(subtask: subtask)
            }
            .onDelete { offsets in
                let items = task.sortedSubtasks
                for index in offsets {
                    context.delete(items[index])
                }
                TaskActions.save(context)
            }
            HStack {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
                TextField("Unteraufgabe hinzufügen", text: $newSubtask)
                    .submitLabel(.next)
                    .onSubmit {
                        TaskActions.addSubtask(titled: newSubtask, to: task, in: context)
                        newSubtask = ""
                    }
            }
        } header: {
            let progress = task.subtaskProgress
            Text(progress.total > 0 ? "Unteraufgaben (\(progress.done)/\(progress.total))" : "Unteraufgaben")
        }
    }

    // MARK: Bindungen

    private var hasDateBinding: Binding<Bool> {
        Binding(
            get: { task.dueDate != nil },
            set: { isOn in
                if isOn {
                    task.dueDate = calendar.startOfDay(for: .now)
                    task.hasDueTime = false
                } else {
                    task.dueDate = nil
                    task.hasDueTime = false
                    task.reminderOffsets = []
                }
            }
        )
    }

    private var dayBinding: Binding<Date> {
        Binding(
            get: { task.dueDate ?? .now },
            set: { newDay in
                if task.hasDueTime, let due = task.dueDate {
                    task.dueDate = calendar.combiningDay(newDay, timeOf: due)
                } else {
                    task.dueDate = calendar.startOfDay(for: newDay)
                }
            }
        )
    }

    private var hasTimeBinding: Binding<Bool> {
        Binding(
            get: { task.hasDueTime },
            set: { isOn in
                let day = calendar.startOfDay(for: task.dueDate ?? .now)
                task.hasDueTime = isOn
                if isOn {
                    task.dueDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)
                    let offset = UserDefaults.standard.object(forKey: SettingsKeys.defaultReminderOffset) as? Int ?? 0
                    if task.reminderOffsets.isEmpty, offset >= 0 {
                        task.reminderOffsets = [offset]
                    }
                } else {
                    task.dueDate = day
                }
            }
        )
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { task.dueDate ?? .now },
            set: { newTime in
                let day = task.dueDate ?? .now
                task.dueDate = calendar.combiningDay(day, timeOf: newTime)
            }
        )
    }

    private var reminderBinding: Binding<Int> {
        Binding(
            get: { task.reminderOffsets.first ?? -1 },
            set: { task.reminderOffsets = $0 >= 0 ? [$0] : [] }
        )
    }

    private var focusBinding: Binding<Bool> {
        Binding(
            get: { task.facts.isFocus(on: .now, calendar: calendar) },
            set: { _ in
                focusLimitReached = !TaskActions.toggleFocus(task, allTasks: allTasks, in: context, calendar: calendar)
            }
        )
    }

    // MARK: Abschluss

    private func finishEditing() {
        guard !isDeleted else { return }
        if task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            TaskActions.delete(task, in: context)
        } else {
            TaskActions.save(context)
        }
        app.tasksChanged()
    }
}

struct SubtaskRow: View {
    @Bindable var subtask: Subtask
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack {
            Button {
                subtask.isDone.toggle()
                TaskActions.save(context)
            } label: {
                Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(subtask.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(subtask.isDone ? "Unteraufgabe erledigt" : "Unteraufgabe abhaken")
            .sensoryFeedback(.selection, trigger: subtask.isDone)
            TextField("Unteraufgabe", text: $subtask.title)
                .strikethrough(subtask.isDone)
                .foregroundStyle(subtask.isDone ? Color.secondary : Color.primary)
        }
    }
}

/// Wiederholung auswählen: Vorlagen oder eigene Regel.
struct RecurrenceEditorView: View {
    @Bindable var task: TaskItem

    private enum Preset: String, CaseIterable, Identifiable {
        case none = "Nie"
        case daily = "Täglich"
        case workdays = "Werktags"
        case weekly = "Wöchentlich"
        case biweekly = "Alle 2 Wochen"
        case monthly = "Monatlich"
        case yearly = "Jährlich"

        var id: String { rawValue }

        func rule(monthDay: Int?) -> RecurrenceRule? {
            switch self {
            case .none: nil
            case .daily: .daily
            case .workdays: .workdays
            case .weekly: .weekly
            case .biweekly: .biweekly
            case .monthly: RecurrenceRule(frequency: .monthly, monthDay: monthDay)
            case .yearly: .yearly
            }
        }
    }

    private var calendar: Calendar { AppModel.calendar }

    var body: some View {
        Form {
            Section {
                ForEach(Preset.allCases) { preset in
                    Button {
                        task.recurrence = preset.rule(monthDay: task.dueDate.map { calendar.component(.day, from: $0) })
                    } label: {
                        HStack {
                            Text(preset.rawValue)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if matches(preset) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }

            Section {
                Stepper(value: intervalBinding, in: 1...365) {
                    Text("Alle \(task.recurrence?.interval ?? 1) \(unitName)")
                }
                Picker("Einheit", selection: frequencyBinding) {
                    Text("Tage").tag(RecurrenceRule.Frequency.daily)
                    Text("Wochen").tag(RecurrenceRule.Frequency.weekly)
                    Text("Monate").tag(RecurrenceRule.Frequency.monthly)
                    Text("Jahre").tag(RecurrenceRule.Frequency.yearly)
                }
                Toggle("Ab Erledigung zählen", isOn: afterCompletionBinding)
                if task.recurrence?.frequency == .weekly, task.recurrence?.mode == .fixed {
                    weekdayPicker
                }
            } header: {
                Text("Eigene Regel")
            } footer: {
                Text("„Ab Erledigung zählen“: Der nächste Termin richtet sich danach, wann du erledigt hast, z. B. „Bettwäsche 7 Tage nach dem letzten Wechsel“.")
            }
        }
        .navigationTitle("Wiederholen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func matches(_ preset: Preset) -> Bool {
        guard let rule = task.recurrence else { return preset == .none }
        guard let presetRule = preset.rule(monthDay: rule.monthDay) else { return false }
        return presetRule == rule
    }

    private var unitName: String {
        let plural = (task.recurrence?.interval ?? 1) != 1
        switch task.recurrence?.frequency ?? .daily {
        case .daily: return plural ? "Tage" : "Tag"
        case .weekly: return plural ? "Wochen" : "Woche"
        case .monthly: return plural ? "Monate" : "Monat"
        case .yearly: return plural ? "Jahre" : "Jahr"
        }
    }

    private var currentRule: RecurrenceRule {
        task.recurrence ?? RecurrenceRule(frequency: .daily)
    }

    private var intervalBinding: Binding<Int> {
        Binding(
            get: { currentRule.interval },
            set: { value in
                var rule = currentRule
                rule.interval = max(1, value)
                task.recurrence = rule
            }
        )
    }

    private var frequencyBinding: Binding<RecurrenceRule.Frequency> {
        Binding(
            get: { currentRule.frequency },
            set: { frequency in
                var rule = currentRule
                rule.frequency = frequency
                if frequency != .weekly { rule.weekdays = [] }
                if frequency == .monthly {
                    rule.monthDay = task.dueDate.map { calendar.component(.day, from: $0) }
                } else {
                    rule.monthDay = nil
                }
                task.recurrence = rule
            }
        )
    }

    private var afterCompletionBinding: Binding<Bool> {
        Binding(
            get: { currentRule.mode == .afterCompletion },
            set: { isOn in
                var rule = currentRule
                rule.mode = isOn ? .afterCompletion : .fixed
                if isOn { rule.weekdays = [] }
                task.recurrence = rule
            }
        )
    }

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(GermanCalendar.weekdayOrder, id: \.self) { weekday in
                let selected = currentRule.weekdays.contains(weekday)
                Button {
                    var weekdays = Set(currentRule.weekdays)
                    if selected { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
                    let rule = currentRule
                    task.recurrence = RecurrenceRule(
                        frequency: .weekly, interval: rule.interval, weekdays: Array(weekdays),
                        mode: rule.mode, endDate: rule.endDate
                    )
                } label: {
                    Text(GermanCalendar.shortWeekdays[weekday - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(
                            selected ? Color.accentColor : Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension Calendar {
    /// Tag von `day` mit Uhrzeit von `timeSource`.
    func combiningDay(_ day: Date, timeOf timeSource: Date) -> Date {
        let time = dateComponents([.hour, .minute], from: timeSource)
        return date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? day
    }
}
