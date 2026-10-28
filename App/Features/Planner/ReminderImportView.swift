import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Einmaliger Import aus Apple Erinnerungen: Listen wählen, übernehmen, fertig.
/// Orbit ändert in Apple Erinnerungen nichts.
struct ReminderImportView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var tasks: [TaskItem]

    private enum Phase: Equatable {
        case needsAccess, denied, loading, ready, done(String)
    }

    @State private var importer: ReminderImporter?
    @State private var phase: Phase = .needsAccess
    @State private var lists: [ReminderImporter.ReminderList] = []
    @State private var reminders: [String: [ExternalReminder]] = [:]
    @State private var selected: Set<String> = []
    @State private var includeCompleted = false

    var body: some View {
        List {
            switch phase {
            case .needsAccess:
                accessSection
            case .denied:
                deniedSection
            case .loading:
                Section {
                    HStack(spacing: Spacing.s) {
                        ProgressView()
                        Text("Erinnerungen werden gelesen …")
                            .foregroundStyle(.secondary)
                    }
                }
            case .ready:
                readySections
            case .done(let summary):
                Section {
                    Label(summary, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("reminderImport.result")
                } footer: {
                    Text("Die Aufgaben stehen jetzt im Planer in Listen mit dem gleichen Namen. Ein zweiter Import überspringt alles, was schon da ist.")
                }
                Section {
                    Button("Weitere Listen übernehmen") {
                        phase = .ready
                    }
                }
            }
        }
        .navigationTitle("Aus Erinnerungen")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if ReminderImporter.isAuthorized {
                await load()
            } else if ReminderImporter.isDenied {
                phase = .denied
            }
        }
    }

    private var accessSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label("Apple Erinnerungen übernehmen", systemImage: "checklist")
                    .font(.headline)
                Text("Orbit liest deine Listen einmal aus und legt sie als Aufgaben an, mit Fälligkeit, Priorität, Notizen und Wiederholung. In Apple Erinnerungen ändert sich nichts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, Spacing.xxs)
            Button {
                Task { await requestAccess() }
            } label: {
                Label("Zugriff erlauben", systemImage: "lock.open")
            }
            .accessibilityIdentifier("reminderImport.allow")
        }
    }

    private var deniedSection: some View {
        Section {
            Text("Orbit hat keinen Zugriff auf Erinnerungen. Du kannst ihn in den Einstellungen unter Orbit → Erinnerungen → „Vollzugriff“ erlauben.")
                .foregroundStyle(.secondary)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Label("Einstellungen öffnen", systemImage: "gear")
            }
        }
    }

    @ViewBuilder
    private var readySections: some View {
        if lists.isEmpty {
            Section {
                Text("Keine Listen in Apple Erinnerungen gefunden.")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                ForEach(lists) { list in
                    Toggle(isOn: binding(for: list.id)) {
                        HStack(spacing: Spacing.s) {
                            Circle()
                                .fill(Color(hex: list.colorHex))
                                .frame(width: 12, height: 12)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(list.title)
                                Text(countText(for: list.id))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Listen")
            }

            Section {
                Toggle("Erledigte auch übernehmen", isOn: $includeCompleted)
            } footer: {
                Text("Erledigte landen im Planer unter „Erledigt“. Ohne diesen Schalter kommen nur offene Erinnerungen mit.")
            }

            Section {
                let count = plan.count
                Button {
                    runImport()
                } label: {
                    Label(count == 0 ? "Nichts Neues zu übernehmen" : "\(count) \(count == 1 ? "Erinnerung" : "Erinnerungen") übernehmen", systemImage: "square.and.arrow.down")
                }
                .disabled(count == 0)
                .accessibilityIdentifier("reminderImport.run")
            } footer: {
                Text("Schon übernommene Erinnerungen werden übersprungen. Erinnerungen ohne Uhrzeit werden ganztägige Aufgaben. Unteraufgaben und Orte kommen nicht mit.")
            }
        }
    }

    private var chosen: [ExternalReminder] {
        selected.flatMap { reminders[$0] ?? [] }
    }

    private var plan: [ImportedTask] {
        ReminderImport.plan(chosen, existingIDs: Set(tasks.map(\.stableID)), includeCompleted: includeCompleted, calendar: AppModel.calendar)
    }

    private func countText(for listID: String) -> String {
        let items = reminders[listID] ?? []
        let open = items.filter { !$0.isCompleted }.count
        let done = items.count - open
        return done == 0 ? "\(open) offen" : "\(open) offen, \(done) erledigt"
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { isOn in
                if isOn { selected.insert(id) } else { selected.remove(id) }
            }
        )
    }

    private func requestAccess() async {
        let importer = importer ?? ReminderImporter()
        self.importer = importer
        if await importer.requestAccess() {
            await load()
        } else {
            phase = .denied
        }
    }

    private func load() async {
        phase = .loading
        let importer = importer ?? ReminderImporter()
        self.importer = importer
        lists = importer.lists()
        reminders = await importer.remindersByList()
        // Vorauswahl: Listen mit offenen Erinnerungen.
        selected = Set(lists.map(\.id).filter { id in (reminders[id] ?? []).contains { !$0.isCompleted } })
        phase = .ready
    }

    private func runImport() {
        let importer = importer ?? ReminderImporter()
        let result = importer.importReminders(chosen, includeCompleted: includeCompleted, calendar: AppModel.calendar, in: context)
        app.tasksChanged()
        phase = .done(result.summary)
    }
}
