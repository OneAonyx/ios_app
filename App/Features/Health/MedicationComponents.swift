import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Symbol eines Medikaments in seiner Farbe.
struct MedicationIcon: View {
    let symbol: String
    let colorName: String
    var size: CGFloat = 36

    var body: some View {
        IconBadge(systemImage: symbol, tint: ListColor.color(named: colorName), size: size)
    }
}

extension Medication {
    var tint: Color { ListColor.color(named: colorName) }
}

/// Runder Abhak-Knopf für Einnahmen. Farbe und Symbol zeigen den Zustand.
struct DoseCheckButton: View {
    let state: DoseEntry.State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: TouchTarget.standard, height: TouchTarget.standard)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == .taken || state == .skipped ? "Zurücksetzen" : "Als genommen markieren")
    }

    private var symbol: String {
        switch state {
        case .taken: "checkmark.circle.fill"
        case .skipped: "minus.circle.fill"
        case .missed: "exclamationmark.circle"
        default: "circle"
        }
    }

    private var color: Color {
        switch state {
        case .taken: .green
        case .skipped: .gray
        case .missed, .late: .red
        case .due: ModuleAccent.medication
        case .upcoming: Color.secondary
        }
    }
}

/// Zustand einer Einnahme als kurzer Text.
enum DoseStateText {
    static func label(for entry: DoseEntry, now: Date, calendar: Calendar) -> (text: String, color: Color)? {
        switch entry.state {
        case .taken:
            if let takenAt = entry.log?.takenAt {
                return ("genommen \(GermanCalendar.time(takenAt, calendar: calendar))", .green)
            }
            return ("genommen", .green)
        case .skipped:
            return ("ausgelassen", .secondary)
        case .missed:
            return ("verpasst", .red)
        case .late:
            return ("überfällig", .red)
        case .due:
            return entry.dose.date > now ? ("gleich dran", ModuleAccent.medication) : ("jetzt dran", ModuleAccent.medication)
        case .upcoming:
            return nil
        }
    }
}

/// Eine geplante Einnahme: Uhrzeit, Medikament, Menge, Zustand, Abhaken.
/// Bei sehr großer Schrift stehen Name und Details unter Uhrzeit und Knopf.
struct DoseRow: View {
    let entry: DoseEntry
    let medication: Medication
    var showsName = true
    var now: Date = .now

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.s) {
                        timeText
                        if showsName {
                            MedicationIcon(symbol: medication.symbol, colorName: medication.colorName, size: 32)
                        }
                        Spacer(minLength: 0)
                        checkButton
                    }
                    texts
                }
            } else {
                HStack(spacing: Spacing.s) {
                    timeText
                        .frame(minWidth: 46, alignment: .leading)
                    if showsName {
                        MedicationIcon(symbol: medication.symbol, colorName: medication.colorName, size: 32)
                    }
                    texts
                    Spacer(minLength: 0)
                    checkButton
                }
            }
        }
        .contentShape(Rectangle())
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: entry.isResolved ? "Zurücksetzen" : "Genommen") {
            toggle()
        }
    }

    private var timeText: some View {
        Text(GermanCalendar.time(entry.dose.date, calendar: AppModel.calendar))
            .font(.subheadline.monospacedDigit().weight(.semibold))
            .foregroundStyle(entry.isResolved ? Color.secondary : Color.primary)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(showsName ? (medication.name.isEmpty ? medication.displayName : medication.name) : medication.form.amountLabel(entry.dose.amount))
                .font(.body)
                .strikethrough(entry.state == .skipped)
                .foregroundStyle(entry.isResolved ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: Spacing.xs, lineSpacing: 2) {
                ForEach(detailParts, id: \.self) { part in
                    Text(part).foregroundStyle(.secondary)
                }
                if let state = DoseStateText.label(for: entry, now: now, calendar: AppModel.calendar) {
                    Text(state.text)
                        .fontWeight(.medium)
                        .foregroundStyle(state.color)
                }
            }
            .font(.caption)
        }
    }

    /// „10.000 HDU“, „1 Kapsel“, „vor dem Essen“ – einzeln, damit sie sauber umbrechen.
    private var detailParts: [String] {
        var parts: [String] = []
        if showsName {
            let dosage = medication.dosage.trimmingCharacters(in: .whitespaces)
            if !dosage.isEmpty { parts.append(dosage) }
            parts.append(medication.form.amountLabel(entry.dose.amount))
        }
        if let hint = medication.timing.hint { parts.append(hint) }
        return parts
    }

    private var checkButton: some View {
        DoseCheckButton(state: entry.state) {
            withAnimation(.snappy) { toggle() }
        }
        .sensoryFeedback(.success, trigger: entry.state) { _, state in state == .taken }
    }

    private func toggle() {
        if entry.isResolved {
            MedicationActions.undo(entry, medication: medication, in: context)
        } else {
            MedicationActions.take(entry, medication: medication, in: context)
        }
        app.medicationsChanged()
    }

    @ViewBuilder
    private var menu: some View {
        if !entry.isResolved || entry.state == .skipped {
            Button {
                MedicationActions.take(entry, medication: medication, in: context)
                app.medicationsChanged()
            } label: {
                Label("Genommen", systemImage: "checkmark.circle")
            }
        }
        if entry.state != .skipped {
            Button {
                MedicationActions.skip(entry, medication: medication, in: context)
                app.medicationsChanged()
            } label: {
                Label("Auslassen", systemImage: "minus.circle")
            }
        }
        if entry.isResolved {
            Button {
                MedicationActions.undo(entry, medication: medication, in: context)
                app.medicationsChanged()
            } label: {
                Label("Zurücksetzen", systemImage: "arrow.uturn.backward")
            }
        }
    }
}

/// Eine Einnahme mit ihrem Medikament.
struct DayDoseItem: Identifiable {
    let entry: DoseEntry
    let medication: Medication
    var id: String { entry.id }
}

/// Einnahmen mehrerer Medikamente an einem Tag, nach Uhrzeit sortiert.
struct DayDoses {
    let items: [DayDoseItem]

    init(medications: [Medication], day: Date, now: Date, calendar: Calendar) {
        items = medications
            .filter(\.isActive)
            .flatMap { medication in
                medication.entries(on: day, now: now, calendar: calendar).map { DayDoseItem(entry: $0, medication: medication) }
            }
            .sorted { lhs, rhs in
                if lhs.entry.dose.date != rhs.entry.dose.date { return lhs.entry.dose.date < rhs.entry.dose.date }
                return lhs.medication.sortIndex < rhs.medication.sortIndex
            }
    }

    var done: Int { items.filter { $0.entry.isResolved }.count }
    var total: Int { items.count }
    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

/// Mengen-Auswahl mit Anzeige in der Einheit der Darreichungsform („½ Tablette“).
struct AmountStepper: View {
    let title: String
    @Binding var amount: Double
    let form: MedicationForm

    var body: some View {
        Stepper(value: $amount, in: form.amountStep...100, step: form.amountStep) {
            HStack {
                Text(title)
                Spacer()
                Text(form.amountLabel(amount))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
