import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Wochenrückblick: Aufgaben, Medikamente, Training, Ernährung, Beschwerden, Befinden, Gewicht.
struct WeeklyReviewView: View {
    @State var weekStart: Date

    @Environment(\.modelContext) private var context
    // Die Abfragen sorgen dafür, dass der Rückblick bei neuen Einträgen neu rechnet.
    @Query private var checkIns: [DailyCheckIn]
    @Query private var sessions: [WorkoutSession]
    @Query private var meals: [MealEntry]
    @State private var askingClaude = false

    var body: some View {
        let _ = (checkIns.count, sessions.count, meals.count)
        let calendar = AppModel.calendar
        let review = InsightsActions.weeklyReview(weekStart: weekStart, calendar: calendar, in: context)
        let thisWeek = AgendaBuilder.startOfWeek(containing: .now, calendar: calendar)
        let isCurrent = weekStart >= thisWeek

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                WeekSwitcher(title: review.title, isCurrent: isCurrent) { step in
                    if let moved = calendar.date(byAdding: .day, value: 7 * step, to: weekStart) {
                        withAnimation(.snappy) { weekStart = moved }
                    }
                }

                if review.isEmpty {
                    Card {
                        ContentUnavailableView(
                            "Noch nichts in dieser Woche",
                            systemImage: "calendar.badge.clock",
                            description: Text("Sobald du Aufgaben erledigst, trainierst, Mahlzeiten oder Check-ins einträgst, steht hier deine Woche.")
                        )
                    }
                } else {
                    if !review.highlights.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                SectionHeader("Höhepunkte", systemImage: "star.fill", tint: .yellow)
                                ForEach(review.highlights, id: \.self) { highlight in
                                    Label(highlight, systemImage: "checkmark.seal.fill")
                                        .font(.subheadline)
                                        .labelStyle(TintedIconLabelStyle(tint: .green))
                                }
                            }
                        }
                    }
                    ForEach(review.sections) { section in
                        ReviewSectionCard(section: section)
                    }
                    if isCurrent {
                        Text("Die Woche läuft noch. Zahlen bis jetzt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Spacing.xxs)
                    }
                    Card {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            SectionHeader("Mit Claude", systemImage: "sparkles", tint: .purple)
                            Text("Claude bekommt nur die Kennzahlen oben (keine Namen, keine Einzeleinträge) und gibt dir Tipps für die nächste Woche.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            HStack(spacing: Spacing.xs) {
                                Button {
                                    askingClaude = true
                                } label: {
                                    Label("Besprechen", systemImage: "bubble.left.and.text.bubble.right")
                                        .frame(maxWidth: .infinity, minHeight: 34)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)
                                .accessibilityIdentifier("review.claude")
                                ShareLink(item: review.plainText, subject: Text(review.title)) {
                                    Label("Teilen", systemImage: "square.and.arrow.up")
                                        .frame(maxWidth: .infinity, minHeight: 34)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.tagwerkPage)
        .navigationTitle("Wochenrückblick")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $askingClaude) {
            ClaudeRequestSheet(task: .weeklyReview, preset: ClaudePreset(weekStart: weekStart))
        }
    }
}

/// Wochenrückblick als eigenes Blatt (aus Mitteilung, Siri, „Heute“).
struct WeeklyReviewSheet: View {
    let weekStart: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WeeklyReviewView(weekStart: weekStart)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                    }
                }
        }
    }
}

private struct WeekSwitcher: View {
    let title: String
    let isCurrent: Bool
    let onStep: (Int) -> Void

    var body: some View {
        HStack {
            Button {
                onStep(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Vorige Woche")
            .accessibilityIdentifier("review.previous")
            Spacer(minLength: 0)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button {
                onStep(1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(isCurrent)
            .accessibilityLabel("Nächste Woche")
        }
        .padding(.top, Spacing.xs)
    }
}

private struct ReviewSectionCard: View {
    let section: WeeklyReview.Section

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(section.title, systemImage: section.symbol, tint: tint)
                ForEach(section.lines) { line in
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                            lineLabel(line)
                            Spacer(minLength: Spacing.xs)
                            lineValue(line)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            lineLabel(line)
                            lineValue(line)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func lineLabel(_ line: WeeklyReview.Line) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(line.label)
                .font(.subheadline)
            if let detail = line.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func lineValue(_ line: WeeklyReview.Line) -> some View {
        Text(line.value)
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(line.tone.color)
            .multilineTextAlignment(.trailing)
    }

    private var tint: Color {
        switch section.id {
        case "tasks": ModuleAccent.tasks
        case "medication": ModuleAccent.medication
        case "training": ModuleAccent.training
        case "nutrition": ModuleAccent.nutrition
        case "symptoms", "checkins": ModuleAccent.health
        default: .secondary
        }
    }
}

extension WeeklyReview.Tone {
    var color: Color {
        switch self {
        case .good: .green
        case .neutral: .primary
        case .attention: .orange
        }
    }
}

/// Label mit farbigem Symbol und normalem Text.
struct TintedIconLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            configuration.icon
                .foregroundStyle(tint)
            configuration.title
        }
    }
}

/// Auf „Heute“ ab Sonntagmittag bis Montagmittag: Hinweis auf den Wochenrückblick.
struct ReviewTodayCard: View {
    let now: Date

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context

    var body: some View {
        let calendar = AppModel.calendar
        if let weekStart = Self.weekToShow(now: now, calendar: calendar) {
            let review = InsightsActions.weeklyReview(weekStart: weekStart, now: now, calendar: calendar, in: context)
            let planningDay = calendar.component(.weekday, from: now) == 1
            if !review.isEmpty || planningDay {
                Card {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader("Wochenrückblick", systemImage: "calendar.badge.checkmark", tint: .purple)
                        if !review.isEmpty {
                            Text(review.title)
                                .font(.headline)
                            ForEach(review.highlights.prefix(3), id: \.self) { highlight in
                                Label(highlight, systemImage: "checkmark.seal.fill")
                                    .font(.subheadline)
                                    .labelStyle(TintedIconLabelStyle(tint: .green))
                            }
                        }
                        HStack(spacing: Spacing.xs) {
                            if !review.isEmpty {
                                Button {
                                    app.openReview(weekStart: weekStart)
                                } label: {
                                    Label("Ansehen", systemImage: "arrow.right")
                                        .frame(maxWidth: .infinity, minHeight: 34)
                                }
                                .buttonStyle(.bordered)
                                .tint(.purple)
                                .accessibilityIdentifier("today.review")
                            }
                            if planningDay {
                                Button {
                                    app.isShowingWeekPlanning = true
                                } label: {
                                    Label("Woche planen", systemImage: "calendar.badge.plus")
                                        .frame(maxWidth: .infinity, minHeight: 34)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)
                                .accessibilityIdentifier("today.planWeek")
                            }
                        }
                    }
                }
            }
        }
    }

    /// Sonntag ab 12 Uhr: diese Woche. Montag bis 12 Uhr: die Woche davor.
    static func weekToShow(now: Date, calendar: Calendar) -> Date? {
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        let thisWeek = AgendaBuilder.startOfWeek(containing: now, calendar: calendar)
        if weekday == 1, hour >= 12 { return thisWeek }
        if weekday == 2, hour < 12 { return calendar.date(byAdding: .day, value: -7, to: thisWeek) }
        return nil
    }
}
