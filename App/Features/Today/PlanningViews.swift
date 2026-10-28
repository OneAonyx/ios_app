import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Tag abschließen: Offenes auf morgen ziehen oder abhaken, dann Top 3 für morgen.
struct DayClosingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var tasks: [TaskItem] = []
    @State private var writingJournal = false

    var body: some View {
        let calendar = AppModel.calendar
        NavigationStack {
            List {
                Section {
                    Text("Was heute offen blieb, ziehst du mit einem Tipp auf morgen oder hakst es ab. Danach legst du die Top 3 für morgen fest.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if tasks.isEmpty {
                        Label("Nichts mehr offen für heute.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                    ForEach(tasks) { task in
                        HStack(spacing: Spacing.s) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.body.weight(.semibold))
                                if let due = task.dueDate {
                                    Text(DueFormatter.dayLabel(for: due, now: .now, calendar: calendar))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: Spacing.xs)
                            Button("Morgen") {
                                TaskActions.moveToTomorrow(task, in: context, calendar: calendar)
                                changed()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            Button {
                                TaskActions.toggleCompletion(task, in: context, calendar: calendar)
                                changed()
                            } label: {
                                Image(systemName: "checkmark")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.small)
                            .accessibilityLabel("\(task.title) erledigt")
                        }
                    }
                    if tasks.count > 1 {
                        Button {
                            PlanningActions.moveAllToTomorrow(calendar: calendar, in: context)
                            changed()
                        } label: {
                            Label("Alle \(tasks.count) auf morgen", systemImage: "arrow.turn.down.right")
                        }
                        .accessibilityIdentifier("closing.moveAll")
                    }
                } header: {
                    Text("Noch offen")
                }

                Section {
                    Button {
                        writingJournal = true
                    } label: {
                        Label("Top 3 für morgen und Tagebuch", systemImage: "square.and.pencil")
                    }
                    .accessibilityIdentifier("closing.journal")
                } header: {
                    Text("Morgen")
                } footer: {
                    Text("Die Top 3 stehen morgen früh als Fokus auf „Heute“ und im Morgen-Briefing.")
                }
            }
            .navigationTitle("Tag abschließen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("closing.done")
                }
            }
            .sheet(isPresented: $writingJournal) {
                JournalEditorView()
            }
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        tasks = PlanningActions.openToday(calendar: AppModel.calendar, in: context)
    }

    private func changed() {
        app.tasksChanged()
        withAnimation { reload() }
    }
}

/// Woche planen (sonntags): Fokus der Woche, Trainingstage, Ausblick, Essen.
struct WeekPlanningView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKeys.weekFocus) private var storedFocus = ""
    @State private var focus = ""
    @State private var weekdays: Set<Int> = []
    @State private var loaded = false

    /// Montag zuerst (Wochentag 2 … 7, dann 1 = Sonntag).
    private let order = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        let calendar = AppModel.calendar
        // Sonntags plant man die kommende Woche.
        let reference = calendar.component(.weekday, from: .now) == 1 ? calendar.date(byAdding: .day, value: 1, to: .now) ?? .now : .now
        let plan = TrainingActions.activePlan(in: context)
        NavigationStack {
            List {
                Section {
                    TextField("z. B. früher ins Bett, 5× Gym, Steuer fertig", text: $focus, axis: .vertical)
                        .lineLimit(1...3)
                        .accessibilityIdentifier("week.focus")
                } header: {
                    Text("Fokus der Woche")
                } footer: {
                    Text("Steht die Woche über oben auf „Heute“ und im Morgen-Briefing.")
                }

                if plan != nil {
                    Section {
                        HStack(spacing: 6) {
                            ForEach(order, id: \.self) { weekday in
                                let selected = weekdays.contains(weekday)
                                Button {
                                    if selected { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
                                } label: {
                                    Text(GermanCalendar.shortWeekdays[weekday - 1])
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 40)
                                        .background(selected ? ModuleAccent.training : Color.tagwerkPage, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                                        .foregroundStyle(selected ? Color.white : Color.primary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(GermanCalendar.longWeekdays[weekday - 1])
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, Spacing.xxs)
                    } header: {
                        Text("Trainingstage")
                    } footer: {
                        Text("\(weekdays.count) Tage. Für die Erinnerung am Trainingstag und das Briefing; die Reihenfolge der Einheiten bleibt.")
                    }
                }

                Section {
                    NavigationLink {
                        WeekView()
                    } label: {
                        Label("Wochenansicht mit Terminen und Aufgaben", systemImage: "calendar")
                    }
                    NavigationLink {
                        MealPlanView()
                    } label: {
                        Label("Wochen-Essensplan", systemImage: "calendar.day.timeline.left")
                    }
                    NavigationLink {
                        ShoppingListView()
                    } label: {
                        Label("Einkaufsliste", systemImage: "cart")
                    }
                } header: {
                    Text("Woche ab \(WeeklyReview.dayMonth(AgendaBuilder.startOfWeek(containing: reference, calendar: calendar), calendar: calendar))")
                }
            }
            .navigationTitle("Woche planen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        save(plan: plan, reference: reference)
                        dismiss()
                    }
                    .accessibilityIdentifier("week.done")
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                focus = WeekFocus.current(storedFocus, now: reference, calendar: calendar) ?? ""
                weekdays = Set(plan?.preferredWeekdays ?? [])
            }
        }
    }

    private func save(plan: WorkoutPlan?, reference: Date) {
        storedFocus = WeekFocus.store(focus, now: reference, calendar: AppModel.calendar)
        if let plan, Set(plan.preferredWeekdays) != weekdays {
            plan.preferredWeekdays = weekdays.sorted()
            TrainingActions.save(context)
            app.trainingChanged()
        }
        app.tasksChanged()
    }
}

/// Morgen-Briefing an/aus und Uhrzeit (Einstellungen → Erinnerungen).
struct BriefingSettings: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKeys.briefingMinute) private var minute = MorningBriefing.standardMinute

    var body: some View {
        Toggle("Morgen-Briefing", isOn: Binding(
            get: { minute >= 0 },
            set: { minute = $0 ? MorningBriefing.standardMinute : -1 }
        ))
        .accessibilityIdentifier("settings.briefing")
        .onChange(of: minute) { _, _ in app.tasksChanged() }
        if minute >= 0 {
            DatePicker("Uhrzeit", selection: Binding(get: time, set: setTime), displayedComponents: .hourAndMinute)
        }
    }

    private func time() -> Date {
        AppModel.calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
    }

    private func setTime(_ date: Date) {
        let parts = AppModel.calendar.dateComponents([.hour, .minute], from: date)
        minute = (parts.hour ?? 7) * 60 + (parts.minute ?? 15)
    }
}
