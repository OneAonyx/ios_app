import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit
import Vision
import VisionKit

/// Kamera mit Live-Erkennung (VisionKit). Läuft auf dem iPhone ohne Apple-KI und ohne Netz.
private struct DataScannerView: UIViewControllerRepresentable {
    enum Mode { case barcode, text }

    let mode: Mode
    var onBarcode: (String) -> Void = { _ in }
    var onText: ([String]) -> Void = { _ in }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let types: Set<DataScannerViewController.RecognizedDataType> = switch mode {
        case .barcode: [.barcode(symbologies: [.ean13, .ean8, .upce])]
        case .text: [.text(languages: ["de-DE"])]
        }
        let controller = DataScannerViewController(
            recognizedDataTypes: types,
            qualityLevel: mode == .text ? .accurate : .balanced,
            recognizesMultipleItems: mode == .text,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
        if !controller.isScanning {
            try? controller.startScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: DataScannerView
        private var reported = false

        init(parent: DataScannerView) {
            self.parent = parent
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(allItems)
        }

        private func handle(_ items: [RecognizedItem]) {
            switch parent.mode {
            case .barcode:
                guard !reported else { return }
                for item in items {
                    if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue, Barcode.isValid(Barcode.clean(payload)) {
                        reported = true
                        parent.onBarcode(Barcode.clean(payload))
                        return
                    }
                }
            case .text:
                let lines = items.compactMap { item -> String? in
                    if case let .text(text) = item { return text.transcript }
                    return nil
                }
                parent.onText(lines)
            }
        }
    }
}

/// Barcode scannen und das Produkt nachschlagen (erst lokal, dann Open Food Facts).
struct BarcodeScannerSheet: View {
    let onFood: (FoodInfo) -> Void

