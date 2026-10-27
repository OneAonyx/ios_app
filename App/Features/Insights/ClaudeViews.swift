import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit
import UIKit

// MARK: - Zentrale

/// Alle Claude-Anfragen: neue Anfrage starten, Verlauf, Kurzbefehl einrichten.
struct ClaudeHubView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \ClaudeExchange.createdAt, order: .reverse) private var exchanges: [ClaudeExchange]

    var body: some View {
        List {
            Section {
                Text("Orbit baut die Anfrage aus deinen Daten, du siehst vorher genau, was rausgeht. Claude antwortet über den Kurzbefehl „\(TagwerkIDs.claudeShortcutName)“ mit deinem normalen Claude-Konto, ohne API-Key.")
                    .font(.subheadline)
                NavigationLink {
                    ClaudeShortcutGuideView()
                } label: {
                    HStack {
                        Label("Kurzbefehl einrichten", systemImage: "square.on.square.badge.person.crop")
                        Spacer()
                        SystemCheckStatePill(app.systemCheck.state(for: .claudeBridge))
                    }
                }
            }

            Section("Neue Anfrage") {
                ForEach(ClaudeTask.allCases) { task in
                    NavigationLink {
                        ClaudeRequestView(task: task)
                    } label: {
                        HStack(spacing: Spacing.s) {
                            IconBadge(systemImage: task.symbol, tint: .purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.body.weight(.semibold))
                                Text(task.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("claude.task.\(task.rawValue)")
                }
            }

            Section("Verlauf") {
                if exchanges.isEmpty {
                    Text("Noch keine Anfragen.")
                        .foregroundStyle(.secondary)
                }
                ForEach(exchanges) { exchange in
                    NavigationLink {
                        ClaudeExchangeView(exchange: exchange)
                    } label: {
                        ExchangeRow(exchange: exchange)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        InsightsActions.delete(exchanges[index], in: context)
                    }
                }
            }
        }
        .navigationTitle("Claude")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ClaudeHubSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ClaudeHubView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                    }
                }
        }
    }
}

private struct ExchangeRow: View {
    let exchange: ClaudeExchange

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: exchange.task.symbol)
                .foregroundStyle(.purple)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(exchange.title)
                    .lineLimit(2)
                Text(exchange.createdAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ExchangeStatusBadge(exchange: exchange)
        }
    }
}

struct ExchangeStatusBadge: View {
    let exchange: ClaudeExchange

    var body: some View {
        Text(exchange.statusTitle)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(exchange.statusColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(exchange.statusColor.opacity(0.14), in: Capsule())
            .fixedSize()
    }
}

extension ClaudeExchange {
    /// Text-Antworten werden gelesen, nicht übernommen.
    var statusTitle: String {
        if status == .applied, task.isTextAnswer { return "Gelesen" }
        return status.title
    }

    var statusColor: Color {
        switch status {
        case .draft: .secondary
        case .sent: .orange
        case .answered: .blue
        case .applied: .green
        case .discarded: .secondary
        case .failed: .red
        }
    }
}

extension ClaudeTask {
    var isTextAnswer: Bool { self == .weeklyReview || self == .patterns }
}

// MARK: - Anfrage

/// Vorbelegung einer Anfrage aus dem jeweiligen Bildschirm.
struct ClaudePreset {
    var weekStart: Date?
    var foodName = ""
    var brand = ""
    var ingredients = ""
    var wish = ""
}

/// Anfrage im eigenen Blatt (aus Plan-Editor, Lexikon, Rezepten, Mustern, Rückblick).
struct ClaudeRequestSheet: View {
    let task: ClaudeTask
    var preset = ClaudePreset()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ClaudeRequestView(task: task, preset: preset)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Schließen") { dismiss() }
                    }
                }
        }
    }
}

