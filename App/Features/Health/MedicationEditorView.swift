import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Eingaben im Editor, getrennt vom gespeicherten Medikament („Abbrechen“ verwirft alles).
struct MedicationDraft {
    var name = ""
    var dosage = ""
    var form: MedicationForm = .tablet
    var colorName = ListColor.teal.rawValue
    var symbol = MedicationForm.tablet.defaultSymbol
    var timing: MealTiming = .none
    var schedule = MedicationSchedule.daily([DoseTime(hour: 8)])
    var startDate = Date.now
    var hasEndDate = false
    var endDate = Date.now.addingTimeInterval(30 * 86_400)
    var tracksStock = false
    var stockText = ""
    var refillThresholdDays = 7
    var autoRefillTask = false
    var reminderStyle: ReminderStyle = .notification
    var isActive = true
    var notes = ""

    init() {}

    init(_ medication: Medication) {
        name = medication.name
        dosage = medication.dosage
        form = medication.form
        colorName = medication.colorName
        symbol = medication.symbol
        timing = medication.timing
        schedule = medication.schedule
        startDate = medication.startDate
        hasEndDate = medication.endDate != nil
        endDate = medication.endDate ?? Date.now.addingTimeInterval(30 * 86_400)
        tracksStock = medication.stock != nil
        stockText = medication.stock.map { DoseAmount.formatStock($0) } ?? ""
        refillThresholdDays = medication.refillThresholdDays
        autoRefillTask = medication.autoRefillTask
        reminderStyle = medication.reminderStyle
        isActive = medication.isActive
        notes = medication.notes
    }

