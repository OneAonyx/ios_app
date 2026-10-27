import Foundation

/// Vorlagen für den Bereich „Leben“: Haushalt, Routinen, Gewohnheiten, Fristen, Verträge.
public enum LifeTemplates {
    /// Wiederkehrende Haushaltsaufgabe.
    public struct Chore: Sendable, Hashable, Identifiable {
        public var title: String
        public var everyDays: Int
        public var symbol: String
        public var id: String { title }

        public init(title: String, everyDays: Int, symbol: String) {
            self.title = title
            self.everyDays = everyDays
            self.symbol = symbol
        }

        /// „alle 7 Tage nach Erledigung“
        public var recurrence: RecurrenceRule {
            RecurrenceRule(frequency: .daily, interval: everyDays, mode: .afterCompletion)
        }
    }

    public static let chores: [Chore] = [
        Chore(title: "Bad putzen", everyDays: 7, symbol: "shower"),
        Chore(title: "Staubsaugen", everyDays: 7, symbol: "fan"),
        Chore(title: "Bettwäsche wechseln", everyDays: 14, symbol: "bed.double"),
        Chore(title: "Pflanzen gießen", everyDays: 3, symbol: "leaf"),
        Chore(title: "Kühlschrank aufräumen", everyDays: 7, symbol: "refrigerator"),
        Chore(title: "Handtücher waschen", everyDays: 7, symbol: "washer"),
        Chore(title: "Müll und Altpapier", everyDays: 7, symbol: "trash"),
        Chore(title: "Gymtasche waschen", everyDays: 7, symbol: "bag"),
    ]

    public struct HabitTemplate: Sendable, Hashable, Identifiable {
        public var name: String
        public var kind: HabitKind
        public var symbol: String
        public var period: HabitPeriod
        public var schedule: HabitSchedule
        public var target: Double
        public var unit: String
        public var steps: [String]
        public var id: String { name }

        public init(name: String, kind: HabitKind, symbol: String, period: HabitPeriod, schedule: HabitSchedule, target: Double, unit: String, steps: [String]) {
            self.name = name
            self.kind = kind
            self.symbol = symbol
            self.period = period
            self.schedule = schedule
            self.target = target
            self.unit = unit
            self.steps = steps
        }
    }

    public static let habits: [HabitTemplate] = [
        HabitTemplate(name: "Morgenroutine", kind: .routine, symbol: "sunrise.fill", period: .morning, schedule: .daily, target: 1, unit: "",
                      steps: ["Medikamente nehmen", "Großes Glas Wasser", "5 Min. dehnen", "Check-in"]),
        HabitTemplate(name: "Abendroutine", kind: .routine, symbol: "moon.stars.fill", period: .evening, schedule: .daily, target: 1, unit: "",
                      steps: ["Gymtasche für morgen packen", "Top 3 für morgen", "Bildschirm aus um 22:30", "Tagebuch"]),
        HabitTemplate(name: "Dehnen", kind: .habit, symbol: "figure.flexibility", period: .anytime, schedule: .daily, target: 10, unit: "Min.", steps: []),
        HabitTemplate(name: "Lesen", kind: .habit, symbol: "book", period: .evening, schedule: .daily, target: 20, unit: "Seiten", steps: []),
        HabitTemplate(name: "Spazieren", kind: .habit, symbol: "figure.walk", period: .anytime, schedule: .times(4), target: 1, unit: "", steps: []),
        HabitTemplate(name: "Meditieren", kind: .habit, symbol: "brain.head.profile", period: .morning, schedule: .daily, target: 5, unit: "Min.", steps: []),
    ]

    public struct ContractTemplate: Sendable, Hashable, Identifiable {
        public var name: String
        public var kind: ContractKind
        public var billing: BillingCycle
        public var notice: NoticePeriod
        public var reminderDaysBefore: Int
        public var id: String { name }

        public init(name: String, kind: ContractKind, billing: BillingCycle, notice: NoticePeriod, reminderDaysBefore: Int) {
            self.name = name
            self.kind = kind
            self.billing = billing
            self.notice = notice
            self.reminderDaysBefore = reminderDaysBefore
        }

        /// Leere Vorlage für eigene Einträge.
        public static func blank(_ kind: ContractKind) -> ContractTemplate {
            let isDocument = kind == .document
            return ContractTemplate(name: "", kind: kind, billing: isDocument ? .once : .monthly, notice: .none, reminderDaysBefore: isDocument ? 60 : 14)
        }
    }

    public static let contracts: [ContractTemplate] = [
        ContractTemplate(name: "Fitnessstudio", kind: .contract, billing: .monthly, notice: NoticePeriod(value: 1, unit: .months), reminderDaysBefore: 21),
        ContractTemplate(name: "Handyvertrag", kind: .contract, billing: .monthly, notice: NoticePeriod(value: 1, unit: .months), reminderDaysBefore: 30),
        ContractTemplate(name: "Internet", kind: .contract, billing: .monthly, notice: NoticePeriod(value: 1, unit: .months), reminderDaysBefore: 30),
        ContractTemplate(name: "Strom", kind: .contract, billing: .monthly, notice: NoticePeriod(value: 1, unit: .months), reminderDaysBefore: 30),
        ContractTemplate(name: "Streaming", kind: .subscription, billing: .monthly, notice: .none, reminderDaysBefore: 7),
        ContractTemplate(name: "Haftpflichtversicherung", kind: .insurance, billing: .yearly, notice: NoticePeriod(value: 3, unit: .months), reminderDaysBefore: 30),
        ContractTemplate(name: "Kfz-Versicherung", kind: .insurance, billing: .yearly, notice: NoticePeriod(value: 1, unit: .months), reminderDaysBefore: 30),
        ContractTemplate(name: "Personalausweis", kind: .document, billing: .once, notice: .none, reminderDaysBefore: 60),
        ContractTemplate(name: "Reisepass", kind: .document, billing: .once, notice: .none, reminderDaysBefore: 90),
        ContractTemplate(name: "Führerschein", kind: .document, billing: .once, notice: .none, reminderDaysBefore: 90),
        ContractTemplate(name: "TÜV / Hauptuntersuchung", kind: .document, billing: .once, notice: .none, reminderDaysBefore: 30),
        ContractTemplate(name: "Krankenkassenkarte", kind: .document, billing: .once, notice: .none, reminderDaysBefore: 30),
    ]
}
