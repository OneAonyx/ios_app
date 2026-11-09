import SwiftUI
import TagwerkCore
import TagwerkKit

/// Planer → Geld: wer dir etwas schuldet, offene Rechnungen, was du selbst zahlst.
struct MoneyView: View {
    @AppStorage(SettingsKeys.moneyEntries) private var storedText = ""
    @State private var filter: Filter = .incoming
    @State private var adding = false

    enum Filter: String, CaseIterable, Identifiable {
        case incoming, outgoing, settled
        var id: String { rawValue }
        var title: String {
            switch self {
            case .incoming: "Ich bekomme"
            case .outgoing: "Ich zahle"
            case .settled: "Erledigt"
            }
        }
    }

    var body: some View {
        let calendar = AppModel.calendar
        let now = Date.now
        let book = MoneyBook.decode(storedText)
        List {
            Section {
                MoneySummary(book: book, now: now)
                    .listRowInsets(EdgeInsets(top: Spacing.s, leading: Spacing.m, bottom: Spacing.s, trailing: Spacing.m))
                Picker("Anzeigen", selection: $filter) {
                    ForEach(Filter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("money.filter")
            }

            switch filter {
            case .incoming, .outgoing:
                let direction: MoneyEntry.Direction = filter == .incoming ? .incoming : .outgoing
                let open = book.open(direction, now: now, calendar: calendar)
                if open.isEmpty {
                    Section {
                        Text(direction == .incoming
                             ? "Niemand schuldet dir gerade etwas. Trag ein, wenn du Geld verleihst, etwas auslegst oder eine Rechnung stellst."
                             : "Nichts offen. Trag Rechnungen und Geld ein, das du jemandem zurückgeben willst.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(MoneyEntry.Kind.allCases) { kind in
                    let items = open.filter { $0.kind == kind }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { entry in
                                NavigationLink {
                                    MoneyDetailView(entryID: entry.id)
                                } label: {
                                    MoneyRow(entry: entry, now: now)
                                }
                            }
                        } header: {
                            Text(kind == .personal ? "Privat" : "Rechnungen")
                        } footer: {
                            Text("Offen: \(MoneyBook.euro(items.reduce(0) { $0 + $1.openCents }))")
                        }
                    }
                }
                if direction == .incoming, !book.balances.isEmpty {
                    Section {
                        ForEach(book.balances, id: \.name) { balance in
                            LabeledContent(balance.name) {
                                Text(balance.cents > 0 ? "bekommst \(MoneyBook.euro(balance.cents))" : "schuldest \(MoneyBook.euro(-balance.cents))")
                                    .foregroundStyle(balance.cents > 0 ? Color.green : Color.orange)
                                    .monospacedDigit()
                            }
                        }
                    } header: {
                        Text("Je Person, verrechnet")
                    }
                }
            case .settled:
                let settled = book.settled
                if settled.isEmpty {
                    Section {
                        Text("Noch nichts erledigt.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(settled.prefix(100)) { entry in
                            NavigationLink {
                                MoneyDetailView(entryID: entry.id)
                            } label: {
                                MoneyRow(entry: entry, now: now)
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                adding = true
            } label: {
                Label("Eintragen", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: TouchTarget.standard)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xs)
            .accessibilityIdentifier("money.add")
        }
        .sheet(isPresented: $adding) {
            MoneyEditor(entry: nil, direction: filter == .outgoing ? .outgoing : .incoming, known: book.knownCounterparties) { entry in
                var updated = MoneyBook.decode(storedText)
                updated.upsert(entry)
                storedText = MoneyBook.encode(updated)
            }
        }
    }
}

/// Summen oben: bekomme, zahle, überfällig.
private struct MoneySummary: View {
    let book: MoneyBook
    let now: Date

    var body: some View {
        let overdue = book.overdue(now: now, calendar: AppModel.calendar)
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .top, spacing: Spacing.m) {
                total("Ich bekomme", book.openCents(.incoming), .green, "arrow.down.circle.fill")
                total("Ich zahle", book.openCents(.outgoing), .orange, "arrow.up.circle.fill")
            }
            if !overdue.isEmpty {
                Label("\(overdue.count) überfällig: " + overdue.prefix(3).map(\.counterparty).joined(separator: ", "), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func total(_ title: String, _ cents: Int, _ tint: Color, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(MoneyBook.euro(cents))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MoneyRow: View {
    let entry: MoneyEntry
    let now: Date

    var body: some View {
        let calendar = AppModel.calendar
        let overdue = entry.isOverdue(now: now, calendar: calendar)
        HStack(spacing: Spacing.s) {
            IconBadge(systemImage: entry.kind.symbol, tint: entry.direction == .incoming ? .green : .orange, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .lineLimit(2)
                Text(detail(calendar: calendar))
                    .font(.caption)
                    .foregroundStyle(overdue ? Color.red : Color.secondary)
            }
            Spacer(minLength: Spacing.xs)
            Text(MoneyBook.euro(entry.isSettled ? entry.cents : entry.openCents))
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(entry.isSettled ? Color.secondary : (entry.direction == .incoming ? Color.green : Color.primary))
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(calendar: Calendar) -> String {
        var parts = [WeeklyReview.dayMonth(entry.date, calendar: calendar)]
        if entry.isSettled {
            parts.append("erledigt")
        } else {
            if entry.paidCents > 0 { parts.append("\(MoneyBook.euro(entry.paidCents)) von \(MoneyBook.euro(entry.cents)) bezahlt") }
            if let due = entry.dueText(now: now, calendar: calendar) { parts.append(due) }
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Detail

private struct MoneyDetailView: View {
    let entryID: String

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.moneyEntries) private var storedText = ""
    @State private var editing = false
    @State private var paying = false
    @State private var paymentText = ""
    @State private var confirmDelete = false

    var body: some View {
        let calendar = AppModel.calendar
        let book = MoneyBook.decode(storedText)
        if let entry = book.entries.first(where: { $0.id == entryID }) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(entry.direction == .incoming ? "\(entry.counterparty) schuldet dir" : "Du schuldest \(entry.counterparty)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(MoneyBook.euro(entry.openCents))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(entry.isSettled ? Color.secondary : (entry.direction == .incoming ? Color.green : Color.orange))
                        if entry.isSettled {
                            Label("Erledigt", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        } else if let due = entry.dueText(now: .now, calendar: calendar) {
                            Text(due)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(entry.isOverdue(now: .now, calendar: calendar) ? Color.red : Color.secondary)
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                }
                Section {
                    LabeledContent("Art", value: entry.kind.title)
                    if !entry.title.isEmpty { LabeledContent("Wofür", value: entry.title) }
                    LabeledContent("Betrag", value: MoneyBook.euro(entry.cents))
                    LabeledContent("Datum", value: CSVFormat.date(entry.date, calendar: calendar))
                    if let due = entry.dueDate { LabeledContent("Fällig", value: CSVFormat.date(due, calendar: calendar)) }
                    if !entry.note.isEmpty { Text(entry.note).font(.subheadline) }
                }
                if !entry.payments.isEmpty {
                    Section("Zahlungen") {
                        ForEach(entry.payments) { payment in
                            LabeledContent(CSVFormat.date(payment.date, calendar: calendar), value: MoneyBook.euro(payment.cents))
                        }
                    }
                }
                Section {
                    if !entry.isSettled {
                        Button {
                            update { $0.settle(id: entry.id, date: .now) }
                        } label: {
                            Label(entry.direction == .incoming ? "Geld bekommen, erledigt" : "Bezahlt, erledigt", systemImage: "checkmark.circle.fill")
                        }
                        .accessibilityIdentifier("money.settle")
                        Button {
                            paymentText = ""
                            paying = true
                        } label: {
                            Label("Teilzahlung eintragen", systemImage: "eurosign.circle")
                        }
                        if entry.direction == .incoming {
                            ShareLink(item: MoneyBook.reminderText(for: entry, now: .now, calendar: calendar)) {
                                Label("Erinnerung schicken", systemImage: "paperplane")
                            }
                        }
                    } else {
                        Button {
                            update { $0.reopen(id: entry.id) }
                        } label: {
                            Label("Wieder öffnen", systemImage: "arrow.uturn.backward")
                        }
                    }
                    Button {
                        editing = true
                    } label: {
                        Label("Bearbeiten", systemImage: "pencil")
                    }
                    Button("Löschen", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(entry.counterparty)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $editing) {
                MoneyEditor(entry: entry, direction: entry.direction, known: book.knownCounterparties) { edited in
                    update { $0.upsert(edited) }
                }
            }
            .alert("Teilzahlung", isPresented: $paying) {
                TextField("Betrag, z. B. 20,00", text: $paymentText)
                    .keyboardType(.decimalPad)
                Button("Eintragen") {
                    if let cents = MoneyBook.cents(from: paymentText) {
                        update { $0.addPayment(to: entry.id, cents: cents, date: .now) }
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Offen sind \(MoneyBook.euro(entry.openCents)).")
            }
            .confirmationDialog("Eintrag löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    update { $0.remove(id: entry.id) }
                    dismiss()
                }
            }
        } else {
            ContentUnavailableView("Eintrag gelöscht", systemImage: "eurosign.circle")
        }
    }

    private func update(_ change: (inout MoneyBook) -> Void) {
        var book = MoneyBook.decode(storedText)
        change(&book)
        withAnimation { storedText = MoneyBook.encode(book) }
    }
}

// MARK: - Eintragen

private struct MoneyEditor: View {
    let entry: MoneyEntry?
    let direction: MoneyEntry.Direction
    let known: [String]
    let onSave: (MoneyEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDirection: MoneyEntry.Direction = .incoming
    @State private var kind: MoneyEntry.Kind = .personal
    @State private var counterparty = ""
    @State private var title = ""
    @State private var amountText = ""
    @State private var date = Date.now
    @State private var hasDue = false
    @State private var dueDate = Date.now.addingTimeInterval(14 * 86_400)
    @State private var note = ""
    @State private var didLoad = false

    var body: some View {
        let cents = MoneyBook.cents(from: amountText)
        NavigationStack {
            Form {
                Section {
                    Picker("Richtung", selection: $selectedDirection) {
                        Text("Ich bekomme").tag(MoneyEntry.Direction.incoming)
                        Text("Ich zahle").tag(MoneyEntry.Direction.outgoing)
                    }
                    .pickerStyle(.segmented)
                    Picker("Art", selection: $kind) {
                        ForEach(MoneyEntry.Kind.allCases) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }
                    }
                }
                Section {
                    TextField(selectedDirection == .incoming ? "Wer schuldet dir? (Person oder Firma)" : "Wem schuldest du? (Person oder Firma)", text: $counterparty)
                        .textContentType(.name)
                        .accessibilityIdentifier("money.counterparty")
                    if counterparty.isEmpty, !known.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Spacing.xs) {
                                ForEach(known.prefix(8), id: \.self) { name in
                                    Button(name) { counterparty = name }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                    TextField(kind == .invoice ? "Rechnungsnummer oder Leistung" : "Wofür, z. B. Konzertkarten", text: $title)
                    TextField("Betrag in €", text: $amountText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("money.amount")
                    if !amountText.isEmpty, cents == nil {
                        Text("Bitte einen Betrag wie 12,50 eingeben.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    Toggle("Fällig bis", isOn: $hasDue)
                    if hasDue {
                        DatePicker("Fällig am", selection: $dueDate, displayedComponents: .date)
                    }
                    TextField("Notiz", text: $note, axis: .vertical)
                } footer: {
                    Text(kind == .invoice ? "Bei Rechnungen sind 14 oder 30 Tage Zahlungsziel üblich." : "Mit Fälligkeit siehst du, wann du nachfragen solltest.")
                }
            }
            .navigationTitle(entry == nil ? "Geld eintragen" : "Bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        guard let cents else { return }
                        var result = entry ?? MoneyEntry(direction: selectedDirection, kind: kind, counterparty: "", cents: cents, date: date)
                        result.direction = selectedDirection
                        result.kind = kind
                        result.counterparty = counterparty.trimmingCharacters(in: .whitespaces)
                        result.title = title.trimmingCharacters(in: .whitespaces)
                        result.cents = cents
                        result.date = date
                        result.dueDate = hasDue ? dueDate : nil
                        result.note = note
                        onSave(result)
                        dismiss()
                    }
                    .disabled(cents == nil || counterparty.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("money.save")
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                selectedDirection = direction
                if let entry {
                    kind = entry.kind
                    counterparty = entry.counterparty
                    title = entry.title
                    amountText = String(format: "%.2f", Double(entry.cents) / 100).replacingOccurrences(of: ".", with: ",")
                    date = entry.date
                    hasDue = entry.dueDate != nil
                    dueDate = entry.dueDate ?? dueDate
                    note = entry.note
                }
            }
        }
    }
}
