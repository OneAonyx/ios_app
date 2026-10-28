import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Tages-Checkliste fürs Arzt-Tagebuch mit Schnellknöpfen.
struct DiaryChecklist: View {
    let now: Date
    /// Knöpfe „+ Schmerz“, „+ Beschwerde“, „+ Bewegung“ (auf „Heute“ übernimmt das „Schnell erfassen“).
    var showsAddButtons = true
    /// Auf „Heute“: mit Überschrift, und ist alles eingetragen, nur eine Zeile.
    var compactWhenComplete = false
    @State private var expanded = false

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    // Abfragen nur für heute, damit die Liste nach jeder Änderung neu rechnet,
    // ohne bei Jahren an Daten alles zu laden.
    @Query private var meals: [MealEntry]
    @Query private var symptoms: [SymptomEntry]
    @Query private var pains: [PainEntry]
    @Query private var activities: [ActivityEntry]
    @Query private var days: [DiaryDay]
    @Query private var sessions: [WorkoutSession]
    @Query private var checkIns: [DailyCheckIn]
    @Query private var doses: [DoseLog]

    init(now: Date, showsAddButtons: Bool = true, compactWhenComplete: Bool = false) {
        self.now = now
        self.showsAddButtons = showsAddButtons
        self.compactWhenComplete = compactWhenComplete
        let start = AppModel.calendar.startOfDay(for: now)
        let end = AppModel.calendar.date(byAdding: .day, value: 1, to: start) ?? now
        _meals = Query(filter: #Predicate<MealEntry> { $0.date >= start && $0.date < end })
        _symptoms = Query(filter: #Predicate<SymptomEntry> { $0.date >= start && $0.date < end })
        _pains = Query(filter: #Predicate<PainEntry> { $0.date >= start && $0.date < end })
        _activities = Query(filter: #Predicate<ActivityEntry> { $0.date >= start && $0.date < end })
        _days = Query(filter: #Predicate<DiaryDay> { $0.day >= start && $0.day < end })
        _sessions = Query(filter: #Predicate<WorkoutSession> { $0.startedAt >= start && $0.startedAt < end })
        _checkIns = Query(filter: #Predicate<DailyCheckIn> { $0.day >= start && $0.day < end })
        _doses = Query(filter: #Predicate<DoseLog> { $0.createdAt >= start })
    }

    var body: some View {
        let calendar = AppModel.calendar
        let _ = meals.count + symptoms.count + pains.count + activities.count + days.count + sessions.count + checkIns.count + doses.count
        let facts = DiaryActions.today(now: now, calendar: calendar, in: context)
        let items = DiaryCheck.items(facts)
        if compactWhenComplete, items.allSatisfy(\.isDone), !expanded {
            Button {
                withAnimation(.snappy) { expanded = true }
            } label: {
                HStack(spacing: Spacing.s) {
                    Label("Tagebuch heute vollständig", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if compactWhenComplete {
                SectionHeader("Tagebuch heute", systemImage: "stethoscope", tint: ModuleAccent.health)
            }
            FlowLayout(spacing: Spacing.xs, lineSpacing: Spacing.xs) {
                ForEach(items) { item in
                    Button {
                        open(item.kind)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isDone ? Color.green : Color.secondary)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.kind.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(item.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.tagwerkPage, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                        .foregroundStyle(Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.kind.title): \(item.detail)")
                    .accessibilityIdentifier("diary.item.\(item.kind.rawValue)")
                }
            }
            FlowLayout(spacing: Spacing.xs, lineSpacing: Spacing.xs) {
                if facts.symptoms + facts.pains == 0 {
                    ToggleChip(title: "Keine Beschwerden", isOn: facts.symptomFree, tint: .green) {
                        DiaryActions.setSymptomFree(!facts.symptomFree, on: now, calendar: calendar, in: context)
                        app.diaryChanged()
                    }
                    .accessibilityIdentifier("diary.symptomFree")
                }
                if showsAddButtons {
                    action("Schmerz", "plus", id: "diary.pain") { app.openPainEntry() }
                    action("Beschwerde", "plus", id: "diary.symptom") { app.openSymptomEntry() }
                    action("Bewegung", "plus", id: "diary.activity") { app.openActivityEntry() }
                }
                if facts.activities + facts.gymSessions == 0 {
                    ToggleChip(title: "Ruhetag", isOn: facts.restDay, tint: .green) {
                        DiaryActions.setRestDay(!facts.restDay, on: now, calendar: calendar, in: context)
                        app.diaryChanged()
                    }
                    .accessibilityIdentifier("diary.restDay")
                }
            }
        }
        }
    }

    private func action(_ title: String, _ symbol: String, id: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ModuleAccent.health.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func open(_ kind: DiaryItem.Kind) {
        switch kind {
        case .meals: app.logMeal()
        case .symptoms: app.openSymptomEntry()
        case .activity: app.openActivityEntry()
        case .medications: app.openMedications()
        case .checkIn: app.openCheckIn()
        }
    }
}

/// Karte auf „Heute“: was fürs Tagebuch heute noch fehlt. Ist alles da, nur eine Zeile.
struct DiaryTodayCard: View {
    let now: Date

    var body: some View {
        Card {
            DiaryChecklist(now: now, showsAddButtons: false, compactWhenComplete: true)
        }
        .accessibilityIdentifier("today.diary")
    }
}

/// Karte im Tab „Gesundheit“: Tagebuch, Schmerzen, Bewegung, Arztbericht.
struct DiaryHealthCard: View {
    let now: Date

    @Environment(\.modelContext) private var context
    // Nur die letzten 7 Tage bzw. die laufende Woche laden.
    @Query private var pains: [PainEntry]
    @Query private var activities: [ActivityEntry]
    @Query private var sessions: [WorkoutSession]

    init(now: Date) {
        self.now = now
        let weekStart = AgendaBuilder.startOfWeek(containing: now, calendar: AppModel.calendar)
        let since = min(weekStart, now.addingTimeInterval(-7 * 86_400))
        _pains = Query(filter: #Predicate<PainEntry> { $0.date >= since }, sort: \PainEntry.date, order: .reverse)
        _activities = Query(filter: #Predicate<ActivityEntry> { $0.date >= since })
        _sessions = Query(filter: #Predicate<WorkoutSession> { $0.startedAt >= since })
    }

    var body: some View {
        let calendar = AppModel.calendar
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let recentPains = pains.filter { $0.date >= weekAgo }
        let _ = activities.count + sessions.count
        let weekStart = AgendaBuilder.startOfWeek(containing: now, calendar: calendar)
        let week = ActivityStats.weeks(
            DiaryActions.activityFacts(from: weekStart, to: now.addingTimeInterval(1), in: context),
            from: weekStart, to: now.addingTimeInterval(1), calendar: calendar
        ).last
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader("Arzt-Tagebuch", systemImage: "stethoscope", tint: ModuleAccent.health)
                DiaryChecklist(now: now)
                Divider()
                NavigationLink {
                    PainHistoryView()
                } label: {
                    DiaryLinkRow(
                        title: "Schmerzen",
                        detail: recentPains.isEmpty
                            ? "In den letzten 7 Tagen keine"
                            : "7 Tage: \(recentPains.count)×, höchstens \(recentPains.map(\.intensity).max() ?? 0)/10",
                        systemImage: "figure.stand",
                        tint: .red
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("health.pains")
                NavigationLink {
                    ActivityHistoryView()
                } label: {
                    DiaryLinkRow(
                        title: "Bewegung",
                        detail: "Diese Woche \(week?.minutes ?? 0) Min. · \(week?.weightedMinutes ?? 0) von 150 fürs WHO-Ziel",
                        systemImage: "figure.walk",
                        tint: .green
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("health.activities")
                NavigationLink {
                    DoctorReportView()
                } label: {
                    DiaryLinkRow(title: "Arztbericht", detail: "PDF mit allem, was du erfasst hast, Tag für Tag", systemImage: "doc.richtext", tint: .blue)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("health.report")
            }
        }
    }
}

private struct DiaryLinkRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: Spacing.s) {
            IconBadge(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
