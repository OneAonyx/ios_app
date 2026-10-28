import Foundation
import SwiftData
import TagwerkCore

/// Datensicherung als JSON im Ordner „Backups“ der App.
///
/// Der Ordner ist in der Dateien-App sichtbar (Auf meinem iPhone → Orbit → Backups).
/// Automatisch einmal am Tag, die letzten 14 Sicherungen bleiben.
@MainActor
public enum BackupService {
    public static let keepCount = 14

    public static var folderURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Backups", isDirectory: true)
    }

    public static var lastBackupDate: Date? {
        let value = UserDefaults.standard.double(forKey: SettingsKeys.lastBackupAt)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    // MARK: Schreiben

    public static func makeDocument(context: ModelContext, now: Date = .now) throws -> BackupDocument {
        let lists = try context.fetch(FetchDescriptor<TaskList>(sortBy: [SortDescriptor(\.sortIndex)]))
        let tasks = try context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.createdAt)]))
        let medications = try context.fetch(FetchDescriptor<Medication>(sortBy: [SortDescriptor(\.sortIndex)]))
        let doseLogs = try context.fetch(FetchDescriptor<DoseLog>(sortBy: [SortDescriptor(\.createdAt)]))
        let defaults = UserDefaults.standard
        var settings: [String: String] = [:]
        for key in SettingsKeys.backedUp {
            if let value = defaults.object(forKey: key) {
                settings[key] = "\(value)"
            }
        }

        return BackupDocument(
            createdAt: now,
            appVersion: "\(AppInfo.version) (\(AppInfo.build))",
            lists: lists.map { list in
                TaskListRecord(
                    stableID: list.stableID, name: list.name, symbol: list.symbol,
                    colorName: list.colorName, sortIndex: list.sortIndex, createdAt: list.createdAt
                )
            },
            tasks: tasks.map { task in
                TaskRecord(
                    stableID: task.stableID, title: task.title, notes: task.notes,
                    dueDate: task.dueDate, hasDueTime: task.hasDueTime, priority: task.priority,
                    isFlagged: task.isFlagged, focusDate: task.focusDate, isDone: task.isDone,
                    completedAt: task.completedAt, createdAt: task.createdAt, sortIndex: task.sortIndex,
                    estimateMinutes: task.estimateMinutes, recurrence: task.recurrence,
                    reminderOffsets: task.reminderOffsets, listID: task.list?.stableID,
                    tags: task.tags, kind: task.kindRaw,
                    subtasks: task.sortedSubtasks.map {
                        SubtaskRecord(stableID: $0.stableID, title: $0.title, isDone: $0.isDone, sortIndex: $0.sortIndex)
                    }
                )
            },
            settings: settings,
            medications: medications.map { medication in
                MedicationRecord(
                    stableID: medication.stableID, name: medication.name, dosage: medication.dosage,
                    form: medication.formRaw, colorName: medication.colorName, symbol: medication.symbol,
                    timing: medication.timingRaw, schedule: medication.schedule, startDate: medication.startDate,
                    endDate: medication.endDate, stock: medication.stock,
                    refillThresholdDays: medication.refillThresholdDays, autoRefillTask: medication.autoRefillTask,
                    reminderStyle: medication.reminderStyleRaw, isActive: medication.isActive, notes: medication.notes,
                    createdAt: medication.createdAt, sortIndex: medication.sortIndex
                )
            },
            doseLogs: doseLogs.compactMap { log in
                guard let medicationID = log.medication?.stableID else { return nil }
                return DoseLogRecord(
                    stableID: log.stableID, medicationID: medicationID, scheduledAt: log.scheduledAt,
                    takenAt: log.takenAt, status: log.statusRaw, amount: log.amount, note: log.note,
                    createdAt: log.createdAt
                )
            },
            training: try TrainingBackupMapper.makeBackup(context: context),
            nutrition: try NutritionBackupMapper.makeBackup(context: context),
            insights: try InsightsBackupMapper.makeBackup(context: context),
            life: try LifeBackupMapper.makeBackup(context: context),
            diary: try DiaryBackupMapper.makeBackup(context: context)
        )
    }

    /// Schreibt eine Sicherung und räumt alte auf. Gibt die neue Datei zurück.
    @discardableResult
    public static func writeBackup(context: ModelContext, now: Date = .now, calendar: Calendar) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let document = try makeDocument(context: context, now: now)
        let data = try BackupCodec.encode(document)
        let url = folderURL.appendingPathComponent(BackupCodec.fileName(for: now, calendar: calendar))
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: SettingsKeys.lastBackupAt)

        let names = (try? fileManager.contentsOfDirectory(atPath: folderURL.path)) ?? []
        for name in BackupRetention.filesToDelete(names, keep: keepCount) {
            try? fileManager.removeItem(at: folderURL.appendingPathComponent(name))
        }
        return url
    }

    /// Einmal am Tag beim Öffnen der App.
    @discardableResult
    public static func autoBackupIfNeeded(context: ModelContext, now: Date = .now, calendar: Calendar) -> URL? {
        guard BackupRetention.isAutomaticBackupDue(lastBackup: lastBackupDate, now: now) else { return nil }
        return try? writeBackup(context: context, now: now, calendar: calendar)
    }

    public static func existingBackups() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folderURL.path)) ?? []
        return BackupRetention.sortedNewestFirst(names)
            .map { folderURL.appendingPathComponent($0) }
    }

    // MARK: Wiederherstellen

    public struct RestoreSummary: Equatable {
        public let lists: Int
        public let tasks: Int
        public let medications: Int
        public let workouts: Int
        public let meals: Int
        public let checkIns: Int
        /// Routinen, Gewohnheiten, Verträge und Geburtstage.
        public let lifeEntries: Int
        /// Schmerzen und Bewegung.
        public let diaryEntries: Int
    }

    /// Ersetzt alle Aufgaben, Listen, Medikamente, Trainings-, Ernährungs- und Einblicke-Daten durch den Inhalt der Sicherung.
    /// Ältere Sicherungen ohne Medikamente, Training oder Ernährung lassen diese Daten stehen.
    /// Vorher wird automatisch eine Sicherung des aktuellen Stands angelegt.
    @discardableResult
    public static func restore(from url: URL, context: ModelContext, now: Date = .now, calendar: Calendar) throws -> RestoreSummary {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        let document = try BackupCodec.decode(Data(contentsOf: url))

        try writeBackup(context: context, now: now, calendar: calendar)

        for subtask in try context.fetch(FetchDescriptor<Subtask>()) {
            context.delete(subtask)
        }
        for task in try context.fetch(FetchDescriptor<TaskItem>()) {
            context.delete(task)
        }
        for list in try context.fetch(FetchDescriptor<TaskList>()) {
            context.delete(list)
        }
        if document.medications != nil {
            for log in try context.fetch(FetchDescriptor<DoseLog>()) {
                context.delete(log)
            }
            for medication in try context.fetch(FetchDescriptor<Medication>()) {
                context.delete(medication)
            }
        }
        try context.save()

        var listsByID: [String: TaskList] = [:]
        for record in document.lists {
            let list = TaskList(
                name: record.name, symbol: record.symbol, colorName: record.colorName,
                sortIndex: record.sortIndex, stableID: record.stableID, createdAt: record.createdAt
            )
            context.insert(list)
            listsByID[record.stableID] = list
        }

        for record in document.tasks {
            let task = TaskItem(
                title: record.title, notes: record.notes, dueDate: record.dueDate,
                hasDueTime: record.hasDueTime, priority: record.priority,
                list: record.listID.flatMap { listsByID[$0] }, sortIndex: record.sortIndex,
                stableID: record.stableID, createdAt: record.createdAt
            )
            task.isFlagged = record.isFlagged
            task.focusDate = record.focusDate
            task.isDone = record.isDone
            task.completedAt = record.completedAt
            task.estimateMinutes = record.estimateMinutes
            task.recurrence = record.recurrence
            task.reminderOffsets = record.reminderOffsets
            task.tags = record.tags
            task.kindRaw = record.kind
            context.insert(task)
            for subRecord in record.subtasks {
                let subtask = Subtask(title: subRecord.title, isDone: subRecord.isDone, sortIndex: subRecord.sortIndex, stableID: subRecord.stableID)
                context.insert(subtask)
                subtask.task = task
            }
        }

        var medicationsByID: [String: Medication] = [:]
        for record in document.medications ?? [] {
            let medication = Medication(
                name: record.name, dosage: record.dosage, form: MedicationForm(rawValue: record.form) ?? .other,
                schedule: record.schedule, startDate: record.startDate, sortIndex: record.sortIndex,
                stableID: record.stableID, createdAt: record.createdAt
            )
            medication.formRaw = record.form
            medication.colorName = record.colorName
            medication.symbol = record.symbol
            medication.timingRaw = record.timing
            medication.endDate = record.endDate
            medication.stock = record.stock
            medication.refillThresholdDays = record.refillThresholdDays
            medication.autoRefillTask = record.autoRefillTask
            medication.reminderStyleRaw = record.reminderStyle
            medication.isActive = record.isActive
            medication.notes = record.notes
            context.insert(medication)
            medicationsByID[record.stableID] = medication
        }
        for record in document.doseLogs ?? [] {
            guard let medication = medicationsByID[record.medicationID] else { continue }
            let log = DoseLog(
                scheduledAt: record.scheduledAt, takenAt: record.takenAt,
                status: DoseStatus(rawValue: record.status) ?? .taken, amount: record.amount,
                note: record.note, stableID: record.stableID, createdAt: record.createdAt
            )
            context.insert(log)
            log.medication = medication
        }

        // Ältere Sicherungen ohne Training lassen vorhandene Trainingsdaten stehen.
        if let training = document.training {
            try TrainingBackupMapper.restore(training, context: context)
        }
        // Ebenso ohne Ernährung (Sicherungen vor Version 0.5).
        if let nutrition = document.nutrition {
            try NutritionBackupMapper.restore(nutrition, context: context)
        }
        // Ebenso ohne Check-ins und Claude-Verlauf (Sicherungen vor Version 0.6).
        if let insights = document.insights {
            try InsightsBackupMapper.restore(insights, context: context)
        }
        // Ebenso ohne Leben (Sicherungen vor Version 0.7).
        if let life = document.life {
            try LifeBackupMapper.restore(life, context: context)
        }
        // Ebenso ohne Arzt-Tagebuch (Sicherungen vor Version 0.8).
        if let diary = document.diary {
            try DiaryBackupMapper.restore(diary, context: context)
        }

        let defaults = UserDefaults.standard
        for (key, value) in document.settings where SettingsKeys.backedUp.contains(key) {
            switch key {
            case SettingsKeys.showCalendarEvents:
                defaults.set(value == "1" || value.lowercased() == "true", forKey: key)
            case SettingsKeys.defaultReminderOffset, SettingsKeys.diaryReminderMinute:
                defaults.set(Int(value) ?? -1, forKey: key)
            case SettingsKeys.proteinPerKg:
                if let number = Double(value) { defaults.set(number, forKey: key) }
            case SettingsKeys.waterTarget:
                if let number = Int(value) { defaults.set(number, forKey: key) }
            case SettingsKeys.askBeforeMealMedication, SettingsKeys.showCheckIns, SettingsKeys.weeklyReviewReminder:
                defaults.set(value == "1" || value.lowercased() == "true", forKey: key)
            default:
                defaults.set(value, forKey: key)
            }
        }

        try context.save()
        return RestoreSummary(
            lists: document.lists.count,
            tasks: document.tasks.count,
            medications: document.medications?.count ?? 0,
            workouts: document.training?.sessions.count ?? 0,
            meals: document.nutrition?.meals.count ?? 0,
            checkIns: document.insights?.checkIns.count ?? 0,
            lifeEntries: document.life.map { $0.habits.count + $0.contracts.count + $0.birthdays.count } ?? 0,
            diaryEntries: document.diary.map { $0.pains.count + $0.activities.count } ?? 0
        )
    }
}
