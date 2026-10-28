import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Tab „Gesundheit“: Einnahmen heute, Bei Bedarf, Einnahmetreue, Vorrat, alle Medikamente, Beschwerden,
/// Einblicke (Befinden, Wochenrückblick, Arztbericht, Claude).
struct HealthView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: [SortDescriptor(\Medication.sortIndex), SortDescriptor(\Medication.name)]) private var medications: [Medication]
    @State private var extraIntake: Medication?
    @State private var refilling: Medication?
    @State private var notificationsAllowed = true

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.healthPath) {
            TimelineView(.everyMinute) { context in
                content(now: context.date)
            }
            .background(Color.tagwerkPage)
            .navigationTitle("Gesundheit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        app.isAddingMedication = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Medikament hinzufügen")
                    .accessibilityIdentifier("health.add")
                }
            }
            .navigationDestination(for: String.self) { stableID in
                if let medication = medications.first(where: { $0.stableID == stableID }) {
                    MedicationDetailView(medication: medication)
                }
            }
            .navigationDestination(for: HealthRoute.self) { route in
                switch route {
                case .painHistory: PainHistoryView()
                case .activityHistory: ActivityHistoryView()
                case .doctorReport: DoctorReportView()
                case .healthBridge: HealthBridgeView()
                case .symptomHistory: SymptomHistoryView()
                case .periodReview: PeriodReviewView()
                }
            }
            .sheet(item: $extraIntake) { medication in
                ExtraIntakeSheet(medication: medication)
            }
            .sheet(item: $refilling) { medication in
                RefillSheet(medication: medication)
            }
            .task {
                let allowed = await NotificationSetup.isAuthorized()
                notificationsAllowed = AppInfo.isUITesting || allowed
            }
        }
    }

    private func content(now: Date) -> some View {
        let calendar = AppModel.calendar
        let active = medications.filter(\.isActive)
        let scheduled = active.filter { $0.schedule.isScheduled }
        let asNeeded = active.filter { !$0.schedule.isScheduled }
        let paused = medications.filter { !$0.isActive }
        let today = DayDoses(medications: scheduled, day: now, now: now, calendar: calendar)
        let lowStock = active.compactMap { medication -> LowStockItem? in
            guard let forecast = medication.forecast(now: now, calendar: calendar), forecast.needsRefill else { return nil }
            return LowStockItem(medication: medication, forecast: forecast)
        }
        let needsReminders = scheduled.contains { $0.reminderStyle != .none }

        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                if medications.isEmpty {
                    EmptyMedicationsCard { app.isAddingMedication = true }
                } else {
                    if needsReminders && !notificationsAllowed {
                        NotificationHintCard {
                            Task { notificationsAllowed = (try? await NotificationSetup.requestAuthorization()) ?? false }
                        }
                    }
                    if !scheduled.isEmpty {
                        TodayDosesCard(today: today, now: now)
                    }
                    if !asNeeded.isEmpty {
                        AsNeededCard(medications: asNeeded, now: now) { extraIntake = $0 }
                    }
                    if !scheduled.isEmpty {
                        AdherenceWeekCard(medications: scheduled, now: now)
                    }
                    if !lowStock.isEmpty {
                        LowStockCard(items: lowStock) { refilling = $0 }
                    }
                    MedicationListCard(title: "Meine Medikamente", medications: active, now: now)
                    if !paused.isEmpty {
                        MedicationListCard(title: "Pausiert", medications: paused, now: now)
                    }
                }
                DiaryHealthCard(now: now)
                HealthBridgeCard(now: now)
                SymptomsHealthCard(now: now)
                InsightsHealthCard(now: now)
                Text("Orbit hilft beim Erinnern und Protokollieren und ersetzt keine ärztliche Beratung.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.xxs)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xl)
        }
    }
}

// MARK: - Karten

