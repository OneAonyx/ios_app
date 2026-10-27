import Contacts
import ContactsUI
import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

// MARK: - Geburtstage

/// Geburtstage nach dem nächsten Termin, mit Übernahme aus den Kontakten.
struct BirthdaysListView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: \Birthday.name) private var birthdays: [Birthday]
    @State private var editing: Birthday?
    @State private var adding = false
    @State private var importing = false
    @State private var importMessage: String?

    var body: some View {
        let now = Date.now
        let calendar = AppModel.calendar
        let sorted = birthdays.sorted { BirthdayLogic.daysUntil($0.fact, now: now, calendar: calendar) < BirthdayLogic.daysUntil($1.fact, now: now, calendar: calendar) }
        List {
            if let importMessage {
                Section {
                    Label(importMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            Section {
                ForEach(sorted) { birthday in
                    Button {
                        editing = birthday
                    } label: {
                        BirthdayRow(birthday: birthday, now: now)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for index in offsets { LifeActions.delete(sorted[index], in: context) }
                    app.lifeChanged()
                }
            }
            Section {
                Button {
                    importing = true
                } label: {
                    Label("Aus Kontakten übernehmen", systemImage: "person.crop.circle.badge.plus")
                }
            } footer: {
                Text("Wähle Kontakte mit Geburtstag aus. Orbit liest nur, was du auswählst, und braucht keinen Zugriff auf alle Kontakte.")
            }
        }
        .overlay {
            if birthdays.isEmpty {
                ContentUnavailableView("Noch keine Geburtstage", systemImage: "gift", description: Text("Trag Geburtstage ein oder übernimm sie aus deinen Kontakten."))
            }
        }
        .navigationTitle("Geburtstage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    adding = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Geburtstag hinzufügen")
            }
        }
        .sheet(item: $editing) { birthday in
            BirthdayEditorView(birthday: birthday)
        }
        .sheet(isPresented: $adding) {
            BirthdayEditorView(birthday: nil)
        }
        .sheet(isPresented: $importing) {
            ContactBirthdayPicker { contacts in
                var count = 0
                for contact in contacts {
                    guard let birthday = contact.birthday, let day = birthday.day, let month = birthday.month else { continue }
                    let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                    LifeActions.addBirthday(name: name.isEmpty ? contact.organizationName : name, day: day, month: month, year: birthday.year, in: context)
                    count += 1
                }
                importMessage = count == 1 ? "1 Geburtstag übernommen." : "\(count) Geburtstage übernommen."
                app.lifeChanged()
            }
            .ignoresSafeArea()
        }
    }
}

struct BirthdayRow: View {
    let birthday: Birthday
    let now: Date

    var body: some View {
        let calendar = AppModel.calendar
        let fact = birthday.fact
        let days = BirthdayLogic.daysUntil(fact, now: now, calendar: calendar)
        HStack(spacing: Spacing.s) {
            IconBadge(systemImage: days == 0 ? "party.popper.fill" : "gift", tint: days <= 7 ? .pink : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(BirthdayLogic.headline(fact, now: now, calendar: calendar))
                    .font(.body.weight(.semibold))
                Text(BirthdayLogic.dateText(fact) + (birthday.note.isEmpty ? "" : " · \(birthday.note)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(BirthdayLogic.whenText(fact, now: now, calendar: calendar))
                .font(.subheadline.weight(days <= 7 ? .semibold : .regular))
                .foregroundStyle(days <= 7 ? Color.pink : Color.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct BirthdayEditorView: View {
    let birthday: Birthday?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var name = ""
    @State private var day = 1
    @State private var month = 1
    @State private var knowsYear = false
    @State private var year = 1995
    @State private var reminderDays = 3
    @State private var note = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .accessibilityIdentifier("birthday.name")
                    Picker("Tag", selection: $day) {
                        ForEach(1...31, id: \.self) { Text("\($0).").tag($0) }
                    }
                    Picker("Monat", selection: $month) {
                        ForEach(1...12, id: \.self) { Text(GermanCalendar.shortMonths[$0 - 1]).tag($0) }
                    }
                    Toggle("Jahr bekannt", isOn: $knowsYear)
                    if knowsYear {
                        Picker("Jahr", selection: $year) {
                            ForEach((1920...Calendar.current.component(.year, from: .now)).reversed(), id: \.self) { Text(String($0)).tag($0) }
                        }
                    }
                }
                Section {
                    Stepper(reminderDays == 0 ? "Nur am Tag selbst" : "\(reminderDays) Tage vorher erinnern", value: $reminderDays, in: 0...30)
                    TextField("Geschenkideen, Notiz", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle(birthday == nil ? "Neuer Geburtstag" : "Geburtstag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("birthday.save")
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let birthday {
                    name = birthday.name
                    day = birthday.day
                    month = birthday.month
                    knowsYear = birthday.year != nil
                    year = birthday.year ?? year
                    reminderDays = birthday.reminderDaysBefore
                    note = birthday.note
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let birthday {
            birthday.name = trimmed
            birthday.day = day
            birthday.month = month
            birthday.year = knowsYear ? year : nil
            birthday.reminderDaysBefore = reminderDays
            birthday.note = note
            LifeActions.save(context)
        } else {
            let created = LifeActions.addBirthday(name: trimmed, day: day, month: month, year: knowsYear ? year : nil, reminderDaysBefore: reminderDays, in: context)
            created.note = note
            LifeActions.save(context)
        }
        app.lifeChanged()
        dismiss()
    }
}

/// Kontakte mit Geburtstag auswählen (ohne Zugriff auf das ganze Adressbuch).
struct ContactBirthdayPicker: UIViewControllerRepresentable {
    let onPick: ([CNContact]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForEnablingContact = NSPredicate(format: "birthday != nil")
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: ([CNContact]) -> Void

        init(onPick: @escaping ([CNContact]) -> Void) {
            self.onPick = onPick
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            onPick(contacts)
        }
    }
}

// MARK: - Tagebuch

/// Frage des Tages, Notiz und „Top 3 für morgen“.
struct JournalEditorView: View {
    var day: Date = .now

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var answer = ""
    @State private var text = ""
    @State private var tomorrow = ["", "", ""]
    @State private var planned = 0
    @State private var loaded = false

    var body: some View {
        let calendar = AppModel.calendar
        let existing = LifeActions.journal(on: day, calendar: calendar, in: context)
        let prompt = existing?.prompt ?? JournalPrompts.prompt(for: day, calendar: calendar)
        let isToday = calendar.isDateInToday(day)
        NavigationStack {
            Form {
                Section {
                    TextField("Ein, zwei Sätze reichen", text: $answer, axis: .vertical)
                        .lineLimit(2...6)
                        .accessibilityIdentifier("journal.answer")
                } header: {
                    Text(prompt)
                        .textCase(nil)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                }
                Section("Notiz") {
                    TextField("Was sonst noch war", text: $text, axis: .vertical)
                        .lineLimit(2...10)
                }
                if isToday {
                    Section {
                        ForEach(tomorrow.indices, id: \.self) { index in
                            TextField("\(index + 1). Aufgabe", text: $tomorrow[index])
                                .accessibilityIdentifier("journal.tomorrow.\(index)")
                        }
                        Button("Als Fokus für morgen anlegen") {
                            planned = LifeActions.planTomorrow(tomorrow, calendar: calendar, in: context).count
                            tomorrow = ["", "", ""]
                            app.tasksChanged()
                        }
                        .disabled(tomorrow.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                        if planned > 0 {
                            Label(planned == 1 ? "1 Aufgabe für morgen angelegt." : "\(planned) Aufgaben für morgen angelegt.", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    } header: {
                        Text("Top 3 für morgen")
                    } footer: {
                        Text("Landen als Aufgaben mit Fälligkeit morgen im Fokus.")
                    }
                }
            }
            .navigationTitle(isToday ? "Tagebuch heute" : GermanCalendar.shortDate(day, calendar: calendar))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        LifeActions.saveJournal(answer: answer, text: text, on: day, calendar: calendar, in: context)
                        dismiss()
                    }
                    .accessibilityIdentifier("journal.done")
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                answer = existing?.answer ?? ""
                text = existing?.text ?? ""
            }
        }
    }
}

/// Alle Tagebucheinträge.
struct JournalListView: View {
    @Query(sort: \JournalEntry.day, order: .reverse) private var entries: [JournalEntry]
    @State private var editingDay: DayRef?

    struct DayRef: Identifiable {
        let day: Date
        var id: Date { day }
    }

    var body: some View {
        List {
            ForEach(entries) { entry in
                Button {
                    editingDay = DayRef(day: entry.day)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(GermanCalendar.shortDate(entry.day, calendar: AppModel.calendar, includeYear: true))
                            .font(.subheadline.weight(.semibold))
                        if !entry.answer.isEmpty {
                            Text(entry.prompt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(entry.answer)
                                .font(.subheadline)
                        }
                        if !entry.text.isEmpty {
                            Text(entry.text)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .foregroundStyle(Color.primary)
                }
            }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("Noch keine Einträge", systemImage: "book.closed", description: Text("Abends fragt Orbit nach deinem Tag."))
            }
        }
        .navigationTitle("Tagebuch")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingDay) { ref in
            JournalEditorView(day: ref.day)
        }
    }
}
