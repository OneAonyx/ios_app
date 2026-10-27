import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit
import TipKit

/// Planer → Leben: Routinen, Gewohnheiten, Verträge und Fristen, Geburtstage, Tagebuch, Haushalt.
struct LifeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: [SortDescriptor(\Habit.sortIndex), SortDescriptor(\Habit.createdAt)]) private var habits: [Habit]
    @Query(sort: \Contract.name) private var contracts: [Contract]
    @Query(sort: \Birthday.name) private var birthdays: [Birthday]
    @Query(sort: \JournalEntry.day, order: .reverse) private var journal: [JournalEntry]
    @State private var addingHabit = false
    @State private var writing = false
    @State private var addedChore: String?

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            content(now: timeline.date)
        }
        .background(Color.tagwerkPage)
        .sheet(isPresented: $addingHabit) {
            HabitTemplatePicker()
        }
        .sheet(isPresented: $writing) {
            JournalEditorView()
        }
    }

    private func content(now: Date) -> some View {
        let calendar = AppModel.calendar
        let active = habits.filter { !$0.isArchived }
        let dueToday = active.filter { $0.schedule.isDue(on: now, calendar: calendar) }
        let totals = ContractLogic.totals(contracts.map(\.fact))
        let attention = contracts.filter { ContractLogic.status($0.fact, now: now, calendar: calendar).needsAttention }
        let upcoming = birthdays
            .filter { BirthdayLogic.daysUntil($0.fact, now: now, calendar: calendar) <= 60 }
            .sorted { BirthdayLogic.daysUntil($0.fact, now: now, calendar: calendar) < BirthdayLogic.daysUntil($1.fact, now: now, calendar: calendar) }
        let todayEntry = journal.first { calendar.isDate($0.day, inSameDayAs: now) }

        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                TipView(LifeTip())
                // Routinen und Gewohnheiten
                Card {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        HStack {
                            SectionHeader("Routinen & Gewohnheiten", systemImage: "repeat", tint: .indigo)
                            Button {
                                addingHabit = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                            }
                            .tint(.indigo)
                            .accessibilityLabel("Routine oder Gewohnheit hinzufügen")
                            .accessibilityIdentifier("life.habit.add")
                        }
                        if active.isEmpty {
                            Text("Morgen- und Abendroutine, Dehnen, Lesen … Starte mit einer Vorlage.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else if dueToday.isEmpty {
                            Text("Heute steht nichts an.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(dueToday) { habit in
                            HabitTodayRow(habit: habit, now: now)
                        }
                        if !active.isEmpty {
                            NavigationLink {
                                HabitsListView()
                            } label: {
                                Label("Alle \(active.count) mit Serien und Verlauf", systemImage: "chart.bar.xaxis")
                                    .font(.subheadline)
                            }
                            .accessibilityIdentifier("life.habits")
                        }
                    }
                }

                // Verträge und Fristen
                NavigationLink {
                    ContractsListView()
                } label: {
                    Card {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            HStack {
                                SectionHeader("Verträge & Fristen", systemImage: "doc.text", tint: ModuleAccent.tasks)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            if contracts.isEmpty {
                                Text("Abos, Verträge, Versicherungen, Ausweis und TÜV: Orbit erinnert an Kündigungsfristen und Ablaufdaten.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                if totals.monthly > 0 {
                                    Text("\(ContractLogic.euro(totals.monthly)) Fixkosten im Monat")
                                        .font(.headline)
                                }
                                if attention.isEmpty {
                                    Text("Keine Frist in den nächsten Wochen.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(attention.prefix(3)) { contract in
                                    ContractRow(contract: contract, now: now, calendar: calendar)
                                }
                            }
                        }
                        .foregroundStyle(Color.primary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("life.contracts")

                // Geburtstage
                NavigationLink {
                    BirthdaysListView()
                } label: {
                    Card {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            HStack {
                                SectionHeader("Geburtstage", systemImage: "gift", tint: .pink)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            if upcoming.isEmpty {
                                Text(birthdays.isEmpty ? "Trag Geburtstage ein oder übernimm sie aus deinen Kontakten." : "In den nächsten 60 Tagen keiner.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(upcoming.prefix(3)) { birthday in
                                BirthdayRow(birthday: birthday, now: now)
                            }
                        }
                        .foregroundStyle(Color.primary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("life.birthdays")

                // Tagebuch
                Card {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        HStack {
                            SectionHeader("Tagebuch", systemImage: "book.closed", tint: .brown)
                            NavigationLink {
                                JournalListView()
                            } label: {
                                Text("Alle")
                                    .font(.subheadline)
                            }
                        }
                        Text(todayEntry?.prompt ?? JournalPrompts.prompt(for: now, calendar: calendar))
                            .font(.headline)
                        if let todayEntry, !todayEntry.answer.isEmpty {
                            Text(todayEntry.answer)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        Button {
                            writing = true
                        } label: {
                            Label(todayEntry == nil ? "Schreiben" : "Weiterschreiben", systemImage: "square.and.pencil")
                                .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.bordered)
                        .tint(.brown)
                        .accessibilityIdentifier("life.journal")
                    }
                }

                // Haushalt
                Card {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader("Haushalt", systemImage: "house", tint: .teal)
                        Text("Wiederkehrende Aufgaben, die nach dem Erledigen neu starten.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: Spacing.xs) {
                            ForEach(LifeTemplates.chores) { chore in
                                Button {
                                    LifeActions.addChore(chore, calendar: calendar, in: context)
                                    addedChore = chore.title
                                    app.tasksChanged()
                                } label: {
                                    Label("\(chore.title) · alle \(chore.everyDays) T.", systemImage: chore.symbol)
                                        .font(.subheadline)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.teal.opacity(0.12), in: Capsule())
                                        .foregroundStyle(Color.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if let addedChore {
                            Label("„\(addedChore)“ steht ab heute in deinen Aufgaben.", systemImage: "checkmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xl)
        }
    }
}

// MARK: - Karten für „Heute“

/// Routinen und Gewohnheiten, die jetzt dran sind (Tageszeit passt, noch nicht erledigt).
struct HabitsTodayCard: View {
    let now: Date

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: [SortDescriptor(\Habit.sortIndex), SortDescriptor(\Habit.createdAt)]) private var habits: [Habit]
    @Query private var logs: [HabitLog]

    var body: some View {
        let calendar = AppModel.calendar
        let today = calendar.startOfDay(for: now)
        let due = habits.filter { !$0.isArchived && $0.schedule.isDue(on: now, calendar: calendar) && $0.period.isCurrent(now: now, calendar: calendar) }
        let doneIDs = Set(logs.filter { calendar.isDate($0.day, inSameDayAs: today) }.compactMap { log -> String? in
            guard let habit = habits.first(where: { $0.stableID == log.habitID }) else { return nil }
            return habit.fact.isComplete(log.habitDay) ? habit.stableID : nil
        })
        let open = due.filter { !doneIDs.contains($0.stableID) }
        if !due.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack {
                        SectionHeader("Routinen", systemImage: "repeat", tint: .indigo)
                        Text("\(due.count - open.count) von \(due.count)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(open.isEmpty ? Color.green : Color.secondary)
                    }
                    if open.isEmpty {
                        Label("Alles erledigt für jetzt.", systemImage: "checkmark.seal.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                    ForEach(open.prefix(4)) { habit in
                        HabitTodayRow(habit: habit, now: now)
                    }
                }
            }
            .accessibilityIdentifier("today.habits")
        }
    }
}

/// Geburtstage in den nächsten 7 Tagen und anstehende Fristen.
struct LifeTodayCard: View {
    let now: Date

    @Environment(AppModel.self) private var app
    @Query(sort: \Contract.name) private var contracts: [Contract]
    @Query(sort: \Birthday.name) private var birthdays: [Birthday]

    var body: some View {
        let calendar = AppModel.calendar
        let soon = birthdays
            .filter { BirthdayLogic.daysUntil($0.fact, now: now, calendar: calendar) <= 7 }
            .sorted { BirthdayLogic.daysUntil($0.fact, now: now, calendar: calendar) < BirthdayLogic.daysUntil($1.fact, now: now, calendar: calendar) }
        let attention = contracts.filter { ContractLogic.status($0.fact, now: now, calendar: calendar).needsAttention }
        if !soon.isEmpty || !attention.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionHeader("Demnächst", systemImage: "calendar.badge.exclamationmark", tint: .pink)
                    ForEach(soon.prefix(3)) { birthday in
                        BirthdayRow(birthday: birthday, now: now)
                    }
                    ForEach(attention.prefix(3)) { contract in
                        ContractRow(contract: contract, now: now, calendar: calendar)
                    }
                    Button {
                        app.openLife()
                    } label: {
                        Text("Zu Leben")
                            .font(.subheadline)
                    }
                    .tint(.pink)
                }
            }
            .accessibilityIdentifier("today.life")
        }
    }
}

/// Abends ab 19 Uhr, solange heute noch nichts im Tagebuch steht.
struct JournalTodayCard: View {
    let now: Date

    @Query(sort: \JournalEntry.day, order: .reverse) private var journal: [JournalEntry]
    @State private var writing = false

    var body: some View {
        let calendar = AppModel.calendar
        let hasEntry = journal.contains { calendar.isDate($0.day, inSameDayAs: now) }
        if calendar.component(.hour, from: now) >= 19, !hasEntry {
            Card {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionHeader("Tagebuch", systemImage: "book.closed", tint: .brown)
                    Text(JournalPrompts.prompt(for: now, calendar: calendar))
                        .font(.headline)
                    Button {
                        writing = true
                    } label: {
                        Label("Schreiben und Top 3 für morgen", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                    .tint(.brown)
                }
            }
            .sheet(isPresented: $writing) {
                JournalEditorView()
            }
        }
    }
}
