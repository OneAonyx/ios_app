import Foundation
import SwiftData
import TagwerkCore
import TagwerkKit

/// Beispieldaten nur für die UI-Tests im CI (Screenshots). Werden nie in echte Speicher geschrieben.
@MainActor
enum DemoData {
    static func seed(into context: ModelContext, now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, _ hour: Int? = nil, _ minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            guard let hour else { return base }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }

        let personal = TaskList(name: "Persönlich", symbol: "person", colorName: ListColor.indigo.rawValue, sortIndex: 0)
        let home = TaskList(name: "Haushalt", symbol: "house", colorName: ListColor.teal.rawValue, sortIndex: 1)
        let work = TaskList(name: "Arbeit", symbol: "briefcase", colorName: ListColor.blue.rawValue, sortIndex: 2)
        for list in [personal, home, work] {
            context.insert(list)
        }

        var index = 0.0
        @discardableResult
        func task(
            _ title: String, due: Date? = nil, time: Bool = false, list: TaskList? = nil,
            priority: Int = 0, focus: Bool = false, flagged: Bool = false,
            recurrence: RecurrenceRule? = nil, doneAt: Date? = nil, reminders: [Int] = []
        ) -> TaskItem {
            index += 1
            let item = TaskItem(title: title, dueDate: due, hasDueTime: time, priority: priority, list: list, sortIndex: index, createdAt: now.addingTimeInterval(-index * 3_600))
            item.focusDate = focus ? today : nil
            item.isFlagged = flagged
            item.recurrence = recurrence
            item.reminderOffsets = reminders
            if let doneAt {
                item.isDone = true
                item.completedAt = doneAt
            }
            context.insert(item)
            return item
        }

        task("Rezept in der Apotheke abholen", due: day(0, 17, 30), time: true, list: personal, priority: 2, focus: true, reminders: [30])
        task("Steuerunterlagen sortieren", due: day(0), list: work, focus: true, flagged: true)
        task("Bettwäsche wechseln", due: day(-1), list: home, recurrence: RecurrenceRule(frequency: .weekly, mode: .afterCompletion))
        task("Müll rausbringen", due: day(0), list: home, recurrence: RecurrenceRule(frequency: .weekly, weekdays: [calendar.component(.weekday, from: now)]))
        task("Zahnarzt anrufen")
        let gift = task("Geschenk für Mama besorgen", due: day(3), list: personal)
        task("Präsentation vorbereiten", due: day(1, 10), time: true, list: work, priority: 3)
        task("Laufschuhe kaufen", due: day(0), list: personal, doneAt: now.addingTimeInterval(-7_200))
        task("Wasser trinken", due: day(0), recurrence: .daily, doneAt: now.addingTimeInterval(-3_600))
        task("Urlaub planen", due: day(9), list: personal)

