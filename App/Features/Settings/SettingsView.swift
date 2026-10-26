import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Environment(CalendarService.self) private var calendarService
    @AppStorage(SettingsKeys.userName) private var userName = ""
    @AppStorage(SettingsKeys.showCalendarEvents) private var showEvents = true
    @AppStorage(SettingsKeys.defaultReminderOffset) private var defaultReminderOffset = 0
    @State private var notificationsAllowed: Bool?

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            List {
                Section("Profil") {
                    TextField("Dein Name", text: $userName)
                        .textContentType(.givenName)
                }

                Section {
                    Toggle("Termine anzeigen", isOn: $showEvents)
                    if calendarService.canRead {
                        NavigationLink("Kalender auswählen") {
                            CalendarSelectionView()
                        }
                    } else {
                        CalendarAccessRow()
                    }
                } header: {
                    Text("Kalender")
                } footer: {
                    Text("Termine erscheinen auf „Heute“, in der Agenda und in der Woche. Neue Termine legst du über die Schnellerfassung an.")
                }

                Section {
                    Picker("Standard-Erinnerung", selection: $defaultReminderOffset) {
                        Text("Keine").tag(-1)
                        ForEach(TaskReminders.presets.map { $0.minutes }, id: \.self) { minutes in
                            Text(TaskReminders.label(forOffset: minutes)).tag(minutes)
                        }
                    }
                    if notificationsAllowed == false {
                        Button("Mitteilungen erlauben") {
                            Task {
                                notificationsAllowed = (try? await NotificationSetup.requestAuthorization()) ?? false
                                app.tasksChanged()
                            }
                        }
                    }
                } header: {
                    Text("Erinnerungen")
                } footer: {
                    Text("Gilt für neue Aufgaben mit Uhrzeit. Ganztägige Aufgaben erinnern um 9 Uhr.")
                }

                BackupSection()

                Section("Orbit") {
                    NavigationLink {
                        RoadmapView()
                    } label: {
                        Label("Fahrplan", systemImage: "map")
                    }
                    NavigationLink {
                        SystemCheckView()
                    } label: {
                        Label("Systemcheck", systemImage: "checkmark.seal")
                    }
                    LabeledContent("Version", value: "\(AppInfo.version) (\(AppInfo.build))")
                    LabeledContent("Signatur", value: SigningInfo.describe())
                    LabeledContent("Widget-Daten", value: AppGroup.isAvailable ? "verfügbar" : "nicht verfügbar")
                    LabeledContent("Installiert über", value: AppGroup.isSideloaded ? "kostenlose Apple-ID" : "Xcode, TestFlight oder Simulator")
                }

                Section {
                    Text("Orbit ist kein Medizinprodukt. Histamin-Bewertungen sind eine Orientierung, und Erinnerungen ersetzen keine ärztliche Beratung. Alle Daten bleiben auf deinem iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Hinweis")
                }
            }
            .navigationTitle("Einstellungen")
            .navigationDestination(isPresented: $app.isShowingSystemCheck) {
                SystemCheckView()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("settings.done")
                }
            }
            .task {
                notificationsAllowed = await NotificationSetup.isAuthorized()
            }
        }
    }
}

/// Datensicherung: jetzt sichern, teilen, wiederherstellen.
private struct BackupSection: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var latestBackup: URL?
    @State private var lastBackupDate: Date?
    @State private var message: String?
    @State private var isImporting = false
    @State private var pendingRestoreURL: URL?

    var body: some View {
        Section {
            Button {
                backUpNow()
            } label: {
                Label("Jetzt sichern", systemImage: "externaldrive.badge.checkmark")
            }
            if let latestBackup {
                ShareLink(item: latestBackup) {
                    Label("Letzte Sicherung teilen", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                isImporting = true
            } label: {
                Label("Sicherung wiederherstellen …", systemImage: "arrow.counterclockwise")
            }
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Datensicherung")
        } footer: {
            Text(footerText)
        }
        .onAppear(perform: refresh)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                pendingRestoreURL = url
            }
        }
        .alert("Sicherung wiederherstellen?", isPresented: restoreAlertBinding) {
            Button("Ersetzen", role: .destructive) { restore() }
            Button("Abbrechen", role: .cancel) { pendingRestoreURL = nil }
        } message: {
            Text("Alle aktuellen Aufgaben und Listen werden durch den Inhalt der Sicherung ersetzt. Der jetzige Stand wird vorher automatisch gesichert.")
        }
    }

    private var footerText: String {
        let last = lastBackupDate.map {
            "Letzte Sicherung: \(DueFormatter.label(due: $0, hasTime: true, now: .now, calendar: AppModel.calendar)). "
        } ?? ""
        return last + "Orbit sichert einmal am Tag automatisch und behält die letzten \(BackupService.keepCount). Du findest sie in der Dateien-App unter „Auf meinem iPhone → Orbit → Backups“."
    }

    private var restoreAlertBinding: Binding<Bool> {
        Binding(get: { pendingRestoreURL != nil }, set: { if !$0 { pendingRestoreURL = nil } })
    }

    private func refresh() {
        latestBackup = BackupService.existingBackups().first
        lastBackupDate = BackupService.lastBackupDate
    }

    private func backUpNow() {
        do {
            try BackupService.writeBackup(context: context, calendar: AppModel.calendar)
            message = "Gesichert."
        } catch {
            message = "Sicherung fehlgeschlagen: \(error.localizedDescription)"
        }
        refresh()
    }

    private func restore() {
        guard let url = pendingRestoreURL else { return }
        pendingRestoreURL = nil
        do {
            let summary = try BackupService.restore(from: url, context: context, calendar: AppModel.calendar)
            message = "Wiederhergestellt: \(summary.tasks) Aufgaben, \(summary.lists) Listen, \(summary.medications) Medikamente."
            app.tasksChanged()
        } catch {
            message = error.localizedDescription
        }
        refresh()
    }
}

