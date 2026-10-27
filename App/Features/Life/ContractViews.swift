import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

extension ContractStatus {
    var color: Color {
        switch self {
        case .running: .secondary
        case .dueSoon: .orange
        case .expired: .red
        case .cancelled: .secondary
        }
    }
}

/// Verträge, Abos, Versicherungen und Dokumente mit Fristen und Fixkosten.
struct ContractsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Contract.name) private var contracts: [Contract]
    @State private var adding = false

    var body: some View {
        let now = Date.now
        let calendar = AppModel.calendar
        let totals = ContractLogic.totals(contracts.map(\.fact))
        List {
            if totals.monthly > 0 {
                Section {
                    HStack {
                        StatTile(title: "Fixkosten im Monat", value: ContractLogic.euro(totals.monthly), tint: ModuleAccent.tasks)
                        StatTile(title: "Im Jahr", value: ContractLogic.euro(totals.yearly), tint: .primary)
                    }
                    .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.s, bottom: Spacing.xs, trailing: Spacing.s))
                } footer: {
                    Text("Laufende Verträge, Abos und Versicherungen (ohne gekündigte und einmalige).")
                }
            }
            ForEach(ContractKind.allCases) { kind in
                let items = contracts.filter { $0.kind == kind }
                if !items.isEmpty {
                    Section(sectionTitle(kind)) {
                        ForEach(items) { contract in
                            NavigationLink {
                                ContractEditorView(contract: contract)
                            } label: {
                                ContractRow(contract: contract, now: now, calendar: calendar)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { LifeActions.delete(items[index], in: context) }
                        }
                    }
                }
            }
        }
        .overlay {
            if contracts.isEmpty {
                ContentUnavailableView {
                    Label("Noch nichts eingetragen", systemImage: "doc.text")
                } description: {
                    Text("Trag Verträge, Abos, Versicherungen und Dokumente wie den Personalausweis ein. Orbit erinnert an Kündigungsfristen und Ablaufdaten.")
                } actions: {
                    Button("Hinzufügen") { adding = true }
                }
            }
        }
        .navigationTitle("Verträge & Fristen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    adding = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Vertrag oder Frist hinzufügen")
                .accessibilityIdentifier("contracts.add")
            }
        }
        .sheet(isPresented: $adding) {
            ContractTemplatePicker()
        }
    }

    private func sectionTitle(_ kind: ContractKind) -> String {
        switch kind {
        case .subscription: "Abos"
        case .contract: "Verträge"
        case .insurance: "Versicherungen"
        case .document: "Dokumente und Fristen"
        }
    }
}

struct ContractRow: View {
    let contract: Contract
    let now: Date
    let calendar: Calendar

