import Charts
import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Fünf Emoji-Knöpfe für eine Skala. Nochmal tippen nimmt den Wert zurück.
struct CheckInScaleRow: View {
    let scale: CheckInScale
    let value: Int?
    var showsQuestion = true
    let onChange: (Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if showsQuestion {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: scale.symbol)
                        .foregroundStyle(ModuleAccent.health)
                        .accessibilityHidden(true)
                    Text(scale.question)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    if let value {
                        Text(scale.label(value))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: Spacing.xs) {
                ForEach(1...5, id: \.self) { option in
                    let isSelected = value == option
                    Button {
                        onChange(isSelected ? nil : option)
                    } label: {
                        Text(scale.emoji(option))
                            .font(.title2)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                isSelected ? ModuleAccent.health.opacity(0.22) : Color.primary.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                    .strokeBorder(isSelected ? ModuleAccent.health : Color.clear, lineWidth: 2)
                            )
                            .opacity(value == nil || isSelected ? 1 : 0.55)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(scale.title): \(scale.label(option))")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("checkin.\(scale.rawValue).\(option)")
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .sensoryFeedback(.selection, trigger: value)
        }
    }
}

/// Check-in auf „Heute“: morgens Schlaf und Energie, abends Stimmung und Stress.
struct CheckInTodayCard: View {
    let now: Date

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: \DailyCheckIn.day, order: .reverse) private var checkIns: [DailyCheckIn]
    @State private var isEditing = false

    var body: some View {
        let calendar = AppModel.calendar
        let today = checkIns.first { calendar.isDate($0.day, inSameDayAs: now) }
        let fact = today?.fact ?? CheckInFact(day: calendar.startOfDay(for: now))
        if let kind = CheckInKind.current(now: now, calendar: calendar) {
            let scales = CheckInScale.scales(for: kind)
            let complete = fact.isComplete(kind)
            Card {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack {
                        SectionHeader("Check-in", systemImage: "heart.text.square", tint: ModuleAccent.health)
                        if complete {
                            Label("Erledigt", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                                .fixedSize()
                        }
                    }
                    if complete && !isEditing {
                        HStack(spacing: Spacing.s) {
                            Text(scales.compactMap { scale in fact.value(scale).map { "\(scale.emoji($0)) \(scale.title) \(scale.label($0))" } }.joined(separator: "   "))
                                .font(.subheadline)
                            Spacer(minLength: 0)
                            Button("Ändern") {
                                withAnimation(.snappy) { isEditing = true }
                            }
                            .font(.subheadline)
                            .tint(ModuleAccent.health)
                        }
                    } else {
                        Text(kind.title)
                            .font(.headline)
                        ForEach(scales) { scale in
                            CheckInScaleRow(scale: scale, value: fact.value(scale)) { value in
                                isEditing = true
                                InsightsActions.set(scale, value, on: now, calendar: calendar, in: context)
                                // Nach dem letzten Wert kurz stehen lassen, dann zusammenklappen.
                                let nowComplete = scales.allSatisfy { $0 == scale ? value != nil : fact.value($0) != nil }
                                if nowComplete {
                                    Task {
                                        try? await Task.sleep(for: .milliseconds(800))
                                        withAnimation(.snappy) { isEditing = false }
                                    }
                                }
                            }
                        }
                        Button {
                            app.openCheckIn()
                        } label: {
                            Label("Mehr (Schlafdauer, Notiz)", systemImage: "square.and.pencil")
                                .font(.footnote)
                        }
                        .tint(ModuleAccent.health)
                    }
                }
            }
            .accessibilityIdentifier("today.checkin")
        }
    }
}

/// Ganzer Check-in des Tages: alle Skalen, Schlafdauer und Notiz.
struct CheckInSheet: View {
    var day: Date = .now

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \DailyCheckIn.day, order: .reverse) private var checkIns: [DailyCheckIn]
    @State private var note = ""
    @State private var loaded = false

    var body: some View {
        let calendar = AppModel.calendar
        let entry = checkIns.first { calendar.isDate($0.day, inSameDayAs: day) }
        let fact = entry?.fact ?? CheckInFact(day: calendar.startOfDay(for: day))
        NavigationStack {
            Form {
                Section("Morgens") {
                    ForEach(CheckInScale.scales(for: .morning)) { scale in
                        CheckInScaleRow(scale: scale, value: fact.value(scale)) { value in
                            InsightsActions.set(scale, value, on: day, calendar: calendar, in: context)
                        }
                    }
                    SleepHoursRow(hours: fact.sleepHours) { hours in
                        InsightsActions.setSleepHours(hours, on: day, calendar: calendar, in: context)
                    }
                }
                Section("Abends") {
                    ForEach(CheckInScale.scales(for: .evening)) { scale in
                        CheckInScaleRow(scale: scale, value: fact.value(scale)) { value in
                            InsightsActions.set(scale, value, on: day, calendar: calendar, in: context)
                        }
                    }
                }
                Section {
                    TextField("Was war heute los?", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                        .accessibilityIdentifier("checkin.note")
                } header: {
                    Text("Notiz")
                } footer: {
                    Text("Schlechter Schlaf (1–2) und viel Stress (4–5) fließen als Umstände in die Muster-Auswertung ein.")
                }
                Section {
                    NavigationLink {
                        CheckInHistoryView()
                    } label: {
                        Label("Verlauf", systemImage: "chart.xyaxis.line")
                    }
                }
            }
            .navigationTitle(calendar.isDateInToday(day) ? "Check-in heute" : "Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        saveNote(existing: entry)
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                note = entry?.note ?? ""
                loaded = true
            }
            .onDisappear {
                saveNote(existing: entry)
            }
        }
    }

    private func saveNote(existing: DailyCheckIn?) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (existing?.note ?? "") else { return }
        InsightsActions.setNote(trimmed, on: day, calendar: AppModel.calendar, in: context)
    }
}