/// Welche Kalender in Orbit erscheinen.
struct CalendarSelectionView: View {
    @Environment(CalendarService.self) private var calendarService
    @AppStorage(SettingsKeys.hiddenCalendarIDs) private var hiddenCalendarIDs = ""

    var body: some View {
        let hidden = Set(hiddenCalendarIDs.split(separator: "\n").map(String.init))
        let calendars = calendarService.calendars()
        let groups = Dictionary(grouping: calendars, by: \.sourceTitle)
        List {
            ForEach(groups.keys.sorted(), id: \.self) { source in
                Section(source.isEmpty ? "Kalender" : source) {
                    ForEach(groups[source] ?? []) { calendar in
                        Toggle(isOn: Binding(
                            get: { !hidden.contains(calendar.id) },
                            set: { isVisible in
                                var updated = hidden
                                if isVisible { updated.remove(calendar.id) } else { updated.insert(calendar.id) }
                                hiddenCalendarIDs = updated.sorted().joined(separator: "\n")
                            }
                        )) {
                            HStack(spacing: Spacing.s) {
                                Circle()
                                    .fill(Color(hex: calendar.colorHex))
                                    .frame(width: 12, height: 12)
                                Text(calendar.title)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Kalender")
    }
}

/// Fahrplan der Phasen (vorher auf „Heute“).
struct RoadmapView: View {
    private struct Phase: Identifiable {
        let id: Int
        let title: String
        let detail: String
        let systemImage: String
    }

    private let currentPhase = 2

    private let phases: [Phase] = [
        Phase(id: 0, title: "Fundament & Systemcheck", detail: "Abgeschlossen: 5 von 6 Tests, Health erst mit Developer-Account.", systemImage: "hammer"),
        Phase(id: 1, title: "Heute, Aufgaben, Agenda", detail: "Abgeschlossen: Aufgaben, Schnellerfassung, Kalender, Datensicherung.", systemImage: "checklist"),
        Phase(id: 2, title: "Medikamente", detail: "Einnahmepläne, Erinnerungen mit Knöpfen, Wecker, Vorrat, Widget, Kontrollzentrum, Siri.", systemImage: "pills"),
        Phase(id: 3, title: "Training", detail: "Dein Oberkörper-4er-Plan, Satz-Tracking, Pausen-Timer.", systemImage: "dumbbell"),
        Phase(id: 4, title: "Ernährung & Histamin", detail: "Lexikon, Scanner, Tagebuch, Auslöser-Analyse.", systemImage: "fork.knife"),
        Phase(id: 5, title: "Einblicke & Claude-Brücke", detail: "Wochenrückblick, Arztbericht, Claude über Kurzbefehl.", systemImage: "sparkles"),
        Phase(id: 6, title: "Leben & Feinschliff", detail: "Routinen, Fristen, Verträge, Widgets, Fokus-Filter.", systemImage: "wand.and.stars"),
        Phase(id: 7, title: "Developer-Account & iCloud", detail: "TestFlight, Apple Health, iCloud-Sync.", systemImage: "icloud"),
    ]

    var body: some View {
        List(phases) { phase in
            HStack(alignment: .top, spacing: Spacing.s) {
                IconBadge(
                    systemImage: phase.id < currentPhase ? "checkmark" : phase.systemImage,
                    tint: phase.id < currentPhase ? .green : (phase.id == currentPhase ? ModuleAccent.today : .gray)
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Phase \(phase.id): \(phase.title)")
                            .font(.headline)
                        if phase.id == currentPhase {
                            Text("jetzt")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .foregroundStyle(ModuleAccent.today)
                                .background(ModuleAccent.today.opacity(0.15), in: Capsule())
                        }
                    }
                    Text(phase.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .navigationTitle("Fahrplan")
    }
}