    var body: some View {
        let fact = contract.fact
        let status = ContractLogic.status(fact, now: now, calendar: calendar)
        HStack(spacing: Spacing.s) {
            IconBadge(systemImage: contract.kind.symbol, tint: status.needsAttention ? .orange : ModuleAccent.tasks)
            VStack(alignment: .leading, spacing: 2) {
                Text(contract.name)
                    .font(.body.weight(.semibold))
                    .strikethrough(contract.isCancelled)
                Text(ContractLogic.statusText(fact, now: now, calendar: calendar))
                    .font(.caption)
                    .foregroundStyle(status.color)
            }
            Spacer(minLength: 0)
            if let cost = contract.cost, contract.kind.hasCost {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(ContractLogic.euro(cost))
                        .font(.subheadline.monospacedDigit())
                    Text(contract.billing.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Vorlage wählen (Fitnessstudio, Personalausweis …) oder leer anfangen.
struct ContractTemplatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var created: Contract?

    var body: some View {
        NavigationStack {
            List {
                ForEach(ContractKind.allCases) { kind in
                    let templates = LifeTemplates.contracts.filter { $0.kind == kind }
                    Section(kind.title) {
                        ForEach(templates) { template in
                            Button {
                                created = LifeActions.createContract(from: template, in: context)
                            } label: {
                                Label(template.name, systemImage: kind.symbol)
                            }
                            .accessibilityIdentifier("contractTemplate.\(template.name)")
                        }
                        Button {
                            created = LifeActions.createContract(
                                from: LifeTemplates.ContractTemplate(name: "", kind: kind, billing: kind == .document ? .once : .monthly, notice: .none, reminderDaysBefore: kind == .document ? 60 : 14),
                                in: context
                            )
                        } label: {
                            Label("Eigene(r) \(kind.title)", systemImage: "plus")
                        }
                    }
                }
            }
            .navigationTitle("Hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .navigationDestination(item: $created) { contract in
                ContractEditorView(contract: contract, onDone: { dismiss() })
            }
        }
    }
}

/// Vertrag, Abo, Versicherung oder Dokument bearbeiten.
struct ContractEditorView: View {
    @Bindable var contract: Contract
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var hasStart = false
    @State private var hasEnd = false
    @State private var hasMinimumTerm = false
    @State private var loaded = false

    var body: some View {
        let now = Date.now
        let calendar = AppModel.calendar
        let isDocument = contract.kind == .document
        Form {
            Section {
                TextField("Name", text: $contract.name)
                    .accessibilityIdentifier("contract.name")
                if !isDocument {
                    TextField("Anbieter (optional)", text: $contract.provider)
                }
                Picker("Art", selection: Binding(get: { contract.kind }, set: { contract.kind = $0 })) {
                    ForEach(ContractKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
            } footer: {
                Text(ContractLogic.statusText(contract.fact, now: now, calendar: calendar))
            }

            if isDocument {
                Section {
                    DatePicker("Gültig bis", selection: Binding(
                        get: { contract.endDate ?? calendar.date(byAdding: .year, value: 1, to: now) ?? now },
                        set: { contract.endDate = calendar.startOfDay(for: $0) }
                    ), displayedComponents: .date)
                } footer: {
                    Text("Ablaufdatum, z. B. vom Ausweis, Führerschein oder der nächsten Hauptuntersuchung.")
                }
            } else {
                Section("Kosten") {
                    HStack {
                        Text("Betrag")
                        Spacer()
                        TextField("0,00", value: $contract.cost, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110)
                            .accessibilityIdentifier("contract.cost")
                        Text("€")
                            .foregroundStyle(.secondary)
                    }
                    Picker("Rhythmus", selection: Binding(get: { contract.billing }, set: { contract.billing = $0 })) {
                        ForEach(BillingCycle.allCases) { cycle in
                            Text(cycle.title.capitalizedFirst).tag(cycle)
                        }
                    }
                }
                Section {
                    Toggle("Vertragsbeginn", isOn: $hasStart)
                    if hasStart {
                        DatePicker("Beginn", selection: Binding(
                            get: { contract.startDate ?? now },
                            set: { contract.startDate = calendar.startOfDay(for: $0) }
                        ), displayedComponents: .date)
                        Toggle("Mindestlaufzeit", isOn: $hasMinimumTerm)
                        if hasMinimumTerm {
                            Stepper(value: Binding(get: { contract.minimumTermMonths ?? 12 }, set: { contract.minimumTermMonths = $0 }), in: 1...60) {
                                Text("\(contract.minimumTermMonths ?? 12) Monate")
                            }
                        }
                    }
                    Toggle("Festes Ende", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("Ende", selection: Binding(
                            get: { contract.endDate ?? now },
                            set: { contract.endDate = calendar.startOfDay(for: $0) }
                        ), displayedComponents: .date)
                    }
                    Picker("Danach", selection: Binding(get: { contract.renewalMonths ?? 0 }, set: { contract.renewalMonths = $0 == 0 ? nil : $0 })) {
                        Text("monatlich kündbar").tag(0)
                        Text("verlängert sich um 1 Monat").tag(1)
                        Text("verlängert sich um 12 Monate").tag(12)
                    }
                } header: {
                    Text("Laufzeit")
                } footer: {
                    Text("Seit März 2022 sind neue Verträge nach der Mindestlaufzeit meist monatlich kündbar. Ältere verlängern sich oft um 12 Monate.")
                }
                Section("Kündigungsfrist") {
                    Stepper(value: $contract.noticeValue, in: 0...24) {
                        Text(contract.notice.text)
                    }
                    if contract.noticeValue > 0 {
                        Picker("Einheit", selection: Binding(get: { contract.notice.unit }, set: { contract.noticeUnitRaw = $0.rawValue })) {
                            Text("Tage").tag(NoticePeriod.Unit.days)
                            Text("Wochen").tag(NoticePeriod.Unit.weeks)
                            Text("Monate").tag(NoticePeriod.Unit.months)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            Section {
                Stepper(value: $contract.reminderDaysBefore, in: 0...120, step: contract.reminderDaysBefore >= 14 ? 7 : 1) {
                    Text(contract.reminderDaysBefore == 0 ? "Nur am Tag selbst" : "\(contract.reminderDaysBefore) Tage vorher")
                }
                if !isDocument {
                    Toggle("Gekündigt", isOn: $contract.isCancelled)
                }
                TextField("Notiz (Kundennummer, Kontakt …)", text: $contract.note, axis: .vertical)
                    .lineLimit(1...4)
            } header: {
                Text("Erinnerung")
            }
        }
        .navigationTitle(contract.name.isEmpty ? contract.kind.title : contract.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        finish()
                        onDone()
                    }
                    .accessibilityIdentifier("contract.done")
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            hasStart = contract.startDate != nil
            hasEnd = contract.endDate != nil && contract.kind != .document
            hasMinimumTerm = contract.minimumTermMonths != nil
        }
        .onChange(of: hasStart) { _, isOn in
            if !isOn { contract.startDate = nil; contract.minimumTermMonths = nil; hasMinimumTerm = false } else if contract.startDate == nil { contract.startDate = calendar.startOfDay(for: now) }
        }
        .onChange(of: hasMinimumTerm) { _, isOn in
            if !isOn { contract.minimumTermMonths = nil } else if contract.minimumTermMonths == nil { contract.minimumTermMonths = 12 }
        }
        .onChange(of: hasEnd) { _, isOn in
            if !isOn, contract.kind != .document { contract.endDate = nil } else if isOn, contract.endDate == nil { contract.endDate = calendar.startOfDay(for: now) }
        }
        .onDisappear(perform: finish)
    }

    private func finish() {
        if contract.name.trimmingCharacters(in: .whitespaces).isEmpty {
            contract.name = contract.kind.title
        }
        if contract.kind == .document, contract.endDate == nil {
            contract.endDate = AppModel.calendar.date(byAdding: .year, value: 1, to: AppModel.calendar.startOfDay(for: .now))
        }
        LifeActions.save(context)
        app.lifeChanged()
    }
}