    @MainActor static var isSupported: Bool {
        DataScannerViewController.isSupported && !AppInfo.isUITesting
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var phase: Phase = .scanning
    @State private var manualCode = ""

    private enum Phase {
        case scanning
        case loading(String)
        case found(FoodInfo)
        case failed(String, String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .scanning:
                    VStack(spacing: 0) {
                        if DataScannerViewController.isAvailable {
                            DataScannerView(mode: .barcode, onBarcode: { code in
                                Task { await lookup(code) }
                            })
                            .ignoresSafeArea(edges: .bottom)
                        } else {
                            ContentUnavailableView(
                                "Kamera nicht verfügbar",
                                systemImage: "camera.fill",
                                description: Text("Erlaube Orbit den Kamerazugriff in den Einstellungen oder tippe den Barcode ein.")
                            )
                        }
                        HStack {
                            TextField("Barcode eintippen", text: $manualCode)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                            Button("Suchen") { Task { await lookup(manualCode) } }
                                .disabled(manualCode.count < 8)
                        }
                        .padding()
                        .background(.bar)
                    }
                case let .loading(code):
                    ProgressView("Suche \(code) …")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .found(food):
                    ScannedFoodView(food: food) {
                        onFood(food)
                        dismiss()
                    }
                case let .failed(code, message):
                    ContentUnavailableView {
                        Label("Nicht gefunden", systemImage: "barcode")
                    } description: {
                        Text("\(message)\n\nBarcode: \(code)")
                    } actions: {
                        Button("Nochmal scannen") { phase = .scanning }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func lookup(_ raw: String) async {
        let code = Barcode.clean(raw)
        phase = .loading(code)
        do {
            let food = try await FoodLookupService.lookup(barcode: code, in: context)
            phase = .found(food)
        } catch {
            phase = .failed(code, error.localizedDescription)
        }
    }
}

/// Gefundenes Produkt mit Bewertung aus der Zutatenliste.
private struct ScannedFoodView: View {
    let food: FoodInfo
    let onUse: () -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(food.name)
                        .font(.title3.weight(.bold))
                    ScoreBadge(score: food.score, showsTitle: true)
                    if let protein = food.protein {
                        Text("\(WeightFormat.number(protein)) g Eiweiß je 100 g")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let ingredients = food.ingredients {
                Section("Zutaten") {
                    Text(ingredients)
                        .font(.footnote)
                    IngredientReportView(report: NutritionActions.analyzer.analyze(ingredients))
                }
            } else {
                Section {
                    Text("Keine Zutatenliste hinterlegt. Die Bewertung ist geschätzt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button(action: onUse) {
                    Label("Übernehmen", systemImage: "checkmark.circle.fill")
                }
            } footer: {
                Text("Daten von Open Food Facts. Gespeichert als eigenes Lebensmittel, Bewertung später änderbar.")
            }
        }
    }
}

/// Zutatenliste abtippen, einfügen oder abfotografieren und prüfen.
struct IngredientCheckView: View {
    @State private var text = ""
    @State private var scanning = false
    @FocusState private var focused: Bool

    var body: some View {
        let report = NutritionActions.analyzer.analyze(text)
        List {
            Section {
                TextField("Zutaten, z. B. „Tomaten, Zucker, Branntweinessig, E 211“", text: $text, axis: .vertical)
                    .lineLimit(4...12)
                    .focused($focused)
                    .accessibilityIdentifier("ingredients.text")
                HStack {
                    if TextScanSheet.isSupported {
                        Button {
                            scanning = true
                        } label: {
                            Label("Kamera", systemImage: "text.viewfinder")
                        }
                        .buttonStyle(.bordered)
                    }
                    PasteButton(payloadType: String.self) { strings in
                        text = strings.first ?? text
                    }
                    .buttonBorderShape(.capsule)
                    Spacer()
                    if !text.isEmpty {
                        Button("Leeren") { text = "" }
                    }
                }
            } header: {
                Text("Zutatenliste")
            } footer: {
                Text("Erkennt rund 230 Stichworte (z. B. Hefeextrakt, Essig, Tomate, gereifter Käse) und E-Nummern wie Sulfite oder Benzoate. Ohne Internet.")
            }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Ergebnis") {
                    IngredientReportView(report: report)
                }
            }
            Section {
                NutritionDisclaimer()
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Zutaten prüfen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") { focused = false }
            }
        }
        .sheet(isPresented: $scanning) {
            TextScanSheet { scanned in
                text = scanned
            }
        }
        .onAppear {
            if AppInfo.isUITesting, text.isEmpty {
                text = "Tomaten (45 %), Wasser, Zucker, Hefeextrakt, Branntweinessig, Salz, Gewürze, Konservierungsstoff: E 211"
            }
        }
    }
}

/// Ergebnis einer Zutatenprüfung.
struct IngredientReportView: View {
    let report: IngredientReport

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.xs) {
                if let worst = report.worstScore {
                    ScoreBadge(score: worst)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                Text(report.summary)
                    .font(.subheadline.weight(.semibold))
            }
            ForEach(report.hits) { hit in
                HStack(alignment: .top, spacing: Spacing.s) {
                    ScoreBadge(score: hit.score)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.rule.name)
                            .font(.subheadline.weight(.medium))
                        Text(hit.rule.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if report.isEmpty, report.ingredientCount > 0 {
                Text("Achte trotzdem auf Frische und Lagerung: Auch unkritische Zutaten bilden mit der Zeit Histamin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}

/// Zutatenliste mit der Kamera erkennen. Was im Bild markiert ist, wird übernommen.
struct TextScanSheet: View {
    let onText: (String) -> Void

    @MainActor static var isSupported: Bool {
        DataScannerViewController.isSupported && !AppInfo.isUITesting
    }

    @Environment(\.dismiss) private var dismiss
    @State private var lines: [String] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if DataScannerViewController.isAvailable {
                    DataScannerView(mode: .text, onText: { lines = $0 })
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView(
                        "Kamera nicht verfügbar",
                        systemImage: "camera.fill",
                        description: Text("Erlaube Orbit den Kamerazugriff in den Einstellungen.")
                    )
                }
                VStack(spacing: Spacing.xs) {
                    Text(lines.isEmpty ? "Halte die Kamera auf die Zutatenliste." : "\(lines.count) Textstellen erkannt")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        onText(lines.joined(separator: ", "))
                        dismiss()
                    } label: {
                        Text("Übernehmen")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ModuleAccent.nutrition)
                    .disabled(lines.isEmpty)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Zutaten scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}