        for (offset, title) in ["Ideen sammeln", "Laden auswählen"].enumerated() {
            let subtask = Subtask(title: title, isDone: offset == 0, sortIndex: Double(offset))
            context.insert(subtask)
            subtask.task = gift
        }
        seedMedications(into: context, now: now, calendar: calendar)
        seedTraining(into: context, now: now, calendar: calendar)
        seedNutrition(into: context, now: now, calendar: calendar)
        try? context.save()
    }

    /// Zwei Wochen Tagebuch: Tomate kommt öfter vor Kopfschmerz, damit „Muster“ etwas zeigt.
    private static func seedNutrition(into context: ModelContext, now: Date, calendar: Calendar) {
        let catalog = NutritionActions.bundledFoods
        let today = calendar.startOfDay(for: now)
        func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }
        func meal(_ type: MealType, _ date: Date, _ items: [(String, Double)], freshness: Freshness = .fresh, place: MealPlace = .home) {
            guard date < now else { return }
            NutritionActions.addMeal(
                type: type, date: date, freshness: freshness, place: place,
                items: items.map { (foodID: $0.0, grams: $0.1) }, catalog: catalog, in: context
            )
        }

        for offset in -14...0 {
            meal(.breakfast, at(offset, 7, 30), [("haferflocken", 60), ("magerquark", 150), ("heidelbeeren", 100), ("milch", 150)])
            let tomatoDay = offset < 0 && [-13, -11, -8, -6, -4, -2].contains(offset)
            if tomatoDay {
                meal(.lunch, at(offset, 12, 30), [("nudeln", 100), ("tomate", 150), ("mozzarella", 60), ("olivenoel", 10)])
                if offset != -8 {
                    NutritionActions.addSymptom(.headache, severity: offset == -2 ? 4 : 3, date: at(offset, 14, 0), durationMinutes: 120, in: context)
                }
            } else if offset == -9 || offset == -3 {
                meal(.lunch, at(offset, 12, 30), [("rinderhack", 125), ("reis", 70), ("paprika", 120)], freshness: .reheated)
                NutritionActions.addSymptom(.flush, severity: 2, date: at(offset, 13, 45), durationMinutes: 30, in: context)
            } else {
                meal(.lunch, at(offset, 12, 30), [("haehnchenbrust", 150), ("reis", 70), ("zucchini", 200), ("rapsoel", 10)])
            }
            if offset == -5 {
                meal(.dinner, at(offset, 19, 30), [("pizza", 300)], place: .out)
                NutritionActions.addSymptom(.bloating, severity: 3, date: at(offset, 21, 0), in: context)
            } else {
                meal(.dinner, at(offset, 19), [("kartoffel", 300), ("speisequark", 150), ("gurke", 150), ("leinoel", 10)])
            }
            if offset % 2 == 0 {
                meal(.snack, at(offset, 16), [("apfel", 150), ("mandeln", 25)])
            }
            for glass in 0..<(offset == 0 ? 5 : 8) {
                let time = at(offset, 8 + glass * 2)
                if time < now { context.insert(WaterLog(date: time, milliliters: NutritionTargets.glassML)) }
            }
        }
        // Heute auf jeden Fall etwas zeigen, auch früh am Morgen.
        if NutritionActions.meals(on: now, calendar: calendar, in: context).isEmpty {
            meal(.snack, now.addingTimeInterval(-1_800), [("skyr", 150), ("heidelbeeren", 80)])
        }

        NutritionActions.setTolerance(.caution, for: "tomate", in: context)
        NutritionActions.setTolerance(.ok, for: "paprika", in: context)
        NutritionActions.setTolerance(.avoid, for: "avocado", in: context)
        for id in ["haehnchenbrust", "magerquark", "haferflocken", "heidelbeeren"] {
            NutritionActions.setFavorite(true, for: id, in: context)
        }

        for (name, amount) in [("Hähnchenbrust", "600 g"), ("Magerquark", "1 kg"), ("Zucchini", "3 Stück"), ("Heidelbeeren", "2 Schalen"), ("Parmesan", ""), ("Reis", "1 kg")] {
            NutritionActions.addShoppingItem(name, amount: amount, catalog: catalog, in: context)
        }
        let monday = AgendaBuilder.startOfWeek(containing: now, calendar: calendar)
        for (offset, recipeID, type) in [(0, "haehnchen-reis-zucchini", MealType.dinner), (2, "ofenkartoffeln-kraeuterquark", .dinner), (3, "quinoa-bowl-pute", .lunch), (5, "kabeljau-kraeuterbutter", .dinner)] {
            if let day = calendar.date(byAdding: .day, value: offset, to: monday) {
                NutritionActions.plan(recipeID, servings: 2, on: day, mealType: type, calendar: calendar, in: context)
            }
        }
    }

    /// Startplan mit gut drei Wochen Verlauf, damit Vorschläge, Rekorde und Diagramme etwas zeigen.
    private static func seedTraining(into context: ModelContext, now: Date, calendar: Calendar) {
        guard let template = PlanTemplate.bundledUpperFourDay() else { return }
        let plan = TrainingActions.createPlan(from: template, in: context, now: now.addingTimeInterval(-30 * 86_400))
        plan.reminderMinute = 17 * 60 + 30
        let catalog = TrainingActions.catalog(in: context)
        let base: [String: Double] = [
            "bench-press-barbell": 72.5, "incline-press-dumbbell": 24, "shoulder-press-dumbbell": 20, "cable-fly-mid": 12.5,
            "lateral-raise-dumbbell": 9, "pushdown-rope": 22.5, "pull-up": 0, "chest-supported-row": 50, "lat-pulldown-close": 55,
            "seated-cable-row": 55, "face-pull": 20, "ez-curl": 27.5, "hammer-curl": 14, "close-grip-bench": 60,
            "incline-dumbbell-curl": 12, "overhead-extension-cable": 20, "preacher-curl-machine": 30, "lateral-raise-cable": 7.5,
            "reverse-fly-machine": 30, "reverse-curl": 20, "incline-press-barbell": 60, "t-bar-row": 50, "dips-chest": 0,
            "lat-pulldown-wide": 60, "pec-deck": 45, "cable-pullover": 25,
        ]
        let today = calendar.startOfDay(for: now)
        // Neun Einheiten in drei Wochen, jeweils 18:00.
        let offsets = [-22, -20, -17, -15, -13, -10, -8, -6, -3]
        for (index, offset) in offsets.enumerated() {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let start = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day),
                  let planDay = plan.nextDay
            else { continue }
            let session = TrainingActions.startSession(plan: plan, day: planDay, includeModule: false, catalog: catalog, now: start, in: context)
            var minute = 4.0
            for set in session.sortedSets {
                let weight = set.weight > 0 ? set.weight : (base[set.exerciseID] ?? 20)
                let reps = set.kind == .warmup ? set.reps : min(set.targetRepMax, set.reps + (index % 2))
                TrainingActions.complete(set, weight: weight, reps: reps, rir: set.kind == .warmup ? nil : set.targetRIR, now: start.addingTimeInterval(minute * 60), in: context)
                minute += 2.5
            }
            TrainingActions.finish(session, catalog: catalog, now: start.addingTimeInterval(minute * 60 + 120), in: context)
        }
        // Gewicht leicht steigend.
        for week in 0..<5 {
            if let date = calendar.date(byAdding: .day, value: -7 * (4 - week), to: today) {
                TrainingActions.addMetric(.weight, value: 81.2 + Double(week) * 0.3, date: date.addingTimeInterval(7 * 3_600), in: context)
            }
        }
        TrainingActions.addMetric(.upperArm, value: 37.5, date: today.addingTimeInterval(-3 * 86_400), in: context)
        TrainingActions.addMetric(.waist, value: 84, date: today.addingTimeInterval(-3 * 86_400), in: context)
    }

    /// Medikamente mit Verlauf der letzten Tage (für Einnahmetreue und Kalender).
    private static func seedMedications(into context: ModelContext, now: Date, calendar: Calendar) {
        let start = calendar.date(byAdding: .day, value: -20, to: calendar.startOfDay(for: now)) ?? now

        func medication(
            _ name: String, dosage: String, form: MedicationForm, schedule: MedicationSchedule,
            color: ListColor, symbol: String? = nil, timing: MealTiming = .none,
            style: ReminderStyle = .notification, stock: Double? = nil, sortIndex: Double
        ) -> Medication {
            let item = Medication(name: name, dosage: dosage, form: form, schedule: schedule, startDate: start, sortIndex: sortIndex, createdAt: start)
            item.colorName = color.rawValue
            if let symbol { item.symbol = symbol }
            item.timing = timing
            item.reminderStyle = style
            item.stock = stock
            context.insert(item)
            return item
        }

        let vitamin = medication("Vitamin D3", dosage: "1000 IE", form: .tablet, schedule: .daily([DoseTime(hour: 8)]), color: .orange, symbol: "sun.max.fill", stock: 54, sortIndex: 0)
        let dao = medication(
            "DAO-Enzym", dosage: "10.000 HDU", form: .capsule,
            schedule: .daily([DoseTime(hour: 7, minute: 45), DoseTime(hour: 12, minute: 15), DoseTime(hour: 18, minute: 45)]),
            color: .teal, timing: .beforeMeal, style: .alarm, stock: 38, sortIndex: 1
        )
        let cetirizin = medication("Cetirizin", dosage: "10 mg", form: .tablet, schedule: .daily([DoseTime(hour: 21)]), color: .purple, timing: .bedtime, stock: 4, sortIndex: 2)
        let ibuprofen = medication("Ibuprofen", dosage: "400 mg", form: .tablet, schedule: .asNeeded(maxPerDay: 3, minGapHours: 6), color: .red, stock: 18, sortIndex: 3)

        // Verlauf: meist genommen, ab und zu verpasst oder ausgelassen.
        for (medIndex, item) in [vitamin, dao, cetirizin].enumerated() {
            let doses = item.scheduledDoses(from: start, to: now, calendar: calendar)
            for (index, dose) in doses.enumerated() where dose.date < now.addingTimeInterval(-DoseTiming.lateAfter) {
                let pattern = (index + medIndex * 3) % 13
                if pattern == 4 { continue }
                let status: DoseStatus = pattern == 9 ? .skipped : .taken
                let log = DoseLog(scheduledAt: dose.date, takenAt: status == .taken ? dose.date.addingTimeInterval(Double(index % 4) * 240) : nil, status: status, amount: dose.amount, createdAt: dose.date)
                context.insert(log)
                log.medication = item
            }
        }
        let headache = DoseLog(scheduledAt: nil, takenAt: now.addingTimeInterval(-3 * 3_600), status: .taken, amount: 1, note: "Kopfschmerzen", createdAt: now.addingTimeInterval(-3 * 3_600))
        context.insert(headache)
        headache.medication = ibuprofen
    }
}
