import Foundation

/// Feste Kennungen der App. Bei SideStore-Installationen können Bundle- und
/// App-Group-ID zur Laufzeit abweichen (Team-ID wird angehängt), siehe `AppGroupResolver`.
public enum TagwerkIDs {
    public static let bundleIdentifier = "de.tagwerk.app"
    public static let widgetBundleIdentifier = "de.tagwerk.app.widgets"
    public static let appGroup = "group.de.tagwerk.app"
    public static let urlScheme = "tagwerk"
    /// Name des Kurzbefehls, den die Claude-Brücke aufruft.
    public static let claudeShortcutName = "Orbit Claude"
}

/// Schlüssel für Einstellungen (App-eigene UserDefaults).
public enum SettingsKeys {
    public static let userName = "tagwerk.settings.userName"
    public static let onboardingDone = "tagwerk.settings.onboardingDone"
    public static let showCalendarEvents = "tagwerk.settings.showCalendarEvents"
    /// Ausgeblendete Kalender, IDs durch Zeilenumbruch getrennt.
    public static let hiddenCalendarIDs = "tagwerk.settings.hiddenCalendarIDs"
    /// Standard-Erinnerung für neue Aufgaben mit Uhrzeit in Minuten vorher, −1 = keine.
    public static let defaultReminderOffset = "tagwerk.settings.defaultReminderOffset"
    public static let lastBackupAt = "tagwerk.settings.lastBackupAt"
    /// Eiweiß-Ziel in g je kg Körpergewicht (Text, z. B. „1.8“).
    public static let proteinPerKg = "tagwerk.settings.proteinPerKg"
    /// Wasser-Ziel in ml.
    public static let waterTarget = "tagwerk.settings.waterTarget"
    /// Nach Medikamenten „vor dem Essen“ fragen, wenn eine Mahlzeit eingetragen wird.
    public static let askBeforeMealMedication = "tagwerk.settings.askBeforeMealMedication"
    /// Check-in-Karte auf „Heute“ zeigen.
    public static let showCheckIns = "tagwerk.settings.showCheckIns"
    /// Sonntags um 18 Uhr an den Wochenrückblick erinnern.
    public static let weeklyReviewReminder = "tagwerk.settings.weeklyReviewReminder"

    /// Diese Einstellungen wandern mit in die Datensicherung.
    public static let backedUp = [
        userName, showCalendarEvents, hiddenCalendarIDs, defaultReminderOffset, proteinPerKg, waterTarget,
        askBeforeMealMedication, showCheckIns, weeklyReviewReminder,
    ]
}

/// Schlüssel für die gemeinsamen UserDefaults (App Group) und die App-eigenen Defaults.
public enum SharedKeys {
    public static let widgetSnapshot = "tagwerk.widget.systemcheck.snapshot"
    public static let pendingClaudeResponse = "tagwerk.claude.pendingResponse"
    public static let systemCheckResults = "tagwerk.systemcheck.results"
    public static let notificationActionLog = "tagwerk.systemcheck.notificationAction"
    /// Medikamente von heute und morgen für Widgets, Siri und das Kontrollzentrum.
    public static let medicationSnapshot = "tagwerk.widget.medication.snapshot"
    /// Einnahmen, die Widget oder Kontrollzentrum abgehakt haben, bis die App sie übernimmt.
    public static let pendingDoseActions = "tagwerk.medication.pendingActions"
    /// Nächste Einheit und laufendes Training für Widget, Kontrollzentrum und Siri.
    public static let trainingSnapshot = "tagwerk.widget.training.snapshot"
    /// Befehle aus der Live Activity (Pause verlängern/überspringen), bis die App sie übernimmt.
    public static let pendingWorkoutCommands = "tagwerk.training.pendingCommands"
    /// Histamin-Tageslast, Eiweiß und Wasser für Widget, Kontrollzentrum und Siri.
    public static let nutritionSnapshot = "tagwerk.widget.nutrition.snapshot"
    /// Wasser aus Widget oder Kontrollzentrum, bis die App es übernimmt.
    public static let pendingWater = "tagwerk.nutrition.pendingWater"
}

/// Kennungen der Widgets und Steuerelemente.
public enum WidgetKinds {
    public static let systemCheck = "TagwerkSystemCheck"
    public static let medication = "TagwerkMedicationWidget"
    public static let medicationControl = "de.tagwerk.control.medication"
    public static let training = "TagwerkTrainingWidget"
    public static let trainingControl = "de.tagwerk.control.training"
    public static let nutrition = "TagwerkNutritionWidget"
    public static let waterControl = "de.tagwerk.control.water"
}

/// Kennungen für Mitteilungen und ihre Aktionsknöpfe.
public enum NotificationIDs {
    public enum Category {
        public static let systemCheck = "tagwerk.category.systemcheck"
        public static let medication = "tagwerk.category.medication"
        public static let task = "tagwerk.category.task"
    }

    public enum Action {
        public static let taken = "tagwerk.action.taken"
        public static let snooze10 = "tagwerk.action.snooze10"
        public static let skip = "tagwerk.action.skip"
        public static let complete = "tagwerk.action.complete"
        public static let tomorrow = "tagwerk.action.tomorrow"
    }

    /// Schlüssel in `userInfo` einer Aufgaben-Mitteilung.
    public static let taskIDKey = "taskID"
    /// Schlüssel in `userInfo` einer Medikamenten-Mitteilung (siehe `DoseID`).
    public static let doseIDKey = "doseID"
    public static let medicationIDKey = "medicationID"
    /// Schlüssel in `userInfo` einer Trainings-Mitteilung (Tag in der Rotation).
    public static let trainingKey = "trainingDay"
    /// Schlüssel in `userInfo` der Erinnerung an den Wochenrückblick (Wochenbeginn, Unix-Sekunden).
    public static let reviewKey = "weeklyReview"

    /// Präfixe der Mitteilungs-IDs. Beim Neuplanen werden nur diese ersetzt.
    public enum Prefix {
        public static let task = "task."
        public static let medication = "med."
        public static let medicationFollowUp = "medlate."
        public static let snooze = "medsnooze."
        public static let refill = "refill."
        public static let training = "training."
        /// Wochenrückblick am Sonntag.
        public static let review = "review."
        /// Pause vorbei (wird nicht beim Neuplanen ersetzt).
        public static let restTimer = "rest."

        /// Werden bei jedem Neuplanen komplett ersetzt (Schlummern bleibt bestehen).
        public static let managed = [task, medication, medicationFollowUp, refill, training, review]
    }

    public static let systemCheckRequest = "tagwerk.systemcheck.notification"
}