/// Anfrage zusammenstellen: Angaben, Datenvorschau, Senden. Danach zeigt sie die Antwort.
struct ClaudeRequestView: View {
    let task: ClaudeTask
    var preset = ClaudePreset()

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKeys.trainingGoal) private var goal = ""
    @AppStorage(SettingsKeys.trainingExperience) private var experience = ""
    @State private var ref = ClaudePromptBuilder.makeRef()
    @State private var wish = ""
    @State private var foodName = ""
    @State private var brand = ""
    @State private var ingredients = ""
    @State private var weekStart = Date.now
    @State private var recipeCount = 3
    @State private var servings = 2
    @State private var inputs = RequestInputs()
    @State private var loaded = false
    @State private var showsPrompt = false
    @State private var exchange: ClaudeExchange?
    @State private var isSending = false

    /// Einmal berechnete Daten, damit das Tippen im Wunschfeld nichts neu abfragt.
    private struct RequestInputs {
        var training: ClaudePromptBuilder.TrainingContext?
        var review: WeeklyReview?
        var recipes: ClaudePromptBuilder.RecipeContext?
        var patterns: ClaudeBridgeActions.PatternsInput?
    }

    var body: some View {
        Group {
            if let exchange {
                ClaudeExchangeView(exchange: exchange)
            } else {
                form
            }
        }
        .onAppear(perform: load)
        .onChange(of: weekStart) { _, start in
            guard task == .weeklyReview, loaded else { return }
            inputs.review = InsightsActions.weeklyReview(weekStart: start, calendar: AppModel.calendar, in: context)
        }
    }

    private var form: some View {
        let prompt = currentPrompt
        return Form {
            Section {
                HStack(spacing: Spacing.s) {
                    IconBadge(systemImage: task.symbol, tint: .purple, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.headline)
                        Text(task.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            inputSection

            if let prompt {
                Section {
                    ForEach(prompt.includedData, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .labelStyle(TintedIconLabelStyle(tint: .purple))
                    }
                    DisclosureGroup("Ganze Anfrage ansehen", isExpanded: $showsPrompt) {
                        Text(prompt.text)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    .accessibilityIdentifier("claude.preview")
                } header: {
                    Text("Das geht an Claude")
                } footer: {
                    Text("Kennung \(prompt.ref). Ohne deinen Namen und ohne Einzeleinträge mit Datum. Die Anfrage zählt zu deinem normalen Claude-Nutzungslimit.")
                }

                Section {
                    Button {
                        send(prompt)
                    } label: {
                        Label("An Claude senden", systemImage: "paperplane.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(isSending)
                    .accessibilityIdentifier("claude.send")
                    Button {
                        copy(prompt)
                    } label: {
                        Label("Stattdessen kopieren", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("claude.copy")
                } footer: {
                    Text("Senden startet den Kurzbefehl „\(TagwerkIDs.claudeShortcutName)“, die Antwort kommt automatisch zurück. Kopieren: in der Claude-App einfügen, Antwort kopieren und hier einfügen.")
                }
            }

            Section {
                NavigationLink {
                    ClaudeShortcutGuideView()
                } label: {
                    Label("Kurzbefehl einrichten", systemImage: "questionmark.circle")
                }
            }
        }
        .navigationTitle(task.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var inputSection: some View {
        switch task {
        case .trainingPlan:
            if inputs.training == nil, loaded {
                Section {
                    Label("Es gibt keinen aktiven Trainingsplan.", systemImage: "exclamationmark.triangle")
                }
            } else {
                Section {
                    TextField("Was soll sich ändern?", text: $wish, prompt: Text("z. B. mehr Rücken, kürzere Einheiten"), axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("claude.wish")
                    TextField("Ziel", text: $goal, prompt: Text(ClaudeBridgeActions.defaultGoal))
                    TextField("Erfahrung", text: $experience, prompt: Text(ClaudeBridgeActions.defaultExperience))
                } header: {
                    Text("Deine Angaben")
                } footer: {
                    Text("Ohne Wunsch prüft Claude den Plan allgemein. Ziel und Erfahrung merkt sich Orbit.")
                }
            }
        case .weeklyReview:
            Section("Deine Angaben") {
                Picker("Woche", selection: $weekStart) {
                    ForEach(weekOptions, id: \.self) { start in
                        Text(WeeklyReview.title(weekStart: start, calendar: AppModel.calendar)).tag(start)
                    }
                }
                TextField("Frage oder Wunsch", text: $wish, prompt: Text("optional, z. B. mehr Fokus auf Schlaf"), axis: .vertical)
                    .lineLimit(1...4)
            }
            if let review = inputs.review, review.isEmpty {
                Section {
                    Label("In dieser Woche gibt es noch keine Daten.", systemImage: "calendar.badge.exclamationmark")
                }
            }
        case .food:
            Section {
                TextField("Name", text: $foodName, prompt: Text("z. B. Haferdrink Barista"))
                    .accessibilityIdentifier("claude.food.name")
                TextField("Marke", text: $brand, prompt: Text("optional"))
                TextField("Zutaten", text: $ingredients, prompt: Text("optional, z. B. von der Verpackung"), axis: .vertical)
                    .lineLimit(2...6)
            } header: {
                Text("Lebensmittel")
            } footer: {
                Text("Claude bewertet es auf der Histamin-Skala 0–3. Du kannst es danach ins Lexikon übernehmen.")
            }
        case .recipes:
            Section("Deine Angaben") {
                TextField("Wunsch", text: $wish, prompt: Text("z. B. schnelles Frühstück, ohne Fisch"), axis: .vertical)
                    .lineLimit(1...4)
                    .accessibilityIdentifier("claude.wish")
                Stepper("\(recipeCount) Rezepte", value: $recipeCount, in: 1...5)
                Stepper(servings == 1 ? "1 Portion" : "\(servings) Portionen", value: $servings, in: 1...6)
            }
        case .patterns:
            Section {
                TextField("Frage", text: $wish, prompt: Text("optional, z. B. Liegt es am Käse?"), axis: .vertical)
                    .lineLimit(1...4)
            } header: {
                Text("Deine Angaben")
            } footer: {
                if let missing = inputs.patterns?.report.missingDataText {
                    Text("Noch wenig Daten: \(missing)")
                } else {
                    Text("Claude sieht nur die Auswertung der letzten 90 Tage, keine einzelnen Mahlzeiten.")
                }
            }
        }
    }

    /// Die letzten 6 Wochen, dazu die vorbelegte, falls sie weiter zurückliegt.
    private var weekOptions: [Date] {
        let calendar = AppModel.calendar
        let current = AgendaBuilder.startOfWeek(containing: .now, calendar: calendar)
        var weeks = (0..<6).compactMap { calendar.date(byAdding: .day, value: -7 * $0, to: current) }
        if !weeks.contains(weekStart) { weeks.append(weekStart) }
        return weeks
    }

    private var currentPrompt: ClaudePrompt? {
        let trimmedWish = wish.trimmingCharacters(in: .whitespacesAndNewlines)
        switch task {
        case .trainingPlan:
            guard var data = inputs.training else { return nil }
            data.wish = trimmedWish
            data.goal = goal.trimmingCharacters(in: .whitespaces).isEmpty ? ClaudeBridgeActions.defaultGoal : goal
            data.experience = experience.trimmingCharacters(in: .whitespaces).isEmpty ? ClaudeBridgeActions.defaultExperience : experience
            return ClaudePromptBuilder.trainingPlan(data, ref: ref)
        case .weeklyReview:
            guard let review = inputs.review, !review.isEmpty else { return nil }
            return ClaudePromptBuilder.weeklyReview(review, wish: trimmedWish, ref: ref)
        case .food:
            guard !foodName.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return ClaudeBridgeActions.foodPrompt(name: foodName, brand: brand, ingredients: ingredients, ref: ref)
        case .recipes:
            guard var data = inputs.recipes else { return nil }
            data.wish = trimmedWish
            data.count = recipeCount
            data.servings = servings
            return ClaudePromptBuilder.recipes(data, ref: ref)
        case .patterns:
            return inputs.patterns?.prompt(wish: trimmedWish, ref: ref)
        }
    }

    private func load() {
        guard !loaded else { return }
        let calendar = AppModel.calendar
        wish = preset.wish
        foodName = preset.foodName
        brand = preset.brand
        ingredients = preset.ingredients
        let start = preset.weekStart ?? AgendaBuilder.startOfWeek(containing: .now, calendar: calendar)
        weekStart = start
        switch task {
        case .trainingPlan:
            inputs.training = ClaudeBridgeActions.trainingContext(calendar: calendar, in: context)
        case .weeklyReview:
            inputs.review = InsightsActions.weeklyReview(weekStart: start, calendar: calendar, in: context)
        case .food:
            break
        case .recipes:
            inputs.recipes = ClaudeBridgeActions.recipeContext(in: context)
        case .patterns:
            inputs.patterns = ClaudeBridgeActions.patternsInput(calendar: calendar, in: context)
        }
        loaded = true
    }

    private var exchangeTitle: String {
        let trimmedWish = wish.trimmingCharacters(in: .whitespacesAndNewlines)
        switch task {
        case .trainingPlan: return trimmedWish.isEmpty ? "Trainingsplan prüfen" : "Plan: \(trimmedWish)"
        case .weeklyReview: return "Rückblick " + WeeklyReview.title(weekStart: weekStart, calendar: AppModel.calendar)
        case .food: return "Lebensmittel: \(foodName.trimmingCharacters(in: .whitespaces))"
        case .recipes: return trimmedWish.isEmpty ? "Rezeptideen" : "Rezepte: \(trimmedWish)"
        case .patterns: return trimmedWish.isEmpty ? "Muster deuten" : "Muster: \(trimmedWish)"
        }
    }

    private func send(_ prompt: ClaudePrompt) {
        isSending = true
        let created = InsightsActions.createExchange(prompt, title: exchangeTitle, in: context)
        exchange = created
        Task {
            await app.sendToClaude(created)
            isSending = false
        }
    }

    private func copy(_ prompt: ClaudePrompt) {
        let created = InsightsActions.createExchange(prompt, title: exchangeTitle, in: context)
        UIPasteboard.general.string = prompt.text
        InsightsActions.markSent(created, in: context)
        exchange = created
    }
}

// MARK: - Antwort

/// Eine Anfrage mit Antwort: warten, einfügen, Vorschau, übernehmen.
struct ClaudeExchangeView: View {
    let exchange: ClaudeExchange

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showsPrompt = false
    @State private var showsResponse = false
    @State private var message: String?
    @State private var copied = false

    var body: some View {
        let answer = parsedAnswer
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack {
                        Label(exchange.task.title, systemImage: exchange.task.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.purple)
                        Spacer()
                        ExchangeStatusBadge(exchange: exchange)
                    }
                    Text(exchange.title)
                        .font(.headline)
                    Text(exchange.createdAt.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if exchange.response.isEmpty {
                waitingSection
            } else {
                switch answer {
                case .success(.plan(let template)):
                    PlanAnswerSection(template: template, exchange: exchange) { text in message = text }
                case .success(.text(let heading, let content)):
                    Section(heading) {
                        MarkdownText(content)
                            .textSelection(.enabled)
                    }
                case .success(.food(let food)):
                    FoodAnswerSection(food: food, exchange: exchange) { text in message = text }
                case .success(.recipes(let recipes, let newFoods)):
                    RecipesAnswerSection(recipes: recipes, newFoods: newFoods, exchange: exchange) { text in message = text }
                case .failure(let error):
                    Section {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        PasteButton(payloadType: String.self) { strings in
                            receive(strings.first)
                        }
                        Button("Erneut senden") { resend() }
                    } footer: {
                        Text("Du kannst eine korrigierte Antwort einfügen oder die Anfrage nochmal schicken.")
                    }
                }
            }

            if let message {
                Section {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Section {
                DisclosureGroup("Anfrage", isExpanded: $showsPrompt) {
                    Text(exchange.prompt)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                if !exchange.response.isEmpty {
                    DisclosureGroup("Antwort im Original", isExpanded: $showsResponse) {
                        Text(exchange.response)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle(exchange.task.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if exchange.status != .applied, exchange.status != .discarded, !exchange.response.isEmpty {
                        Button("Verwerfen", systemImage: "xmark.bin") {
                            InsightsActions.setStatus(.discarded, of: exchange, in: context)
                        }
                    }
                    Button("Löschen", systemImage: "trash", role: .destructive) {
                        if app.visibleExchangeID == exchange.stableID { app.visibleExchangeID = nil }
                        InsightsActions.delete(exchange, in: context)
                        dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Mehr")
            }
        }
        .onAppear {
            app.visibleExchangeID = exchange.stableID
            markRead()
        }
        .onDisappear {
            if app.visibleExchangeID == exchange.stableID { app.visibleExchangeID = nil }
        }
        .onChange(of: exchange.response) { _, _ in markRead() }
    }

    @ViewBuilder
    private var waitingSection: some View {
        Section {
            switch exchange.status {
            case .sent:
                HStack(spacing: Spacing.s) {
                    ProgressView()
                    Text("Wartet auf Claudes Antwort …")
                }
            case .failed:
                Label("Senden hat nicht geklappt. Gibt es den Kurzbefehl „\(TagwerkIDs.claudeShortcutName)“?", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            default:
                Text("Noch nicht abgeschickt.")
                    .foregroundStyle(.secondary)
            }
            PasteButton(payloadType: String.self) { strings in
                receive(strings.first)
            }
            .accessibilityIdentifier("claude.paste")
            Button {
                resend()
            } label: {
                Label(exchange.status == .sent ? "Nochmal senden" : "An Claude senden", systemImage: "paperplane")
            }
            Button {
                UIPasteboard.general.string = exchange.prompt
                if exchange.status != .sent { InsightsActions.markSent(exchange, in: context) }
                copied = true
            } label: {
                Label(copied ? "Kopiert" : "Anfrage kopieren", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
        } header: {
            Text("Antwort")
        } footer: {
            Text("Die Antwort kommt automatisch, sobald der Kurzbefehl fertig ist. Ohne Kurzbefehl: Anfrage kopieren, in der Claude-App einfügen, Claudes Antwort kopieren und hier einfügen.")
        }
    }

    private var parsedAnswer: Result<ClaudeAnswer, Error> {
        Result { try ClaudeBridgeActions.parse(exchange, in: context) }
    }

    private func receive(_ text: String?) {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        InsightsActions.attach(text, to: exchange, in: context)
    }

    private func resend() {
        copied = false
        Task { await app.sendToClaude(exchange) }
    }

    /// Text-Antworten gelten als gelesen, sobald sie angezeigt werden.
    private func markRead() {
        guard exchange.task.isTextAnswer, exchange.status == .answered, case .success = parsedAnswer else { return }
        InsightsActions.setStatus(.applied, of: exchange, in: context)
    }
}

/// Anfrage im eigenen Blatt, z. B. nach dem Rücksprung aus der Kurzbefehle-App.
struct ClaudeExchangeSheet: View {
    let stableID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            Group {
                if let exchange = InsightsActions.exchange(stableID: stableID, in: context) {
                    ClaudeExchangeView(exchange: exchange)
                } else {
                    ContentUnavailableView("Anfrage nicht gefunden", systemImage: "questionmark.bubble")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Antwort-Vorschauen

private struct PlanAnswerSection: View {
    let template: PlanTemplate
    let exchange: ClaudeExchange
    let onApplied: (String) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context

    var body: some View {
        let catalog = TrainingActions.catalog(in: context)
        let imported = PlanImporter.resolve(template, catalog: catalog)
        let days = imported.template.days
        Section {
            ForEach(days.indices, id: \.self) { dayIndex in
                let day = days[dayIndex]
                VStack(alignment: .leading, spacing: 4) {
                    Text([day.shortName, day.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.headline)
                    ForEach(day.exercises.indices, id: \.self) { index in
                        let item = day.exercises[index]
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(item.name ?? catalog.name(for: item.exercise)) – \(item.prescription)")
                                .font(.subheadline)
                            if let note = item.note, !note.isEmpty {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Vorschlag: \(imported.template.name)")
        } footer: {
            Text("\(days.count) Tage, Mesozyklus \(imported.template.mesoWeeks) Wochen.")
        }
        if !imported.unmatched.isEmpty {
            Section {
                ForEach(imported.unmatched, id: \.self) { Text($0) }
            } header: {
                Text("Neue eigene Übungen")
            } footer: {
                Text("Diese Übungen gibt es in der Bibliothek nicht. Sie werden als eigene Übungen angelegt.")
            }
        }
        Section {
            if exchange.status == .applied {
                Label("Übernommen", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button {
                    let plan = ClaudeBridgeActions.applyPlan(template, from: exchange, in: context)
                    app.trainingChanged()
                    onApplied("„\(plan.name)“ ist jetzt dein aktiver Plan. Der alte bleibt unter Pläne erhalten.")
                } label: {
                    Label("Als neuen Plan übernehmen", systemImage: "square.and.arrow.down")
                        .font(.headline)
                }
                .accessibilityIdentifier("claude.apply")
            }
        }
    }
}

private struct FoodAnswerSection: View {
    let food: FoodInfo
    let exchange: ClaudeExchange
    let onApplied: (String) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context

    var body: some View {
        Section("Bewertung") {
            HStack {
                Text(food.name)
                    .font(.headline)
                Spacer()
                ScoreBadge(score: food.score, showsTitle: true)
            }
            LabeledContent("Kategorie", value: food.category.title)
            ForEach(food.flags) { flag in
                Label(flag.title, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
            }
            if let hint = food.hint {
                Text(hint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let protein = food.protein {
                LabeledContent("Eiweiß", value: "\(WeightFormat.number(protein)) g / 100 g")
            }
            if let kcal = food.kcal {
                LabeledContent("Energie", value: "\(Int(kcal.rounded())) kcal / 100 g")
            }
        }
        Section {
            if exchange.status == .applied {
                Label("Im Lexikon gespeichert", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button {
                    ClaudeBridgeActions.applyFood(food, from: exchange, in: context)
                    app.nutritionChanged()
                    onApplied("„\(food.name)“ steht jetzt in deinem Lexikon.")
                } label: {
                    Label("Ins Lexikon übernehmen", systemImage: "plus.circle")
                        .font(.headline)
                }
                .accessibilityIdentifier("claude.apply")
            }
        } footer: {
            Text("Claudes Einschätzung ist eine Orientierung. Deine eigene Verträglichkeit kannst du danach im Lexikon setzen.")
        }
    }
}

private struct RecipesAnswerSection: View {
    let recipes: [RecipeInfo]
    let newFoods: [FoodInfo]
    let exchange: ClaudeExchange
    let onApplied: (String) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context

    var body: some View {
        let catalog = NutritionActions.catalog(in: context)
        ForEach(recipes) { recipe in
            Section {
                if !recipe.summary.isEmpty {
                    Text(recipe.summary)
                        .font(.subheadline)
                }
                Text("\(recipe.servings) Portionen · \(recipe.minutes) Min.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(recipe.ingredients.indices, id: \.self) { index in
                    let ingredient = recipe.ingredients[index]
                    let food = catalog.food(id: ingredient.food) ?? newFoods.first { $0.id == ingredient.food }
                    HStack {
                        Text(food?.name ?? ingredient.food)
                        Spacer()
                        Text(ingredient.amount ?? "\(WeightFormat.number(ingredient.grams)) g")
                            .foregroundStyle(.secondary)
                        if let food {
                            ScoreBadge(score: food.score)
                        }
                    }
                    .font(.subheadline)
                }
                if !recipe.steps.isEmpty {
                    Text(recipe.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(recipe.title)
            }
        }
        if !newFoods.isEmpty {
            Section {
                Text(newFoods.map(\.name).joined(separator: ", "))
                    .font(.subheadline)
            } header: {
                Text("Neu im Lexikon")
            } footer: {
                Text("Diese Zutaten kennt Orbit noch nicht. Sie werden als eigene Lebensmittel mit vorsichtiger Bewertung (1) angelegt.")
            }
        }
        Section {
            if exchange.status == .applied {
                Label("In Rezepte gespeichert", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button {
                    ClaudeBridgeActions.applyRecipes(recipes, newFoods: newFoods, from: exchange, in: context)
                    app.nutritionChanged()
                    onApplied(recipes.count == 1 ? "Rezept gespeichert." : "\(recipes.count) Rezepte gespeichert.")
                } label: {
                    Label(recipes.count == 1 ? "Rezept speichern" : "\(recipes.count) Rezepte speichern", systemImage: "book.closed")
                        .font(.headline)
                }
                .accessibilityIdentifier("claude.apply")
            }
        }
    }
}

/// Einfaches Markdown: Überschriften, Listen, fett und kursiv.
struct MarkdownText: View {
    private let blocks: [Block]

    private struct Block: Identifiable {
        let id: Int
        let text: AttributedString
        let isHeading: Bool
    }

    init(_ source: String) {
        var result: [Block] = []
        let paragraphs = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        for paragraph in paragraphs {
            let lines = paragraph.split(separator: "\n", omittingEmptySubsequences: true).map { line -> (String, Bool) in
                var text = line.trimmingCharacters(in: .whitespaces)
                var heading = false
                while text.hasPrefix("#") {
                    text.removeFirst()
                    heading = true
                }
                if text.hasPrefix("- ") || text.hasPrefix("* ") {
                    text = "• " + String(text.dropFirst(2))
                }
                return (text.trimmingCharacters(in: .whitespaces), heading)
            }
            guard !lines.isEmpty else { continue }
            let joined = lines.map { $0.0 }.joined(separator: "\n")
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            let text = (try? AttributedString(markdown: joined, options: options)) ?? AttributedString(joined)
            result.append(Block(id: result.count, text: text, isHeading: lines.count == 1 && lines[0].1))
        }
        blocks = result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ForEach(blocks) { block in
                Text(block.text)
                    .font(block.isHeading ? .headline : .body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}
