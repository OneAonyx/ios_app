import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Schnellerfassung: ein Satz genügt, z. B. „morgen 10 Uhr Zahnarzt !! #Arbeit“.
struct QuickAddView: View {
    let presetList: TaskList?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Environment(CalendarService.self) private var calendarService
    @AppStorage(SettingsKeys.defaultReminderOffset) private var defaultReminderOffset = 0
    @State private var text = ""
    @State private var addAsEvent = false
    @State private var confirmation: String?
    @State private var errorMessage: String?
    @State private var addedCount = 0
    @FocusState private var isFocused: Bool

    private var entry: QuickEntry {
        QuickEntryParser(calendar: AppModel.calendar).parse(text, now: .now)
    }

    var body: some View {
        let current = self.entry
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.m) {
                TextField("Was steht an?", text: $text)
                    .font(.title3)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit { add(current) }
                    .padding(Spacing.s)
                    .background(Color.tagwerkCard, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    .accessibilityIdentifier("quickadd.field")

                if current.chips.isEmpty && presetList == nil {
                    hints
                } else {
                    chips(for: current)
                }

                if current.hasTime && current.recurrence == nil && calendarService.canRead {
                    Toggle(isOn: $addAsEvent) {
                        Label("Als Termin in den Kalender", systemImage: "calendar.badge.plus")
                    }
                    .font(.subheadline)
                }

                if let confirmation {
                    Label(confirmation, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.m)
            .background(Color.tagwerkPage)
            // Kein Titel: Neben „Abbrechen“ und „Hinzufügen“ würde er abgeschnitten,
            // und das Textfeld sagt schon, worum es geht.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(addedCount > 0 ? "Fertig" : "Abbrechen") { dismiss() }
                        .accessibilityIdentifier("quickadd.close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") { add(current) }
                        .disabled(current.title.isEmpty)
                        .accessibilityIdentifier("quickadd.add")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        openDetails(current)
                    } label: {
                        Label("Mit Details anlegen", systemImage: "slider.horizontal.3")
                    }
                    .disabled(current.title.isEmpty)
                }
            }
            .sensoryFeedback(.success, trigger: addedCount)
        }
        .presentationDetents([.medium, .large])
        .onAppear { isFocused = true }
    }

    private var hints: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Schreib einfach los, Orbit erkennt zum Beispiel:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(["morgen 10 Uhr Zahnarzt", "jeden Montag Müll rausbringen", "Freitag Steuer !! #Arbeit", "in 2 Stunden Wäsche aufhängen"], id: \.self) { example in
                Button {
                    text = example
                } label: {
                    Label(example, systemImage: "text.cursor")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func chips(for entry: QuickEntry) -> some View {
        FlowLayout(spacing: Spacing.xs, lineSpacing: Spacing.xs) {
            ForEach(entry.chips, id: \.self) { chip in
                chipView(symbol: symbol(for: chip.kind), text: chip.label, tint: tint(for: chip.kind))
            }
            if entry.listName == nil, let presetList {
                chipView(symbol: presetList.symbol, text: presetList.name, tint: ListColor.color(named: presetList.colorName))
            }
        }
    }

    private func chipView(symbol: String, text: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 6)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private func symbol(for kind: QuickEntry.Chip.Kind) -> String {
        switch kind {
        case .date: "calendar"
        case .time: "clock"
        case .recurrence: "repeat"
        case .priority: "exclamationmark.circle"
        case .list: "list.bullet"
        }
    }

    private func tint(for kind: QuickEntry.Chip.Kind) -> Color {
        switch kind {
        case .date, .time: ModuleAccent.calendar
        case .recurrence: .purple
        case .priority: .orange
        case .list: ModuleAccent.tasks
        }
    }

    // MARK: Anlegen

    private func add(_ entry: QuickEntry) {
        guard !entry.title.isEmpty else { return }
        errorMessage = nil
        if addAsEvent, entry.hasTime, let start = entry.dueDate {
            do {
                try calendarService.createEvent(title: entry.title, start: start, end: start.addingTimeInterval(3_600), isAllDay: false)
                withAnimation { confirmation = "Termin „\(entry.title)“ eingetragen" }
            } catch {
                errorMessage = "Termin konnte nicht angelegt werden: \(error.localizedDescription)"
                return
            }
        } else {
            TaskActions.create(
                from: entry,
                presetList: presetList,
                defaultReminderOffset: defaultReminderOffset >= 0 ? defaultReminderOffset : nil,
                in: context
            )
            app.tasksChanged()
            withAnimation { confirmation = "„\(entry.title)“ hinzugefügt" }
        }
        addedCount += 1
        text = ""
        addAsEvent = false
        isFocused = true
    }

    private func openDetails(_ entry: QuickEntry) {
        guard !entry.title.isEmpty else { return }
        let task = TaskActions.create(
            from: entry,
            presetList: presetList,
            defaultReminderOffset: defaultReminderOffset >= 0 ? defaultReminderOffset : nil,
            in: context
        )
        app.tasksChanged()
        dismiss()
        // Editor öffnen, nachdem dieses Sheet geschlossen ist.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            app.editingTask = task
        }
    }
}