    var stockValue: Double? {
        guard tracksStock else { return nil }
        return Double(stockText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? 0
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isValid: Bool { !trimmedName.isEmpty && schedule.validationMessage == nil }

    func apply(to medication: Medication) {
        medication.name = trimmedName
        medication.dosage = dosage.trimmingCharacters(in: .whitespaces)
        medication.form = form
        medication.colorName = colorName
        medication.symbol = symbol
        medication.timing = timing
        medication.schedule = schedule
        medication.startDate = startDate
        medication.endDate = hasEndDate && schedule.kind != .taper ? endDate : nil
        let newStock = stockValue
        if newStock != medication.stock {
            medication.stock = newStock
            // Neuer Vorrat: eine alte Nachschub-Aufgabe gilt nicht mehr.
            medication.refillTaskID = nil
        }
        medication.refillThresholdDays = refillThresholdDays
        medication.autoRefillTask = tracksStock && autoRefillTask
        medication.reminderStyle = reminderStyle
        medication.isActive = isActive
        medication.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Medikament anlegen oder bearbeiten.
struct MedicationEditorView: View {
    /// `nil` = neues Medikament.
    let medication: Medication?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var draft = MedicationDraft()
    @State private var didLoad = false
    @State private var confirmDelete = false

    private var calendar: Calendar { AppModel.calendar }

    var body: some View {
        NavigationStack {
            Form {
                basicsSection
                scheduleSection
                scheduleDetails
                timingSection
                reminderSection
                stockSection
                appearanceSection
                notesSection
                if medication != nil {
                    manageSection
                }
            }
            .navigationTitle(medication == nil ? "Medikament" : "Bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(!draft.isValid)
                        .accessibilityIdentifier("medEditor.save")
                }
            }
            .confirmationDialog("Medikament löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { deleteMedication() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Das Einnahme-Protokoll wird mit gelöscht. Zum Aufheben lieber pausieren.")
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let medication {
                draft = MedicationDraft(medication)
            }
        }
    }

    // MARK: Abschnitte

    private var basicsSection: some View {
        Section {
            TextField("Name, z. B. DAO-Enzym", text: $draft.name)
                .font(.headline)
                .accessibilityIdentifier("medEditor.name")
            TextField("Stärke, z. B. 400 mg", text: $draft.dosage)
            Picker("Form", selection: $draft.form) {
                ForEach(MedicationForm.allCases) { form in
                    Text(form.title).tag(form)
                }
            }
            .onChange(of: draft.form) { oldForm, newForm in
                if draft.symbol == oldForm.defaultSymbol {
                    draft.symbol = newForm.defaultSymbol
                }
            }
        }
    }

    private var scheduleSection: some View {
        Section {
            Picker("Einnahme", selection: $draft.schedule.kind) {
                ForEach(MedicationSchedule.Kind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .accessibilityIdentifier("medEditor.kind")
            if draft.schedule.kind == .weekdays {
                WeekdayPicker(selection: $draft.schedule.weekdays)
            }
            if draft.schedule.kind == .everyNDays {
                Stepper("Alle \(draft.schedule.dayInterval) Tage", value: $draft.schedule.dayInterval, in: 2...60)
            }
            if draft.schedule.kind == .cycle {
                Stepper("\(draft.schedule.cycleOnDays) Tage Einnahme", value: $draft.schedule.cycleOnDays, in: 1...120)
                Stepper("\(draft.schedule.cycleOffDays) Tage Pause", value: $draft.schedule.cycleOffDays, in: 1...120)
            }
            if draft.schedule.kind == .interval {
                Stepper("Alle \(draft.schedule.intervalHours) Stunden", value: $draft.schedule.intervalHours, in: 1...24)
                DatePicker("Erste Einnahme", selection: intervalStartBinding, displayedComponents: .hourAndMinute)
                AmountStepper(title: "Menge", amount: $draft.schedule.intervalStart.amount, form: draft.form)
            }
            if draft.schedule.kind == .asNeeded {
                AmountStepper(title: "Übliche Menge", amount: $draft.schedule.asNeededAmount, form: draft.form)
                Toggle("Höchstens pro 24 Std.", isOn: maxPerDayEnabled)
                if let max = draft.schedule.maxPerDay {
                    Stepper("\(max)× in 24 Std.", value: maxPerDayValue, in: 1...24)
                }
                Toggle("Mindestabstand", isOn: minGapEnabled)
                if let gap = draft.schedule.minGapHours {
                    Stepper("\(MedicationSchedule.hoursLabel(gap)) Abstand", value: minGapValue, in: 0.5...48, step: 0.5)
                }
            }
        } header: {
            Text("Zeitplan")
        } footer: {
            if let message = draft.schedule.validationMessage {
                Text(message).foregroundStyle(.orange)
            } else {
                Text(draft.schedule.summary)
            }
        }
    }

    @ViewBuilder
    private var scheduleDetails: some View {
        let kind = draft.schedule.kind
        if kind == .taper {
            Section {
                ForEach(Array(draft.schedule.taperSteps.enumerated()), id: \.offset) { index, step in
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Stufe \(index + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Stepper("\(step.days) \(step.days == 1 ? "Tag" : "Tage")", value: taperDaysBinding(index), in: 1...120)
                        AmountStepper(title: "Menge", amount: taperAmountBinding(index), form: draft.form)
                    }
                }
                .onDelete { offsets in
                    draft.schedule.taperSteps.remove(atOffsets: offsets)
                }
                Button {
                    let last = draft.schedule.taperSteps.last
                    let amount = max(draft.form.amountStep, (last?.amount ?? 2) / 2)
                    draft.schedule.taperSteps.append(TaperStep(days: last?.days ?? 5, amount: amount))
                } label: {
                    Label("Stufe hinzufügen", systemImage: "plus.circle")
                }
            } header: {
                Text("Stufen")
            } footer: {
                Text("Nach der letzten Stufe endet der Plan automatisch.")
            }
        }
        if kind != .interval && kind != .asNeeded {
            Section {
                ForEach(Array(draft.schedule.times.enumerated()), id: \.offset) { index, _ in
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        DatePicker("Uhrzeit", selection: timeBinding(index), displayedComponents: .hourAndMinute)
                        if kind != .taper {
                            AmountStepper(title: "Menge", amount: timeAmountBinding(index), form: draft.form)
                        }
                    }
                }
                .onDelete { offsets in
                    draft.schedule.times.remove(atOffsets: offsets)
                }
                Button {
                    addTime()
                } label: {
                    Label("Uhrzeit hinzufügen", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("medEditor.addTime")
            } header: {
                Text("Uhrzeiten")
            }
        }
    }

    private var timingSection: some View {
        Section {
            Picker("Hinweis", selection: $draft.timing) {
                ForEach(MealTiming.allCases) { timing in
                    Text(timing.title).tag(timing)
                }
            }
            DatePicker("Beginn", selection: $draft.startDate, displayedComponents: .date)
            if draft.schedule.kind != .taper {
                Toggle("Enddatum", isOn: $draft.hasEndDate)
                if draft.hasEndDate {
                    DatePicker("Letzter Tag", selection: $draft.endDate, in: draft.startDate..., displayedComponents: .date)
                }
            }
        } header: {
            Text("Einnahme")
        }
    }

    private var reminderSection: some View {
        Section {
            Picker("Erinnerung", selection: $draft.reminderStyle) {
                ForEach(ReminderStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!draft.schedule.isScheduled)
        } header: {
            Text("Erinnerung")
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                switch (draft.schedule.isScheduled, draft.reminderStyle) {
                case (false, _):
                    Text("Bei Bedarf gibt es keine Erinnerungen.")
                case (true, .none):
                    Text("Keine Erinnerung. Die Einnahmen stehen trotzdem auf „Heute“.")
                case (true, .notification):
                    Text("Mitteilung mit „Genommen“, „In 10 Min“ und „Auslassen“. Nach 30 Minuten fragt Tagwerk noch einmal nach.")
                case (true, .alarm):
                    Text("Klingelt wie ein Wecker, auch im Stumm- und Fokusmodus, mit Knopf „Genommen“. Für wichtige Medikamente.")
                }
            }
        }
    }

    private var stockSection: some View {
        Section {
            Toggle("Vorrat mitzählen", isOn: $draft.tracksStock)
            if draft.tracksStock {
                HStack {
                    Text("Vorrat")
                    Spacer()
                    TextField("0", text: $draft.stockText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                    Text(draft.form.unit(for: 2))
                        .foregroundStyle(.secondary)
                }
                Stepper("Warnen \(draft.refillThresholdDays) Tage vorher", value: $draft.refillThresholdDays, in: 1...60)
                Toggle("Aufgabe „Nachschub besorgen“ anlegen", isOn: $draft.autoRefillTask)
            }
        } header: {
            Text("Vorrat")
        } footer: {
            if draft.tracksStock {
                Text("„Genommen“ zieht automatisch ab. Wird es knapp, erinnert Tagwerk morgens um 9 Uhr.")
            }
        }
    }

    private var appearanceSection: some View {
        Section("Aussehen") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s) {
                    ForEach(ListColor.allCases) { color in
                        Button {
                            draft.colorName = color.rawValue
                        } label: {
                            Circle()
                                .fill(color.color)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if draft.colorName == color.rawValue {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(color.rawValue)
                    }
                }
                .padding(.vertical, Spacing.xxs)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: Spacing.s) {
                ForEach(MedicationSymbols.all, id: \.self) { symbol in
                    Button {
                        draft.symbol = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.body)
                            .frame(width: 40, height: 40)
                            .foregroundStyle(draft.symbol == symbol ? Color.white : ListColor.color(named: draft.colorName))
                            .background(
                                draft.symbol == symbol ? ListColor.color(named: draft.colorName) : ListColor.color(named: draft.colorName).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, Spacing.xxs)
        }
    }

    private var notesSection: some View {
        Section("Notizen") {
            TextField("z. B. mit viel Wasser, nicht mit Milch", text: $draft.notes, axis: .vertical)
                .lineLimit(2...6)
        }
    }

    private var manageSection: some View {
        Section {
            Toggle("Aktiv", isOn: $draft.isActive)
            Button("Medikament löschen", role: .destructive) {
                confirmDelete = true
            }
        } footer: {
            Text("Pausierte Medikamente erinnern nicht und erscheinen nicht auf „Heute“. Das Protokoll bleibt erhalten.")
        }
    }

    // MARK: Bindungen

    private func date(from time: DoseTime) -> Date {
        calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: .now) ?? .now
    }

    private func timeBinding(_ index: Int) -> Binding<Date> {
        Binding(
            get: { index < draft.schedule.times.count ? date(from: draft.schedule.times[index]) : .now },
            set: { newValue in
                guard index < draft.schedule.times.count else { return }
                let parts = calendar.dateComponents([.hour, .minute], from: newValue)
                draft.schedule.times[index].hour = parts.hour ?? 8
                draft.schedule.times[index].minute = parts.minute ?? 0
            }
        )
    }

    private func timeAmountBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { index < draft.schedule.times.count ? draft.schedule.times[index].amount : 1 },
            set: { newValue in
                guard index < draft.schedule.times.count else { return }
                draft.schedule.times[index].amount = newValue
            }
        )
    }

    private func taperDaysBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { index < draft.schedule.taperSteps.count ? draft.schedule.taperSteps[index].days : 1 },
            set: { newValue in
                guard index < draft.schedule.taperSteps.count else { return }
                draft.schedule.taperSteps[index].days = newValue
            }
        )
    }

    private func taperAmountBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { index < draft.schedule.taperSteps.count ? draft.schedule.taperSteps[index].amount : 1 },
            set: { newValue in
                guard index < draft.schedule.taperSteps.count else { return }
                draft.schedule.taperSteps[index].amount = newValue
            }
        )
    }

    private var intervalStartBinding: Binding<Date> {
        Binding(
            get: { date(from: draft.schedule.intervalStart) },
            set: { newValue in
                let parts = calendar.dateComponents([.hour, .minute], from: newValue)
                draft.schedule.intervalStart.hour = parts.hour ?? 6
                draft.schedule.intervalStart.minute = parts.minute ?? 0
            }
        )
    }

    private var maxPerDayEnabled: Binding<Bool> {
        Binding(
            get: { draft.schedule.maxPerDay != nil },
            set: { draft.schedule.maxPerDay = $0 ? (draft.schedule.maxPerDay ?? 3) : nil }
        )
    }

    private var maxPerDayValue: Binding<Int> {
        Binding(get: { draft.schedule.maxPerDay ?? 3 }, set: { draft.schedule.maxPerDay = $0 })
    }

    private var minGapEnabled: Binding<Bool> {
        Binding(
            get: { draft.schedule.minGapHours != nil },
            set: { draft.schedule.minGapHours = $0 ? (draft.schedule.minGapHours ?? 6) : nil }
        )
    }

    private var minGapValue: Binding<Double> {
        Binding(get: { draft.schedule.minGapHours ?? 6 }, set: { draft.schedule.minGapHours = $0 })
    }

    // MARK: Aktionen

    private func addTime() {
        let last = draft.schedule.times.sorted().last
        let hour = min(23, (last?.hour ?? 7) + (last == nil ? 1 : 4))
        draft.schedule.times.append(DoseTime(hour: hour, minute: last?.minute ?? 0, amount: last?.amount ?? 1))
    }

    private func save() {
        guard draft.isValid else { return }
        let target: Medication
        if let medication {
            target = medication
        } else {
            target = Medication(name: draft.trimmedName, sortIndex: MedicationActions.nextSortIndex(in: context))
            context.insert(target)
        }
        draft.apply(to: target)
        MedicationActions.save(context)
        app.medicationsChanged()

        let style = draft.reminderStyle
        let scheduled = draft.schedule.isScheduled
        Task { @MainActor in
            guard scheduled, style != .none, !AppInfo.isUITesting else { return }
            _ = try? await NotificationSetup.requestAuthorization()
            if style == .alarm {
                // Ohne Wecker-Erlaubnis kommt stattdessen eine Mitteilung (siehe ReminderScheduler).
                _ = try? await AlarmProbe.requestAuthorization()
            }
            app.medicationsChanged()
        }
        dismiss()
    }

    private func deleteMedication() {
        guard let medication else { return }
        // Detailseite schließen, bevor das Medikament verschwindet.
        app.healthPath.removeAll()
        MedicationActions.delete(medication, in: context)
        app.medicationsChanged()
        dismiss()
    }
}

/// Wochentage zum Antippen (Mo zuerst).
struct WeekdayPicker: View {
    @Binding var selection: [Int]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(GermanCalendar.weekdayOrder, id: \.self) { weekday in
                let isOn = selection.contains(weekday)
                Button {
                    if isOn {
                        selection.removeAll { $0 == weekday }
                    } else {
                        selection.append(weekday)
                    }
                } label: {
                    Text(GermanCalendar.shortWeekdays[weekday - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .background(isOn ? ModuleAccent.medication : Color.secondary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(GermanCalendar.longWeekdays[weekday - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}

/// Symbole für Medikamente.
enum MedicationSymbols {
    static let all = [
        "pills.fill", "pill.fill", "capsule.fill", "capsule.portrait.fill", "drop.fill", "syringe.fill",
        "bandage.fill", "cross.vial.fill", "cross.case.fill", "heart.fill", "leaf.fill", "sun.max.fill",
        "moon.fill", "bolt.heart.fill", "allergens", "lungs.fill", "brain.head.profile", "eye.fill",
        "wind", "cup.and.saucer.fill", "bag.fill", "hand.raised.fill", "stethoscope", "medical.thermometer.fill",
    ]
}
