import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Ein Medikament: heutige Einnahmen, Einnahmetreue mit Monatskalender, Vorrat, Protokoll.
struct MedicationDetailView: View {
    let medication: Medication

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var monthOffset = 0
    @State private var showsExtraIntake = false
    @State private var showsRefill = false

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            content(now: timeline.date)
        }
        .background(Color.tagwerkPage)
        .navigationTitle(medication.name.isEmpty ? "Medikament" : medication.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Bearbeiten") {
                    app.editingMedication = medication
                }
                .accessibilityIdentifier("medDetail.edit")
            }
        }
        .sheet(isPresented: $showsExtraIntake) {
            ExtraIntakeSheet(medication: medication)
        }
        .sheet(isPresented: $showsRefill) {
            RefillSheet(medication: medication)
        }
    }

    private func content(now: Date) -> some View {
        let calendar = AppModel.calendar
        let isScheduled = medication.schedule.isScheduled
        let todayEntries = medication.isActive ? medication.entries(on: now, now: now, calendar: calendar) : []

        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                header
                if isScheduled {
                    if medication.isActive {
                        todayCard(entries: todayEntries, now: now)
                    }
                    adherenceCard(now: now, calendar: calendar)
                } else {
                    asNeededCard(now: now, calendar: calendar)
                }
                if medication.stock != nil {
                    stockCard(now: now, calendar: calendar)
                }
                historyCard(now: now, calendar: calendar)
                if !medication.notes.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            SectionHeader("Notizen", systemImage: "note.text")
                            Text(medication.notes)
                                .font(.subheadline)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xl)
        }
    }

    // MARK: Karten

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            MedicationIcon(symbol: medication.symbol, colorName: medication.colorName, size: 56)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(medication.displayName)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(medication.schedule.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: Spacing.xs, lineSpacing: Spacing.xxs) {
                    chip(medication.form.title, symbol: "shippingbox")
                    if let hint = medication.timing.hint {
                        chip(hint, symbol: "fork.knife")
                    }
                    if medication.reminderStyle != .none, medication.schedule.isScheduled {
                        chip(medication.reminderStyle.title, symbol: medication.reminderStyle == .alarm ? "alarm" : "bell")
                    }
                    if !medication.isActive {
                        chip("Pausiert", symbol: "pause.circle")
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.top, Spacing.xs)
    }

    private func chip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 4)
            .foregroundStyle(medication.tint)
            .background(medication.tint.opacity(0.12), in: Capsule())
    }

    private func todayCard(entries: [DoseEntry], now: Date) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionHeader("Heute", systemImage: "clock", tint: medication.tint)
                if entries.isEmpty {
                    Text(medication.isRunning(on: now, calendar: AppModel.calendar) ? "Heute keine Einnahme geplant." : "Der Plan läuft heute nicht.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        DoseRow(entry: entry, medication: medication, showsName: false, now: now)
                    }
                }
                Button {
                    showsExtraIntake = true
                } label: {
                    Label("Zusätzlich genommen", systemImage: "plus.circle")
                        .font(.subheadline)
                }
                .padding(.top, Spacing.xxs)
            }
        }
    }

    private func asNeededCard(now: Date, calendar: Calendar) -> some View {
        let check = medication.asNeededCheck(now: now, calendar: calendar)
        return Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader("Bei Bedarf", systemImage: "hand.tap", tint: medication.tint)
                Text(check.statusLine)
                    .font(.subheadline)
                ForEach(check.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if let next = check.nextAllowed {
                    Text(AsNeededGuard.nextAllowedLabel(next, now: now, calendar: calendar))
                        .font(.footnote.weight(.medium))
                }
                Button {
                    showsExtraIntake = true
                } label: {
                    Label("Einnahme eintragen", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(check.isAllowed ? medication.tint : .orange)
                .accessibilityIdentifier("medDetail.takeAsNeeded")
            }
        }
    }

    private func adherenceCard(now: Date, calendar: Calendar) -> some View {
        let today = calendar.startOfDay(for: now)
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let month = calendar.date(byAdding: .month, value: monthOffset, to: thisMonth) ?? thisMonth
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: month) ?? month
        let monthEntries = medication.entries(from: month, to: min(monthEnd, calendar.endOfDayDate(for: today)), now: now, calendar: calendar)
        let days = Adherence.days(monthEntries, from: month, days: calendar.range(of: .day, in: .month, for: month)?.count ?? 30, calendar: calendar)
        let last30Start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let summary = Adherence.summarize(medication.entries(from: last30Start, to: calendar.endOfDayDate(for: today), now: now, calendar: calendar))
        let monthName = GermanCalendar.formatter("LLLL yyyy", calendar: calendar).string(from: month)

        return Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader("Einnahmetreue", systemImage: "calendar", tint: medication.tint)
                HStack(spacing: Spacing.m) {
                    ProgressRing(fraction: summary.rate ?? 0, tint: medication.tint, lineWidth: 8) {
                        Text(summary.percentLabel)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .minimumScaleFactor(0.6)
                            .padding(6)
                    }
                    .frame(width: 70, height: 70)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Letzte 30 Tage")
                            .font(.headline)
                        Text("\(summary.taken) genommen · \(summary.skipped) ausgelassen · \(summary.missed) verpasst")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button {
                        withAnimation(.snappy) { monthOffset -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: TouchTarget.standard, height: TouchTarget.standard)
                    }
                    .accessibilityLabel("Voriger Monat")
                    Spacer()
                    Text(monthName)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        withAnimation(.snappy) { monthOffset += 1 }
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: TouchTarget.standard, height: TouchTarget.standard)
                    }
                    .disabled(monthOffset >= 0)
                    .accessibilityLabel("Nächster Monat")
                }
                AdherenceCalendar(days: days, month: month)
            }
        }
    }

    private func stockCard(now: Date, calendar: Calendar) -> some View {
        let forecast = medication.forecast(now: now, calendar: calendar)
        let isLow = forecast?.needsRefill ?? false
        return Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader("Vorrat", systemImage: "shippingbox", tint: isLow ? .orange : medication.tint)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(medication.stockText ?? "–")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                        if let range = forecast?.rangeLabel(calendar: calendar) {
                            Text(range)
                                .font(.subheadline)
                                .foregroundStyle(isLow ? Color.orange : Color.secondary)
                        }
                    }
                    Spacer()
                    Button("Nachgefüllt") { showsRefill = true }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("medDetail.refill")
                }
                if medication.autoRefillTask {
                    Text("Wird es knapp, legt Tagwerk die Aufgabe „Nachschub besorgen“ an.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func historyCard(now: Date, calendar: Calendar) -> some View {
        let logs = Array(medication.sortedLogs.prefix(15))
        return Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionHeader("Protokoll", systemImage: "list.bullet.clipboard", tint: medication.tint)
                if logs.isEmpty {
                    Text("Noch keine Einträge.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(logs) { log in
                        LogRow(log: log, form: medication.form, now: now)
                            .contextMenu {
                                Button(role: .destructive) {
                                    MedicationActions.delete(log, in: context)
                                    app.medicationsChanged()
                                } label: {
                                    Label("Eintrag löschen", systemImage: "trash")
                                }
                            }
                    }
                    if (medication.logs?.count ?? 0) > logs.count {
                        Text("Ältere Einträge sind in der Datensicherung enthalten.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

private struct LogRow: View {
    let log: DoseLog
    let form: MedicationForm
    let now: Date

    var body: some View {
        let calendar = AppModel.calendar
        let moment = log.takenAt ?? log.scheduledAt ?? log.createdAt
        HStack(spacing: Spacing.s) {
            Image(systemName: log.status == .taken ? "checkmark.circle.fill" : "minus.circle.fill")
                .foregroundStyle(log.status == .taken ? Color.green : Color.gray)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(DueFormatter.dayLabel(for: moment, now: now, calendar: calendar)), \(GermanCalendar.time(moment, calendar: calendar))")
                    .font(.subheadline)
                Text(detail(calendar: calendar))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(calendar: Calendar) -> String {
        var parts: [String] = []
        switch log.status {
        case .taken: parts.append("\(form.amountLabel(log.amount)) genommen")
        case .skipped: parts.append("ausgelassen")
        }
        if let scheduled = log.scheduledAt {
            parts.append("geplant \(GermanCalendar.time(scheduled, calendar: calendar))")
        } else {
            parts.append("ohne festen Termin")
        }
        if !log.note.isEmpty {
            parts.append(log.note)
        }
        return parts.joined(separator: " · ")
    }
}
