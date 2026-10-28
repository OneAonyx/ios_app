import SwiftUI
import TagwerkCore
import TagwerkKit

/// Wohin eine Funktion aus dem Verzeichnis führt.
enum FeatureDestination {
    case quickAdd, checkIn, review, journal, claude, dayClosing, weekPlanning
    case planner(String), life
    case startWorkout, training(TrainingRoute)
    case logMeal, water, addSymptom, nutrition(NutritionRoute)
    case medications, addMedication, addPain, addActivity, health(HealthRoute)
    case settings(SettingsPage), systemCheck

    /// `nil` für unbekannte IDs (der Selbsttest prüft, dass es keine gibt).
    static func of(_ id: String) -> FeatureDestination? {
        switch id {
        // Heute
        case "quickAdd": .quickAdd
        case "checkIn": .checkIn
        case "review": .review
        case "journal": .journal
        case "todayLayout": .settings(.todayLayout)
        case "dayClosing": .dayClosing
        case "weekPlanning": .weekPlanning
        case "briefing": .settings(.reminders)
        case "claude": .claude

        // Planer
        case "tasks": .planner("Aufgaben")
        case "agenda": .planner("Agenda")
        case "week": .planner("Woche")
        case "life", "habits", "contracts", "birthdays": .life
        case "reminderImport": .settings(.data)

        // Training
        case "startWorkout": .startWorkout
        case "trainingPlan": .training(.plan)
        case "trainingStats": .training(.stats)
        case "coach": .training(.coach)
        case "exerciseLibrary": .training(.library)
        case "trainingProgress": .training(.progress)
        case "photos": .training(.photos)
        case "body": .training(.body)
        case "workoutHistory": .training(.history)

        // Ernährung
        case "logMeal": .logMeal
        case "water": .water
        case "lexicon": .nutrition(.lexicon)
        case "ingredientCheck": .nutrition(.ingredientCheck)
        case "shopping": .nutrition(.shopping)
        case "recipes": .nutrition(.recipes)
        case "mealPlan": .nutrition(.mealPlan)
        case "patterns": .nutrition(.patterns)
        case "nutritionSettings": .nutrition(.settings)
        case "addSymptom": .addSymptom

        // Gesundheit
        case "medications": .medications
        case "addMedication": .addMedication
        case "addPain": .addPain
        case "addActivity": .addActivity
        case "painHistory": .health(.painHistory)
        case "activityHistory": .health(.activityHistory)
        case "doctorReport": .health(.doctorReport)
        case "healthBridge": .health(.healthBridge)
        case "symptoms": .health(.symptomHistory)
        case "periodReview": .health(.periodReview)

        // Einstellungen
        case "backup", "exportTables": .settings(.data)
        case "notifications": .settings(.reminders)
        case "calendars": .settings(.calendar)
        case "privacy": .settings(.privacy)
        case "shortcuts": .settings(.shortcuts)
        case "roadmap": .settings(.about)
        case "systemCheck": .systemCheck
        default: nil
        }
    }
}

/// Öffnet eine Funktion aus dem Verzeichnis dort, wo sie in der App wohnt
/// (im richtigen Tab, damit man den Weg beim nächsten Mal selbst findet).
extension AppModel {
    func open(feature: Feature) {
        guard let destination = FeatureDestination.of(feature.id) else { return }
        // Aus einem Blatt heraus (Suche, Einstellungen): erst schließen, dann öffnen.
        // Zwei Blätter gleichzeitig wechseln verträgt SwiftUI nicht.
        let wasPresenting = isShowingSearch || isShowingSettings
        isShowingSearch = false
        isShowingSettings = false
        guard wasPresenting else {
            go(to: destination)
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(550))
            go(to: destination)
        }
    }

    private func go(to destination: FeatureDestination) {
        switch destination {
        case .quickAdd: openQuickAdd()
        case .checkIn: openCheckIn()
        case .review: openReview(weekStart: nil)
        case .journal: isShowingJournal = true
        case .claude: openClaudeHub()
        case .dayClosing: isShowingDayClosing = true
        case .weekPlanning: isShowingWeekPlanning = true
        case .planner(let mode):
            plannerModeRequest = mode
            selectedTab = .planner
        case .life: openLife()
        case .startWorkout: startWorkout()
        case .training(let route):
            openTraining()
            trainingPath = Self.path(route)
        case .logMeal: logMeal()
        case .water: addWater(NutritionTargets.glassML)
        case .addSymptom: openSymptomEntry()
        case .nutrition(let route):
            openNutrition()
            nutritionPath = Self.path(route)
        case .medications: openMedications()
        case .addMedication:
            openMedications()
            isAddingMedication = true
        case .addPain: openPainEntry()
        case .addActivity: openActivityEntry()
        case .health(let route):
            openMedications()
            healthPath = Self.path(route)
        case .settings(let page): openSettings(page)
        case .systemCheck: openSystemCheck()
        }
    }

    private static func path(_ value: some Hashable) -> NavigationPath {
        var path = NavigationPath()
        path.append(value)
        return path
    }
}