/// Schlafdauer in halben Stunden.
private struct SleepHoursRow: View {
    let hours: Double?
    let onChange: (Double?) -> Void

    var body: some View {
        // Bei großer Schrift steht der Wert unter der Überschrift.
        ViewThatFits(in: .horizontal) {
            HStack {
                title
                Spacer()
                control
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                title
                control
            }
        }
    }

    private var title: some View {
        Label("Schlafdauer", systemImage: "moon.zzz.fill")
            .fixedSize()
    }

    @ViewBuilder
    private var control: some View {
        HStack {
            if let hours {
                Stepper(value: Binding(get: { hours }, set: { onChange($0) }), in: 0...16, step: 0.5) {
                    Text("\(WeightFormat.number(hours)) Std.")
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .fixedSize()
                Button {
                    onChange(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Schlafdauer löschen")
            } else {
                Button("Eintragen") { onChange(7.5) }
            }
        }
    }
}

/// Befinden der letzten Wochen: Verlauf je Skala, Durchschnitte, Tage mit Notizen.
struct CheckInHistoryView: View {
    @Query(sort: \DailyCheckIn.day, order: .reverse) private var checkIns: [DailyCheckIn]
    @State private var scale: CheckInScale = .mood
    @State private var days = 30
    @State private var editingDay: DayLink?

    private struct DayLink: Identifiable {
        let day: Date
        var id: Date { day }
    }

    private struct Point: Identifiable {
        let day: Date
        let value: Int
        var id: Date { day }
    }

    var body: some View {
        let calendar = AppModel.calendar
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: .now)) ?? .now
        let inRange = checkIns.filter { $0.day >= start }
        let facts = inRange.map(\.fact)
        let averages = CheckInAverages.compute(facts)
        let points = facts.compactMap { fact in fact.value(scale).map { Point(day: fact.day, value: $0) } }

        List {
            Section {
                Picker("Zeitraum", selection: $days) {
                    Text("14 Tage").tag(14)
                    Text("30 Tage").tag(30)
                    Text("90 Tage").tag(90)
                }
                .pickerStyle(.segmented)
                AveragesGrid(averages: averages)
            } footer: {
                Text(averages.days == 1 ? "1 Tag mit Check-in." : "\(averages.days) Tage mit Check-in.")
            }

            Section {
                Picker("Skala", selection: $scale) {
                    ForEach(CheckInScale.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                if points.isEmpty {
                    Text("Noch keine Werte für \(scale.title).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Chart(points) { point in
                        LineMark(x: .value("Tag", point.day, unit: .day), y: .value(scale.title, point.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(ModuleAccent.health)
                        PointMark(x: .value("Tag", point.day, unit: .day), y: .value(scale.title, point.value))
                            .foregroundStyle(ModuleAccent.health)
                    }
                    .chartYScale(domain: 1...5)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.day().month(.twoDigits))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let number = value.as(Int.self) { Text(scale.emoji(number)) }
                            }
                        }
                    }
                    .frame(height: 180)
                    .accessibilityLabel("Verlauf \(scale.title)")
                }
            } header: {
                Text("Verlauf")
            } footer: {
                Text(scale.higherIsBetter ? "Höher ist besser." : "Niedriger ist besser.")
            }

            Section("Tage") {
                if inRange.isEmpty {
                    Text("Noch keine Check-ins in diesem Zeitraum.")
                        .foregroundStyle(.secondary)
                }
                ForEach(inRange) { entry in
                    Button {
                        editingDay = DayLink(day: entry.day)
                    } label: {
                        CheckInDayRow(fact: entry.fact)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Befinden")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingDay) { link in
            CheckInSheet(day: link.day)
        }
    }
}

/// Durchschnitte der vier Skalen als kleine Kacheln.
struct AveragesGrid: View {
    let averages: CheckInAverages

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 130), spacing: Spacing.xs)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.xs) {
            ForEach(CheckInScale.allCases) { scale in
                let value = averages.value(scale)
                HStack(spacing: Spacing.xs) {
                    Text(value.map { scale.emoji(Int($0.rounded())) } ?? "–")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(scale.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(value.map { "Ø " + CheckInAverages.format($0) } ?? "–")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct CheckInDayRow: View {
    let fact: CheckInFact

    var body: some View {
        let calendar = AppModel.calendar
        let weekday = GermanCalendar.shortWeekdays[calendar.component(.weekday, from: fact.day) - 1]
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(weekday), \(calendar.component(.day, from: fact.day)). \(GermanCalendar.shortMonths[calendar.component(.month, from: fact.day) - 1])")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(CheckInScale.allCases.compactMap { scale in fact.value(scale).map { scale.emoji($0) } }.joined(separator: " "))
            }
            if let hours = fact.sleepHours {
                Text("\(WeightFormat.number(hours)) Std. Schlaf")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !fact.note.isEmpty {
                Text(fact.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .contentShape(Rectangle())
    }
}