private struct EmptyMedicationsCard: View {
    let onAdd: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                IconBadge(systemImage: "pills.fill", tint: ModuleAccent.medication, size: 48)
                Text("Noch keine Medikamente")
                    .font(.title3.weight(.semibold))
                Text("Lege Medikamente und Nahrungsergänzung an, z. B. DAO-Enzym vor dem Essen. Orbit erinnert dich, zählt den Vorrat und zeigt, wie regelmäßig du sie nimmst.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action: onAdd) {
                    Label("Medikament hinzufügen", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ModuleAccent.medication)
                .accessibilityIdentifier("health.empty.add")
            }
        }
    }
}

private struct NotificationHintCard: View {
    let onAllow: () -> Void

    var body: some View {
        Card {
            HStack(spacing: Spacing.s) {
                IconBadge(systemImage: "bell.badge", tint: .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mitteilungen sind aus")
                        .font(.headline)
                    Text("Ohne Mitteilungen kann Orbit nicht an Einnahmen erinnern.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Erlauben", action: onAllow)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }
}

/// Alle geplanten Einnahmen von heute.
struct TodayDosesCard: View {
    let today: DayDoses
    let now: Date
    var title = "Heute"
    /// Erledigte Einnahmen zu einer Zeile zusammenfassen (auf „Heute“).
    var collapsesResolved = false

    @State private var showsResolved = false

    var body: some View {
        let resolved = today.items.filter { $0.entry.isResolved }
        let collapse = collapsesResolved && !showsResolved && !resolved.isEmpty && resolved.count < today.items.count
        let visible = collapse ? today.items.filter { !$0.entry.isResolved } : today.items
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    SectionHeader(title, systemImage: "pills", tint: ModuleAccent.medication)
                    if today.total > 0 {
                        Text("\(today.done) von \(today.total)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(today.done == today.total ? Color.green : Color.secondary)
                    }
                }
                if today.items.isEmpty {
                    Text("Heute sind keine Einnahmen geplant.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    if collapse {
                        Button {
                            withAnimation(.snappy) { showsResolved = true }
                        } label: {
                            Label(resolved.count == 1 ? "1 Einnahme erledigt" : "\(resolved.count) Einnahmen erledigt", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, Spacing.xxs)
                    }
                    ForEach(visible) { item in
                        DoseRow(entry: item.entry, medication: item.medication, now: now)
                    }
                }
            }
        }
    }
}

private struct AsNeededCard: View {
    let medications: [Medication]
    let now: Date
    let onTake: (Medication) -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader("Bei Bedarf", systemImage: "hand.tap", tint: ModuleAccent.medication)
                ForEach(medications) { medication in
                    let check = medication.asNeededCheck(now: now, calendar: AppModel.calendar)
                    HStack(spacing: Spacing.s) {
                        MedicationIcon(symbol: medication.symbol, colorName: medication.colorName, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(medication.displayName)
                                .lineLimit(2)
                            Text(statusText(check))
                                .font(.caption)
                                .foregroundStyle(check.isAllowed ? Color.secondary : Color.orange)
                        }
                        Spacer(minLength: 0)
                        Button("Nehmen") { onTake(medication) }
                            .buttonStyle(.bordered)
                            .tint(check.isAllowed ? ModuleAccent.medication : .orange)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private func statusText(_ check: AsNeededCheck) -> String {
        guard let next = check.nextAllowed else { return check.statusLine }
        return "\(check.statusLine) · \(AsNeededGuard.nextAllowedLabel(next, now: now, calendar: AppModel.calendar).replacingOccurrences(of: "Wieder", with: "wieder"))"
    }
}

/// Einnahmetreue der letzten 7 Tage über alle Medikamente.
private struct AdherenceWeekCard: View {
    let medications: [Medication]
    let now: Date

    var body: some View {
        let calendar = AppModel.calendar
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let end = calendar.endOfDayDate(for: today)
        let entries = medications.flatMap { $0.entries(from: start, to: end, now: now, calendar: calendar) }
        let summary = Adherence.summarize(entries)
        let days = Adherence.days(entries, from: start, days: 7, calendar: calendar)

        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader("Letzte 7 Tage", systemImage: "chart.bar.fill", tint: ModuleAccent.medication)
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(summary.percentLabel)
                        .font(.system(.title, design: .rounded, weight: .bold))
                    Text("genommen")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 0) {
                    ForEach(days) { day in
                        VStack(spacing: 4) {
                            Circle()
                                .fill(color(for: day.status))
                                .frame(width: 24, height: 24)
                                .overlay {
                                    if day.status == .pending || day.status == .none {
                                        Circle().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                                    }
                                }
                            Text(GermanCalendar.shortWeekdays[calendar.component(.weekday, from: day.date) - 1])
                                .font(.caption2)
                                .foregroundStyle(calendar.isDate(day.date, inSameDayAs: now) ? ModuleAccent.today : Color.secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                    }
                }
                if summary.missed + summary.skipped > 0 {
                    Text("\(summary.taken) genommen · \(summary.skipped) ausgelassen · \(summary.missed) verpasst")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func color(for status: DayAdherenceStatus) -> Color {
        switch status {
        case .complete: .green
        case .partial: .orange
        case .missed: .red
        case .pending: ModuleAccent.medication.opacity(0.25)
        case .none: .clear
        }
    }
}

private struct LowStockItem: Identifiable {
    let medication: Medication
    let forecast: StockForecast
    var id: String { medication.stableID }
}

private struct LowStockCard: View {
    let items: [LowStockItem]
    let onRefill: (Medication) -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader("Vorrat knapp", systemImage: "exclamationmark.triangle.fill", tint: .orange)
                ForEach(items) { item in
                    let medication = item.medication
                    let forecast = item.forecast
                    HStack(spacing: Spacing.s) {
                        MedicationIcon(symbol: medication.symbol, colorName: medication.colorName, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(medication.displayName)
                                .lineLimit(2)
                            Text([medication.stockText, forecast.rangeLabel(calendar: AppModel.calendar)].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Spacer(minLength: 0)
                        Button("Nachgefüllt") { onRefill(medication) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}

private struct MedicationListCard: View {
    let title: String
    let medications: [Medication]
    let now: Date

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionHeader(title, systemImage: "list.bullet", tint: ModuleAccent.medication)
                ForEach(medications) { medication in
                    NavigationLink(value: medication.stableID) {
                        MedicationSummaryRow(medication: medication, now: now)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("medication.\(medication.name)")
                    if medication.id != medications.last?.id {
                        Divider().padding(.leading, 48)
                    }
                }
            }
        }
    }
}

struct MedicationSummaryRow: View {
    let medication: Medication
    let now: Date

    var body: some View {
        HStack(spacing: Spacing.s) {
            MedicationIcon(symbol: medication.symbol, colorName: medication.colorName)
            VStack(alignment: .leading, spacing: 2) {
                Text(medication.displayName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(medication.isActive ? Color.primary : Color.secondary)
                    .lineLimit(2)
                Text(medication.schedule.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let stockText = medication.stockText {
                    Label(stockText, systemImage: "shippingbox")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
    }
}

/// Befinden, Wochenrückblick, Arztbericht und Claude.
private struct InsightsHealthCard: View {
    let now: Date

    @Environment(AppModel.self) private var app
    // Nur die letzten 7 Tage Check-ins laden.
    @Query private var checkIns: [DailyCheckIn]
    @Query(sort: \ClaudeExchange.createdAt, order: .reverse) private var exchanges: [ClaudeExchange]

    init(now: Date) {
        self.now = now
        let since = AppModel.calendar.date(byAdding: .day, value: -7, to: AppModel.calendar.startOfDay(for: now)) ?? now
        _checkIns = Query(filter: #Predicate<DailyCheckIn> { $0.day >= since }, sort: \DailyCheckIn.day, order: .reverse)
    }

    var body: some View {
        let calendar = AppModel.calendar
        let today = checkIns.first { calendar.isDate($0.day, inSameDayAs: now) }?.fact
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        let averages = CheckInAverages.compute(checkIns.filter { $0.day >= weekAgo }.map(\.fact))
        let weekStart = AgendaBuilder.startOfWeek(containing: now, calendar: calendar)
        let waiting = exchanges.filter { $0.status == .sent || $0.status == .answered }.count
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader("Einblicke", systemImage: "chart.line.uptrend.xyaxis", tint: ModuleAccent.health)
                Button {
                    app.openCheckIn()
                } label: {
                    InsightRow(
                        title: "Check-in heute",
                        detail: todayText(today),
                        systemImage: "heart.text.square",
                        tint: ModuleAccent.health
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("health.checkin")
                NavigationLink {
                    CheckInHistoryView()
                } label: {
                    InsightRow(
                        title: "Befinden",
                        detail: averages.days == 0 ? "Noch keine Check-ins" : "7 Tage: Stimmung Ø \(CheckInAverages.format(averages.mood)), Schlaf Ø \(CheckInAverages.format(averages.sleep))",
                        systemImage: "face.smiling",
                        tint: ModuleAccent.health
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("health.mood")
                NavigationLink {
                    WeeklyReviewView(weekStart: weekStart)
                } label: {
                    InsightRow(title: "Wochenrückblick", detail: WeeklyReview.title(weekStart: weekStart, calendar: calendar), systemImage: "calendar.badge.checkmark", tint: .purple)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("health.review")
                NavigationLink(value: HealthRoute.periodReview) {
                    InsightRow(title: "Monat und Jahr", detail: "Trends mit Vergleich zum Zeitraum davor", systemImage: "chart.xyaxis.line", tint: .indigo)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("health.periodReview")
                NavigationLink {
                    ClaudeHubView()
                } label: {
                    InsightRow(
                        title: "Claude",
                        detail: waiting > 0 ? (waiting == 1 ? "1 Anfrage offen" : "\(waiting) Anfragen offen") : "Plan, Lebensmittel, Rezepte, Muster",
                        systemImage: "sparkles",
                        tint: .purple
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("health.claude")
            }
        }
    }

    private func todayText(_ fact: CheckInFact?) -> String {
        guard let fact else { return "Noch offen" }
        let values = CheckInScale.allCases.compactMap { scale in fact.value(scale).map { "\(scale.emoji($0)) \(scale.title)" } }
        return values.isEmpty ? "Noch offen" : values.joined(separator: "  ")
    }
}

private struct InsightRow: View {
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

/// Beschwerden der letzten Tage mit Schnellzugriff auf Erfassung, Verlauf und Muster.
private struct SymptomsHealthCard: View {
    let now: Date

    @Environment(AppModel.self) private var app
    // Nur die letzten 7 Tage laden.
    @Query private var symptoms: [SymptomEntry]

    init(now: Date) {
        self.now = now
        let since = now.addingTimeInterval(-7 * 86_400)
        _symptoms = Query(filter: #Predicate<SymptomEntry> { $0.date >= since }, sort: \SymptomEntry.date, order: .reverse)
    }

    var body: some View {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let recent = symptoms.filter { $0.date >= weekAgo }
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    SectionHeader("Beschwerden", systemImage: "waveform.path.ecg", tint: ModuleAccent.health)
                    Button {
                        app.isAddingSymptom = true
                    } label: {
                        Label("Eintragen", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(ModuleAccent.health)
                    .accessibilityIdentifier("health.symptom.add")
                }
                if recent.isEmpty {
                    Text("In den letzten 7 Tagen keine Beschwerden eingetragen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recent.prefix(4)) { symptom in
                        SymptomRow(symptom: symptom, showsDate: true)
                    }
                }
                HStack(spacing: Spacing.xs) {
                    NavigationLink {
                        SymptomHistoryView()
                    } label: {
                        Label("Verlauf", systemImage: "list.bullet")
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                    NavigationLink {
                        PatternsView()
                    } label: {
                        Label("Muster", systemImage: "magnifyingglass.circle")
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("health.patterns")
                }
                .tint(ModuleAccent.health)
            }
        }
    }
}

/// Ansichten im Tab „Gesundheit“, die sich direkt öffnen lassen (z. B. aus der Funktions-Suche).
enum HealthRoute: Hashable {
    case painHistory, activityHistory, doctorReport, healthBridge, symptomHistory, periodReview
}
