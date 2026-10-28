import Charts
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Monats- und Jahresrückblick mit Vergleich zum Zeitraum davor.
struct PeriodReviewView: View {
    @Environment(\.modelContext) private var context
    @State private var period: ReviewPeriod = .month
    @State private var offset = 0
    @State private var review: PeriodReview?
    @State private var months: [ChartPoint] = []

    var body: some View {
        let calendar = AppModel.calendar
        let start = period.shifted(period.interval(containing: .now, calendar: calendar).start, by: offset, calendar: calendar)
        List {
            Section {
                Picker("Zeitraum", selection: $period) {
                    ForEach(ReviewPeriod.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: period) { _, _ in offset = 0 }
                HStack {
                    Button {
                        offset -= 1
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(period == .month ? "Voriger Monat" : "Voriges Jahr")
                    Spacer()
                    Text(period.label(start, calendar: calendar))
                        .font(.headline)
                    Spacer()
                    Button {
                        offset += 1
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                    .disabled(offset >= 0)
                    .accessibilityLabel(period == .month ? "Nächster Monat" : "Nächstes Jahr")
                }
            }

            if let review {
                if review.isEmpty {
                    Section {
                        ContentUnavailableView("Noch keine Daten", systemImage: "chart.bar.xaxis", description: Text("Für diesen Zeitraum ist nichts erfasst."))
                    }
                } else {
                    if !review.highlights.isEmpty {
                        Section("Gut gelaufen") {
                            ForEach(review.highlights, id: \.self) { highlight in
                                Label(highlight, systemImage: "checkmark.seal.fill")
                                    .labelStyle(TintedIconLabelStyle(tint: .green))
                            }
                        }
                    }
                    Section {
                        ForEach(review.lines) { line in
                            ReviewLineRow(line: line)
                        }
                    } footer: {
                        Text(footer(review, calendar: calendar))
                    }
                    if period == .year, months.contains(where: { $0.value > 0 }) {
                        Section("Einheiten je Monat") {
                            Chart(months) { point in
                                BarMark(x: .value("Monat", point.date, unit: .month), y: .value("Einheiten", point.value))
                                    .foregroundStyle(ModuleAccent.training)
                            }
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                                    AxisGridLine()
                                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                                }
                            }
                            .frame(height: 160)
                            .accessibilityLabel("Trainingseinheiten je Monat")
                            .accessibilityValue(months.map { "\(Int($0.value))" }.joined(separator: ", "))
                        }
                    }
                }
            } else {
                Section {
                    HStack(spacing: Spacing.s) {
                        ProgressView()
                        Text("Wird ausgewertet …")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Rückblick")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(period.rawValue)\(offset)") {
            review = nil
            review = ReviewActions.review(period, start: start, calendar: calendar, in: context)
            months = period == .year
                ? ReviewActions.workoutsPerMonth(year: start, calendar: calendar, in: context).map { ChartPoint(date: $0.month, value: Double($0.count)) }
                : []
        }
    }
}

extension PeriodReviewView {
    private func footer(_ review: PeriodReview, calendar: Calendar) -> String {
        var text = period == .month
            ? "Vergleich zum Vormonat je Woche bzw. als Anteil der Tage, damit ein laufender Monat fair gegen einen ganzen steht."
            : "Vergleich zum Vorjahr je Woche bzw. als Anteil der Tage."
        if let since = review.since {
            text = "Ausgewertet ab deinem ersten Eintrag am \(WeeklyReview.dayMonth(since, calendar: calendar)). " + text
        }
        return text
    }
}

/// Eine Kennzahl mit Vergleich, grün wenn besser, orange wenn schlechter.
private struct ReviewLineRow: View {
    let line: PeriodReviewLine

    var body: some View {
        HStack(spacing: Spacing.s) {
            IconBadge(systemImage: line.symbol, tint: areaTint, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(line.value)
                    .font(.body.weight(.semibold))
                if let change = line.change {
                    Label(change, systemImage: arrow)
                        .font(.caption)
                        .foregroundStyle(tint)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Farbe des Bereichs, damit die Liste auch ohne Vergleich lesbar bleibt.
    private var areaTint: Color {
        switch line.id {
        case "workouts", "sets", "weight": ModuleAccent.training
        case "activity", "steps": .green
        case "symptoms", "pain", "diary", "mood": ModuleAccent.health
        case "adherence": ModuleAccent.medication
        case "sleep": ModuleAccent.sleep
        case "tasks": ModuleAccent.tasks
        default: .secondary
        }
    }

    private var tint: Color {
        switch line.direction {
        case .better: .green
        case .worse: .orange
        case .same, .none: .secondary
        }
    }

    private var arrow: String {
        switch line.direction {
        case .better: "arrow.up.right"
        case .worse: "arrow.down.right"
        case .same: "equal"
        case .none: "arrow.left.arrow.right"
        }
    }
}
