import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit
import UniformTypeIdentifiers

/// Unterseiten der Einstellungen (auch für Sprünge aus der Funktions-Suche).
enum SettingsPage: String, Hashable, CaseIterable, Identifiable {
    case todayLayout, reminders, calendar, privacy, data, shortcuts, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todayLayout: "Startseite"
        case .reminders: "Erinnerungen"
        case .calendar: "Kalender"
        case .privacy: "Datenschutz und Gym"
        case .data: "Daten und Sicherung"
        case .shortcuts: "Kurzbefehle"
        case .about: "Über Orbit"
        }
    }

    var detail: String {
        switch self {
        case .todayLayout: "Karten auf „Heute“ wählen und sortieren"
        case .reminders: "Morgen-Briefing, Aufgaben, Rückblick, Tagebuch"
        case .calendar: "Termine anzeigen, Kalender wählen"
        case .privacy: "App-Sperre, Gym-Ankunft"
        case .data: "Sicherung, iCloud Drive, Import"
        case .shortcuts: "Claude und Apple Health"
        case .about: "Fahrplan, Systemcheck, Version"
        }
    }

    var symbol: String {
        switch self {
        case .todayLayout: "rectangle.3.group"
        case .reminders: "bell.badge"
        case .calendar: "calendar"
        case .privacy: "lock.shield"
        case .data: "externaldrive.badge.icloud"
        case .shortcuts: "square.stack.3d.up"
        case .about: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .todayLayout: ModuleAccent.today
        case .reminders: .red
        case .calendar: ModuleAccent.calendar
        case .privacy: .gray
        case .data: .blue
        case .shortcuts: .purple
        case .about: .teal
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKeys.userName) private var userName = ""

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.settingsPath) {
            List {
                Section("Profil") {
                    TextField("Dein Name", text: $userName)
                        .textContentType(.givenName)
                }

                Section {
                    ForEach(SettingsPage.allCases) { page in
                        NavigationLink(value: page) {
                            HStack(spacing: Spacing.s) {
                                IconBadge(systemImage: page.symbol, tint: page.tint, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(page.title)
                                    Text(page.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("settings.page.\(page.rawValue)")
                    }
                }

                Section {
                    NavigationLink {
                        FeatureDirectoryView()
                    } label: {
                        Label("Alle Funktionen", systemImage: "square.grid.2x2")
                    }
                    .accessibilityIdentifier("settings.features")
                } footer: {
                    Text("Alles, was Orbit kann, mit dem Ort in der App. Die Suche auf „Heute“ findet Funktionen auch per Stichwort.")
                }
            }
            .navigationTitle("Einstellungen")
            .navigationDestination(for: SettingsPage.self) { page in
                SettingsPageView(page: page)
            }
            .navigationDestination(isPresented: $app.isShowingSystemCheck) {
                SystemCheckView()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
    }
}

/// Inhalt einer Unterseite.
struct SettingsPageView: View {
    let page: SettingsPage

    @Environment(AppModel.self) private var app
    @Environment(CalendarService.self) private var calendarService
    @AppStorage(SettingsKeys.showCalendarEvents) private var showEvents = true
    @AppStorage(SettingsKeys.defaultReminderOffset) private var defaultReminderOffset = 0
    @AppStorage(SettingsKeys.weeklyReviewReminder) private var weeklyReviewReminder = true
    @AppStorage(SettingsKeys.todayLayout) private var layoutText = ""
    @AppStorage(SettingsKeys.showCheckIns) private var showCheckIns = true
    @Environment(\.modelContext) private var context
    @State private var notificationsAllowed: Bool?
    @State private var exportURL: URL?
    @State private var exportFailed = false

    var body: some View {
        content
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .todayLayout:
            TodayLayoutList(layoutText: $layoutText, initial: legacyLayout)
        case .reminders:
            remindersPage
        case .calendar:
            calendarPage
        case .privacy:
            List { PrivacyGymSection() }
        case .data:
            List {
                BackupSection()
                Section {
                    NavigationLink {
                        ReminderImportView()
                    } label: {
                        Label("Aus Apple Erinnerungen übernehmen", systemImage: "square.and.arrow.down.on.square")
                    }
                    .accessibilityIdentifier("settings.importReminders")
                } header: {
                    Text("Übernehmen")
                }
                Section {
                    Button {
                        exportAll()
                    } label: {
                        Label("Alle Daten als Tabellen (ZIP)", systemImage: "tablecells")
                    }
                    .accessibilityIdentifier("settings.exportTables")
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("\(exportURL.lastPathComponent) teilen", systemImage: "square.and.arrow.up")
                        }
                    }
                    if exportFailed {
                        Label("Der Export ließ sich nicht erstellen.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Export")
                } footer: {
                    Text("Tabellen für Excel oder Numbers: Mahlzeiten, Beschwerden, Schmerzen, Einnahmen, Bewegung, Tageswerte, Aufgaben, Training, Körperwerte, Routinen. Zum Wiederherstellen dient die Datensicherung oben, nicht dieser Export.")
                }
            }
        case .shortcuts:
            List {
                Section {
                    NavigationLink {
                        ClaudeShortcutGuideView()
                    } label: {
                        Label("Claude-Kurzbefehl", systemImage: "sparkles")
                    }
                    NavigationLink {
                        HealthShortcutGuideView()
                    } label: {
                        Label("Health-Kurzbefehl", systemImage: "heart.text.square")
                    }
                } footer: {
                    Text("Ohne Developer-Account übernehmen Kurzbefehle zwei Dinge: Anfragen an Claude über die Claude-App und Werte aus Apple Health. Siri-Sätze und Automationen findest du in der Kurzbefehle-App unter „Orbit“.")
                }
            }
        case .about:
            aboutPage
        }
    }

    private func exportAll() {
        let calendar = AppModel.calendar
        let tables = ExportActions.allTables(calendar: calendar, in: context)
        do {
            exportURL = try ExportActions.zip(
                files: tables.map { (name: $0.fileName, data: $0.data) },
                folderName: "Orbit-Tabellen-\(CSVFormat.fileDate(.now, calendar: calendar))"
            )
            exportFailed = false
        } catch {
            exportFailed = true
        }
    }

    private var legacyLayout: TodayLayout {
        var layout = TodayLayout.decode(layoutText)
        if layoutText.isEmpty, !showCheckIns { layout.setVisible(.checkIn, false) }
        return layout
    }

    private var remindersPage: some View {
        List {
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
                Text("Aufgaben")
            } footer: {
                Text("Gilt für neue Aufgaben mit Uhrzeit. Ganztägige Aufgaben erinnern um 9 Uhr.")
            }

            Section {
                BriefingSettings()
            } header: {
                Text("Tag planen")
            } footer: {
                Text("Eine Mitteilung am Morgen: Termine, Fokus, fällige Aufgaben, Einnahmen, Training und Geburtstage des Tages. Leise, ohne Ton.")
            }

            Section {
                Toggle("Sonntags an Rückblick erinnern", isOn: $weeklyReviewReminder)
                    .onChange(of: weeklyReviewReminder) { _, _ in app.tasksChanged() }
                DiaryReminderSettings()
            } header: {
                Text("Rückblick und Tagebuch")
            } footer: {
                Text("Der Wochenrückblick kommt sonntags um 18 Uhr. Die Tagebuch-Erinnerung kommt nur, wenn Essen, Beschwerden oder Bewegung noch fehlen. Medikamente erinnern nach ihren eigenen Einstellungen.")
            }
        }
        .task {
            notificationsAllowed = await NotificationSetup.isAuthorized()
        }
    }

    private var calendarPage: some View {
        List {
            Section {
                Toggle("Termine anzeigen", isOn: $showEvents)
                if calendarService.canRead {
                    NavigationLink("Kalender auswählen") {
                        CalendarSelectionView()
                    }
                } else {
                    CalendarAccessRow()
                }
            } footer: {
                Text("Termine erscheinen auf „Heute“, in der Agenda und in der Woche. Neue Termine legst du über die Schnellerfassung an.")
            }
        }
    }

    private var aboutPage: some View {
        List {
            Section {
                NavigationLink {
                    RoadmapView()
                } label: {
                    Label("Fahrplan", systemImage: "map")
                }
                .accessibilityIdentifier("settings.roadmap")
                NavigationLink {
                    SystemCheckView()
                } label: {
                    Label("Systemcheck", systemImage: "checkmark.seal")
                }
                .accessibilityIdentifier("settings.systemcheck")
            }
            Section("Orbit") {
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
    }
}

/// Datensicherung: jetzt sichern, teilen, wiederherstellen.
private struct BackupSection: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var latestBackup: URL?
    @State private var lastBackupDate: Date?
    @State private var message: String?
    @State private var importMode: ImportMode = .restore
    @State private var isImporting = false
    @State private var pendingRestoreURL: URL?
    @State private var externalName: String?
    @State private var externalLast: Date?
    @State private var externalError: String?

    /// Ein gemeinsamer Dateien-Dialog (zwei `.fileImporter` an einer Ansicht vertragen sich nicht).
    private enum ImportMode {
        case restore, folder
    }

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
                importMode = .restore
                isImporting = true
            } label: {
                Label("Sicherung wiederherstellen …", systemImage: "arrow.counterclockwise")
            }
            if let externalName {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Zweiter Ort: \(externalName)", systemImage: "icloud.and.arrow.up")
                    Text(externalStatus)
                        .font(.caption)
                        .foregroundStyle(externalError == nil ? Color.secondary : Color.orange)
                }
                .accessibilityElement(children: .combine)
                Button("Anderen Ordner wählen …") {
                    importMode = .folder
                    isImporting = true
                }
                Button("Zweiten Ort entfernen", role: .destructive) {
                    ExternalBackup.remove()
                    refresh()
                }
            } else {
                Button {
                    importMode = .folder
                    isImporting = true
                } label: {
                    Label("Zusätzlich in iCloud Drive sichern …", systemImage: "icloud.and.arrow.up")
                }
                .accessibilityIdentifier("backup.external")
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
        .fileImporter(isPresented: $isImporting, allowedContentTypes: importMode == .folder ? [.folder] : [.json]) { result in
            guard case .success(let url) = result else { return }
            if importMode == .folder {
                chooseFolder(url)
            } else {
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
        return last + "Orbit sichert einmal am Tag automatisch und behält die letzten \(BackupService.keepCount). Du findest sie in der Dateien-App unter „Auf meinem iPhone → Orbit → Backups“. Mit einem zweiten Ort in iCloud Drive sind sie auch sicher, wenn das iPhone verloren geht."
    }

    private var externalStatus: String {
        if let externalError { return "Zuletzt fehlgeschlagen: \(externalError)" }
        guard let externalLast else { return "Noch keine Kopie. „Jetzt sichern“ legt die erste an." }
        return "Letzte Kopie: \(DueFormatter.label(due: externalLast, hasTime: true, now: .now, calendar: AppModel.calendar))"
    }

    private func chooseFolder(_ url: URL) {
        do {
            try ExternalBackup.setFolder(url)
            try BackupService.writeBackup(context: context, calendar: AppModel.calendar)
            message = ExternalBackup.lastError == nil ? "Ordner „\(url.lastPathComponent)“ gewählt und erste Kopie gesichert." : nil
        } catch {
            message = "Ordner ließ sich nicht verwenden: \(error.localizedDescription)"
        }
        refresh()
    }

    private var restoreAlertBinding: Binding<Bool> {
        Binding(get: { pendingRestoreURL != nil }, set: { if !$0 { pendingRestoreURL = nil } })
    }

    private func refresh() {
        latestBackup = BackupService.existingBackups().first
        lastBackupDate = BackupService.lastBackupDate
        externalName = ExternalBackup.isConfigured ? (ExternalBackup.folderName ?? "Ordner") : nil
        externalLast = ExternalBackup.lastCopy
        externalError = ExternalBackup.lastError
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
            message = "Wiederhergestellt: \(summary.tasks) Aufgaben, \(summary.lists) Listen, \(summary.medications) Medikamente, \(summary.workouts) Trainingseinheiten, \(summary.meals) Mahlzeiten, \(summary.checkIns) Check-ins, \(summary.diaryEntries) Tagebuch-Einträge, \(summary.healthDays) Health-Tage."
            app.tasksChanged()
            app.nutritionChanged()
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

    private let currentPhase = 14

    private let phases: [Phase] = [
        Phase(id: 0, title: "Fundament & Systemcheck", detail: "Abgeschlossen: 5 von 6 Tests, Health erst mit Developer-Account.", systemImage: "hammer"),
        Phase(id: 1, title: "Heute, Aufgaben, Agenda", detail: "Abgeschlossen: Aufgaben, Schnellerfassung, Kalender, Datensicherung.", systemImage: "checklist"),
        Phase(id: 2, title: "Medikamente", detail: "Abgeschlossen: Einnahmepläne, Erinnerungen, Wecker, Vorrat, Widget, Kontrollzentrum, Siri.", systemImage: "pills"),
        Phase(id: 3, title: "Training", detail: "Abgeschlossen: Oberkörper-4er, Satz-Tracking mit Vorschlag, Pausen-Timer in der Dynamic Island, Statistik.", systemImage: "dumbbell"),
        Phase(id: 4, title: "Ernährung & Histamin", detail: "Abgeschlossen: Lexikon, Barcode- und Zutaten-Scan, Tagebuch mit Tageslast, Beschwerden und Muster, Einkauf, Rezepte, Wochenplan.", systemImage: "fork.knife"),
        Phase(id: 5, title: "Einblicke & Claude-Brücke", detail: "Abgeschlossen: Check-ins, Wochenrückblick, Arztbericht als PDF, Claude für Trainingsplan, Lebensmittel, Rezepte, Muster und Rückblick.", systemImage: "sparkles"),
        Phase(id: 6, title: "Leben & Feinschliff", detail: "Abgeschlossen: Routinen, Verträge, Geburtstage, Tagebuch, Fortschritt und Fotos, Widgets Heute und Aufgaben, Spotlight, Fokus-Filter, App-Sperre, Gym-Ankunft.", systemImage: "wand.and.stars"),
        Phase(id: 7, title: "Arzt-Tagebuch", detail: "Abgeschlossen: Schmerzen mit Körperkarte, Bewegung und Sport, beschwerdefreie Tage, Tagebuch-Check, Arztbericht mit Tag-für-Tag-Tabelle.", systemImage: "stethoscope"),
        Phase(id: 8, title: "Apple Health über Kurzbefehle", detail: "Abgeschlossen: Schritte, Strecke, Schlaf, Gewicht und Puls aus Health über einen Kurzbefehl, Wasser und Gewicht zurück nach Health.", systemImage: "heart.text.square"),
        Phase(id: 9, title: "Sicherheit & Feinschliff", detail: "Abgeschlossen: Sicherung zusätzlich in iCloud Drive, einmaliger Import aus Apple Erinnerungen, Muskel-Karte im Training, schnelle Ansichten auch nach Jahren an Daten, bessere VoiceOver-Beschriftungen.", systemImage: "lock.shield"),
        Phase(id: 10, title: "Klarheit", detail: "Abgeschlossen: Aufgeräumte Startseite mit „Schnell erfassen“, anpassbare Karten, alle Funktionen über die Suche auffindbar, gegliederte Einstellungen.", systemImage: "rectangle.3.group"),
        Phase(id: 11, title: "Training-Coach", detail: "Abgeschlossen: Plan-Check mit Vorschlägen je Übung zum Übernehmen, Hinweis vor der nächsten Einheit, wo diese Woche noch Sätze fehlen.", systemImage: "figure.strengthtraining.traditional"),
        Phase(id: 12, title: "Rückblicke und Teilen", detail: "Abgeschlossen: Monats- und Jahresrückblick mit Vergleich, Arzt-Paket aus PDF und Tabellen (ZIP), Export aller Daten als Tabellen.", systemImage: "chart.xyaxis.line"),
        Phase(id: 13, title: "Tag planen", detail: "Abgeschlossen: Morgen-Briefing als Mitteilung, Tag abschließen mit Top 3 für morgen, Woche planen mit Fokus der Woche und Trainingstagen.", systemImage: "sun.horizon"),
        Phase(id: 14, title: "Nach deinen Wünschen", detail: "Was dir im Alltag mit Orbit auffällt: Was fehlt, was stört, was schneller gehen soll.", systemImage: "bubble.left.and.text.bubble.right"),
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

/// Abendliche Erinnerung ans Tagebuch: an/aus und Uhrzeit.
private struct DiaryReminderSettings: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKeys.diaryReminderMinute) private var minute = 20 * 60 + 30

    var body: some View {
        Toggle("Abends an Tagebuch erinnern", isOn: Binding(
            get: { minute >= 0 },
            set: { minute = $0 ? 20 * 60 + 30 : -1 }
        ))
        .accessibilityIdentifier("settings.diaryReminder")
        .onChange(of: minute) { _, _ in app.tasksChanged() }
        if minute >= 0 {
            DatePicker("Uhrzeit", selection: Binding(get: time, set: setTime), displayedComponents: .hourAndMinute)
        }
    }

    private func time() -> Date {
        AppModel.calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
    }

    private func setTime(_ date: Date) {
        let parts = AppModel.calendar.dateComponents([.hour, .minute], from: date)
        minute = (parts.hour ?? 20) * 60 + (parts.minute ?? 30)
    }
}
