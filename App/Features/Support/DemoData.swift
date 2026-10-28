import Foundation
import SwiftData
import TagwerkCore
import TagwerkKit
import UIKit

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
        seedInsights(into: context, now: now, calendar: calendar)
        seedLife(into: context, now: now, calendar: calendar)
        seedDiary(into: context, now: now, calendar: calendar)
        seedHealth(into: context, now: now, calendar: calendar)
        try? context.save()
    }

    /// 30 Tage Schritte und Strecke, als kämen sie über den Kurzbefehl aus Apple Health.
    private static func seedHealth(into context: ModelContext, now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        let pattern = [7_820, 9_410, 5_230, 11_870, 8_050, 4_310, 12_640, 6_980, 10_220, 7_390]
        for offset in 0..<30 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let steps = offset == 0 ? 6_412 : pattern[offset % pattern.count]
            let values = HealthValues(
                steps: steps,
                distanceKm: Double(steps) * 0.00072,
                flights: 4 + offset % 9,
                sleepHours: offset == 0 ? nil : 6.4 + Double(offset % 5) * 0.35
            )
            HealthActions.importValues(values, day: day, now: day.addingTimeInterval(21.5 * 3_600), calendar: calendar, in: context)
        }
        UserDefaults.standard.set(now.addingTimeInterval(-2 * 3_600).timeIntervalSince1970, forKey: SettingsKeys.healthLastImport)
    }

    /// Arzt-Tagebuch: Schmerzen, Bewegung, beschwerdefreie Tage der letzten Wochen.
    private static func seedDiary(into context: ModelContext, now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let pains: [PainFact] = [
            PainFact(date: at(-20, 8), regions: [.lowerBack], intensity: 5, qualities: [.dull, .pulling], durationMinutes: 240, triggers: [.sitting], reliefs: [.heat, .movement]),
            PainFact(date: at(-16, 19), regions: [.shoulderRight], intensity: 6, qualities: [.stabbing], durationMinutes: 60, triggers: [.training], reliefs: [.rest]),
            PainFact(date: at(-12, 7, 30), regions: [.lowerBack], intensity: 4, qualities: [.dull], durationMinutes: 120, triggers: [.sleep], reliefs: [.movement]),
            PainFact(date: at(-9, 20), regions: [.shoulderRight, .elbowRight], intensity: 7, qualities: [.stabbing, .radiating], durationMinutes: 180, triggers: [.training], reliefs: [.medication], note: "Ibuprofen 400"),
            PainFact(date: at(-5, 14), regions: [.wristLeft], intensity: 3, qualities: [.pulling], durationMinutes: 30, triggers: [.strain]),
            PainFact(date: at(-2, 9), regions: [.neck, .upperBack], intensity: 5, qualities: [.pressing], durationMinutes: 480, triggers: [.sitting, .stress], reliefs: [.heat]),
        ]
        for pain in pains {
            DiaryActions.addPain(pain, in: context)
        }
        let activities: [ActivityFact] = [
            ActivityFact(date: at(-19, 7), kind: .walking, minutes: 40, intensity: .light),
            ActivityFact(date: at(-14, 10), kind: .cycling, minutes: 60, intensity: .moderate),
            ActivityFact(date: at(-11, 18), kind: .running, minutes: 30, intensity: .vigorous),
            ActivityFact(date: at(-7, 11), kind: .hiking, minutes: 150, intensity: .moderate),
            ActivityFact(date: at(-4, 19), kind: .ballSports, minutes: 90, intensity: .vigorous, note: "Fußball"),
            ActivityFact(date: at(-1, 7, 30), kind: .walking, minutes: 35, intensity: .moderate),
            ActivityFact(date: at(-1, 21), kind: .stretching, minutes: 15, intensity: .light),
        ]
        for activity in activities {
            DiaryActions.addActivity(activity, in: context)
        }
        for offset in [-18, -15, -13, -10, -8, -6, -3, -1] {
            DiaryActions.setSymptomFree(true, on: at(offset, 21), calendar: calendar, in: context)
        }
        for offset in [-17, -6] {
            DiaryActions.setRestDay(true, on: at(offset, 21), calendar: calendar, in: context)
        }
        UserDefaults.standard.set("Kann die Schulter vom Training kommen? Sind die Kopfschmerzen nach Tomate Histamin?", forKey: SettingsKeys.doctorQuestions)
    }

    /// Routinen mit Verlauf, Verträge mit Fristen, Geburtstage, Tagebuch.
    private static func seedLife(into context: ModelContext, now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }

        let templates = LifeTemplates.habits
        let morning = LifeActions.createHabit(from: templates[0], now: day(-30), in: context)
        let evening = LifeActions.createHabit(from: templates[1], now: day(-30), in: context)
        let reading = LifeActions.createHabit(from: templates[3], now: day(-30), in: context)
        let walking = LifeActions.createHabit(from: templates[4], now: day(-30), in: context)
        for offset in -28 ... -1 where offset % 5 != 0 {
            for step in morning.steps {
                LifeActions.toggleStep(step.id, of: morning, on: day(offset), calendar: calendar, in: context)
            }
            if offset % 3 != 0 {
                LifeActions.toggleDone(evening, on: day(offset), calendar: calendar, in: context)
            }
            if offset % 2 == 0 {
                LifeActions.add(offset % 4 == 0 ? 25 : 12, to: reading, on: day(offset), calendar: calendar, in: context)
                LifeActions.toggleDone(walking, on: day(offset), calendar: calendar, in: context)
            }
        }
        for step in morning.steps.prefix(2) {
            LifeActions.toggleStep(step.id, of: morning, on: today, calendar: calendar, in: context)
        }

        func contract(_ name: String, cost: Double?, start: Int?, end: Int? = nil, minimum: Int? = nil, renewal: Int? = nil, provider: String = "") {
            guard let template = LifeTemplates.contracts.first(where: { $0.name == name }) else { return }
            let contract = LifeActions.createContract(from: template, now: day(-60), in: context)
            contract.cost = cost
            contract.provider = provider
            contract.startDate = start.map(day)
            contract.endDate = end.map(day)
            contract.minimumTermMonths = minimum
            contract.renewalMonths = renewal
        }
        contract("Fitnessstudio", cost: 29.9, start: -360, minimum: 12, renewal: 1, provider: "FitX")
        contract("Handyvertrag", cost: 17.99, start: -420, minimum: 24, renewal: 1, provider: "Telekom")
        contract("Streaming", cost: 13.99, start: -200, provider: "Netflix")
        contract("Haftpflichtversicherung", cost: 64, start: -700, renewal: 12)
        contract("Personalausweis", cost: nil, start: nil, end: 45)

        func birthday(_ name: String, inDays: Int, year: Int?) {
            let date = day(inDays)
            _ = LifeActions.addBirthday(name: name, day: calendar.component(.day, from: date), month: calendar.component(.month, from: date), year: year, in: context)
        }
        birthday("Lena", inDays: 5, year: 1996)
        birthday("Papa", inDays: 23, year: 1965)
        birthday("Jonas", inDays: 71, year: nil)

        LifeActions.saveJournal(answer: "Training lief gut, neues Gewicht beim Latzug.", text: "Abends früh ins Bett.", on: day(-1), calendar: calendar, in: context)
        LifeActions.saveJournal(answer: "Ruhiger Tag, viel gelesen.", text: "", on: day(-2), calendar: calendar, in: context)
        if let chore = LifeTemplates.chores.first {
            LifeActions.addChore(chore, now: now, calendar: calendar, in: context)
        }
        LifeActions.save(context)

        // Zwei Fortschrittsfotos (gezeichnet, keine echten Fotos).
        for (index, offset) in [-56, -2].enumerated() {
            guard let image = demoPhoto(index: index),
                  let data = image.jpegData(compressionQuality: 0.8),
                  let thumbnail = ImageResizer.jpeg(image, maxSide: 420, quality: 0.7) else { continue }
            let photo = ProgressActions.addPhoto(imageData: data, thumbnailData: thumbnail, date: day(offset).addingTimeInterval(8 * 3_600), pose: .front, in: context)
            photo.weight = index == 0 ? 80.4 : 82.3
        }
        ProgressActions.save(context)
    }

    private static func demoPhoto(index: Int) -> UIImage? {
        let size = CGSize(width: 600, height: 800)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let colors = index == 0
                ? [UIColor(red: 0.20, green: 0.24, blue: 0.32, alpha: 1), UIColor(red: 0.36, green: 0.40, blue: 0.50, alpha: 1)]
                : [UIColor(red: 0.18, green: 0.30, blue: 0.34, alpha: 1), UIColor(red: 0.32, green: 0.50, blue: 0.52, alpha: 1)]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: [0, 1])
            if let gradient {
                renderer.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            let configuration = UIImage.SymbolConfiguration(pointSize: index == 0 ? 360 : 380, weight: index == 0 ? .regular : .semibold)
            if let figure = UIImage(systemName: "figure.arms.open", withConfiguration: configuration)?.withTintColor(.white.withAlphaComponent(0.85), renderingMode: .alwaysOriginal) {
                let rect = CGRect(x: (size.width - figure.size.width) / 2, y: (size.height - figure.size.height) / 2, width: figure.size.width, height: figure.size.height)
                figure.draw(in: rect)
            }
        }
    }

    /// Zwei Wochen Check-ins und ein paar Claude-Anfragen mit Antwort.
    private static func seedInsights(into context: ModelContext, now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        let sleep = [4, 3, 2, 4, 5, 3, 4, 2, 3, 4, 4, 5, 3, 4]
        let energy = [4, 3, 2, 3, 4, 3, 4, 2, 3, 4, 3, 5, 3, 4]
        let mood = [4, 3, 3, 4, 5, 3, 4, 2, 3, 4, 4, 5, 4, 4]
        let stress = [2, 3, 4, 2, 1, 3, 2, 4, 3, 2, 3, 1, 2, 2]
        for index in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: index - 14, to: today) else { continue }
            let entry = DailyCheckIn(day: day)
            entry.sleep = sleep[index]
            entry.energy = energy[index]
            entry.mood = mood[index]
            entry.stress = stress[index]
            entry.sleepHours = [7.5, 6.5, 5.0, 7.0, 8.0, 6.5, 7.5, 5.5, 6.5, 7.0, 7.5, 8.5, 6.5, 7.0][index]
            if index == 7 { entry.note = "Wenig geschlafen, viel los bei der Arbeit." }
            context.insert(entry)
        }
        // Heute: nur der Morgen, damit die Karte etwas zeigt und der Abend offen ist.
        let todayEntry = DailyCheckIn(day: today)
        todayEntry.sleep = 4
        todayEntry.energy = 4
        context.insert(todayEntry)

        let weekStart = AgendaBuilder.startOfWeek(containing: now, calendar: calendar)
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let review = ClaudeExchange(
            task: .weeklyReview, ref: "DEMO01",
            title: "Rückblick " + WeeklyReview.title(weekStart: lastWeek, calendar: calendar),
            prompt: "(Beispiel-Anfrage)", createdAt: now.addingTimeInterval(-5 * 86_400)
        )
        review.response = #"{"format":"orbit.text.v1","ref":"DEMO01","title":"Deine Woche","text":"**Gut gelaufen:** Vier Trainings und fast jeden Tag genug Wasser.\n\n**Fällt auf:** An den Tagen mit wenig Schlaf waren Stimmung und Energie niedriger, und zweimal kam Kopfschmerz nach Tomate.\n\n**Für nächste Woche:**\n- Tomate eine Woche weglassen und beobachten.\n- Vor Trainingstagen 30 Minuten früher ins Bett.\n- Mittags Reste nicht aufwärmen, lieber frisch kochen."}"#
        review.answeredAt = review.createdAt.addingTimeInterval(60)
        review.status = .applied
        context.insert(review)

        let food = ClaudeExchange(
            task: .food, ref: "DEMO02", title: "Lebensmittel: Haferdrink Barista",
            prompt: "(Beispiel-Anfrage)", createdAt: now.addingTimeInterval(-3_600)
        )
        food.response = """
            Hier ist meine Einschätzung:

            ```json
            {"format":"orbit.food.v1","ref":"DEMO02","name":"Haferdrink Barista","category":"drinks","score":1,"flags":["L"],"hint":"Hafer ist meist gut verträglich, Zusätze wie Rapsöl und Phosphate eher unkritisch. Bei Liberator-Empfindlichkeit vorsichtig testen.","protein":1.0,"kcal":59,"portion":200}
            ```
            """
        food.answeredAt = food.createdAt.addingTimeInterval(45)
        food.status = .answered
        context.insert(food)

        let waiting = ClaudeExchange(
            task: .recipes, ref: "DEMO03", title: "Rezepte: schnelles Frühstück",
            prompt: "(Beispiel-Anfrage)", createdAt: now.addingTimeInterval(-600)
        )
        waiting.status = .sent
        context.insert(waiting)
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
        guard let template = PlanTemplate.bundledOwnFourDay() else { return }
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
            "chest-press-lying": 35, "shoulder-press-machine": 27, "pushdown-bar": 54, "machine-row": 59,
            "hammer-curl-cable": 45, "wrist-curl-barbell": 20, "reverse-curl-barbell": 20,
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
        TrainingActions.addMetric(.height, value: 183, date: today.addingTimeInterval(-40 * 86_400), in: context)
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
