import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Einnahme ohne festen Termin eintragen (Bei Bedarf oder zusätzlich), mit Warnung
/// bei Höchstmenge und Mindestabstand.
struct ExtraIntakeSheet: View {
    let medication: Medication

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var amount: Double = 1
    @State private var takenAt: Date = .now
    @State private var note = ""
    @State private var confirmDespiteWarning = false

    var body: some View {
        let calendar = AppModel.calendar
        let check = medication.asNeededCheck(now: .now, calendar: calendar)
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: Spacing.s) {
                        MedicationIcon(symbol: medication.symbol, colorName: medication.colorName)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(medication.displayName).font(.headline)
                            Text(medication.schedule.isScheduled ? "Zusätzliche Einnahme" : check.statusLine)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !check.warnings.isEmpty {
                    Section {
                        ForEach(check.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.subheadline)
                        }
                        if let next = check.nextAllowed {
                            Text(AsNeededGuard.nextAllowedLabel(next, now: .now, calendar: calendar))
                                .font(.subheadline.weight(.medium))
                        }
                    } footer: {
                        Text("Hinweis nach deinen eigenen Angaben. Im Zweifel ärztlich oder in der Apotheke nachfragen.")
                    }
                }
                Section {
                    AmountStepper(title: "Menge", amount: $amount, form: medication.form)
                    DatePicker("Zeitpunkt", selection: $takenAt, in: ...Date.now.addingTimeInterval(60))
                    TextField("Notiz (optional)", text: $note)
                }
            }
            .navigationTitle(medication.schedule.isScheduled ? "Zusätzlich genommen" : "Einnahme eintragen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Eintragen") {
                        if check.isAllowed {
                            save()
                        } else {
                            confirmDespiteWarning = true
                        }
                    }
                    .accessibilityIdentifier("extraIntake.save")
                }
            }
            .confirmationDialog("Trotz Hinweis eintragen?", isPresented: $confirmDespiteWarning, titleVisibility: .visible) {
                Button("Trotzdem eintragen") { save() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text(check.warnings.joined(separator: "\n"))
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { amount = medication.defaultAmount }
    }

    private func save() {
        MedicationActions.takeExtra(medication, amount: amount, at: takenAt, note: note.trimmingCharacters(in: .whitespaces), in: context)
        app.medicationsChanged()
        dismiss()
    }
}

/// Vorrat auffüllen.
struct RefillSheet: View {
    let medication: Medication

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var amountText = ""

    private let quickAmounts: [Double] = [10, 20, 28, 30, 50, 100]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Aktuell", value: medication.stockText ?? "nicht gezählt")
                    TextField("Menge", text: $amountText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Hinzufügen (\(medication.form.unit(for: 2)))")
                } footer: {
                    FlowLayout(spacing: Spacing.xs, lineSpacing: Spacing.xs) {
                        ForEach(quickAmounts, id: \.self) { value in
                            Button("+\(DoseAmount.formatStock(value))") {
                                amountText = DoseAmount.formatStock(value)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, Spacing.xs)
                }
            }
            .navigationTitle("Nachgefüllt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        guard let amount = parsedAmount else { return }
                        MedicationActions.refill(medication, adding: amount, in: context)
                        app.medicationsChanged()
                        dismiss()
                    }
                    .disabled(parsedAmount == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var parsedAmount: Double? {
        let value = Double(amountText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        guard let value, value > 0 else { return nil }
        return value
    }
}

/// Monatskalender mit dem Einnahme-Status je Tag.
///
/// Ein festes `Grid` statt `LazyVGrid`: Es misst seine Höhe zuverlässig, und Kopfzeile und
/// Tage kommen sich bei den IDs nicht in die Quere.
struct AdherenceCalendar: View {
    let days: [DayAdherence]
    let month: Date

    var body: some View {
        let calendar = AppModel.calendar
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let leading = GermanCalendar.mondayIndex(ofWeekday: calendar.component(.weekday, from: first))
        let byDay = Dictionary(days.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { lhs, _ in lhs })
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let today = calendar.startOfDay(for: .now)
        // Zellen: nil = leer, sonst Tag des Monats (1…).
        let cells: [Int?] = Array(repeating: nil, count: leading) + (1...count).map { Optional($0) }
        let weeks: [[Int?]] = stride(from: 0, to: cells.count, by: 7).map { start in
            let row = Array(cells[start..<min(start + 7, cells.count)])
            return row + Array(repeating: nil, count: 7 - row.count)
        }

        VStack(spacing: Spacing.xs) {
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    ForEach(GermanCalendar.weekdayOrder, id: \.self) { weekday in
                        Text(GermanCalendar.shortWeekdays[weekday - 1])
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    GridRow {
                        ForEach(0..<7, id: \.self) { column in
                            if let number = week[column] {
                                let day = calendar.date(byAdding: .day, value: number - 1, to: first) ?? first
                                DayCell(
                                    number: number,
                                    status: byDay[calendar.startOfDay(for: day)]?.status ?? .none,
                                    isToday: calendar.isDate(day, inSameDayAs: today)
                                )
                            } else {
                                Color.clear.frame(maxWidth: .infinity, minHeight: 32)
                            }
                        }
                    }
                }
            }
            HStack(spacing: Spacing.s) {
                LegendDot(color: .green, text: "alles")
                LegendDot(color: .orange, text: "teilweise")
                LegendDot(color: .red, text: "nichts")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private struct DayCell: View {
        let number: Int
        let status: DayAdherenceStatus
        let isToday: Bool

        var body: some View {
            Text("\(number)")
                .font(.caption.monospacedDigit().weight(isToday ? .bold : .regular))
                .foregroundStyle(foreground)
                .frame(width: 32, height: 32)
                .background(background, in: Circle())
                .overlay {
                    if isToday {
                        Circle().strokeBorder(ModuleAccent.today, lineWidth: 2)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("\(number). \(statusText)")
        }

        private var background: Color {
            switch status {
            case .complete: .green
            case .partial: .orange
            case .missed: .red
            case .pending: ModuleAccent.medication.opacity(0.25)
            case .none: .clear
            }
        }

        private var foreground: Color {
            switch status {
            case .complete, .partial, .missed: .white
            case .pending, .none: .primary
            }
        }

        private var statusText: String {
            switch status {
            case .complete: "alles genommen"
            case .partial: "teilweise genommen"
            case .missed: "nichts genommen"
            case .pending: "offen"
            case .none: "keine Einnahme"
            }
        }
    }

    private struct LegendDot: View {
        let color: Color
        let text: String

        var body: some View {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(text)
            }
        }
    }
}
