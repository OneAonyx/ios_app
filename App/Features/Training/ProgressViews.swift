import PhotosUI
import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit
import UIKit

extension ProgressPace {
    var color: Color {
        switch self {
        case .good: .green
        case .tooFast: .orange
        case .slow: .yellow
        case .stalled: .orange
        case .declining: .red
        case .notEnoughData: .secondary
        }
    }
}

/// Tempo einer Übung mit Einschätzung.
struct ProgressTrendRow: View {
    let trend: ExerciseTrend
    /// Übungsname (in Listen), `nil` auf der Übungsseite.
    let name: String?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: trend.pace.symbol)
                .font(.title3)
                .foregroundStyle(trend.pace.color)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if let name {
                    Text(name)
                        .font(.body.weight(.semibold))
                }
                HStack(spacing: Spacing.xs) {
                    Text(trend.pace.title.capitalizedFirst)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(trend.pace.color)
                    if trend.pace != .notEnoughData {
                        Text(trend.rateText)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if trend.pace != .notEnoughData {
                    Text("Geschätztes Max. \(WeightFormat.number(trend.first.rounded())) → \(WeightFormat.number(trend.last.rounded())) kg · \(trend.sessions) Einheiten")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(trend.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

extension String {
    /// „gutes Tempo“ → „Gutes Tempo“
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

/// Fortschritt auf einen Blick: Tempo je Übung, Körpergewicht, Maße, Fotos, Claude.
struct ProgressOverviewView: View {
    @Environment(\.modelContext) private var context
    @Query private var sessions: [WorkoutSession]
    @Query private var metrics: [BodyMetric]
    @State private var askingClaude = false

    var body: some View {
        let _ = (sessions.count, metrics.count)
        let catalog = TrainingActions.catalog(in: context)
        let trends = ProgressActions.trends(in: context)
        let bodyweight = ProgressActions.bodyweightTrend(in: context)
        let measurements = ProgressActions.measurementChanges(in: context)
        List {
            Section {
                Text(ProgressAssessment.summary(trends))
                    .font(.headline)
                Text("Bewertet wird das geschätzte Maximalgewicht der letzten 8 Wochen. Nach etwa einem Jahr Training sind 0,5–2,5 % pro Woche bei Grundübungen ein gutes Tempo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Übungen") {
                if trends.isEmpty {
                    Text("Noch kein aktiver Plan.")
                        .foregroundStyle(.secondary)
                }
                ForEach(trends) { trend in
                    NavigationLink {
                        ExerciseDetailView(exerciseID: trend.exerciseID)
                    } label: {
                        ProgressTrendRow(trend: trend, name: catalog.name(for: trend.exerciseID))
                    }
                }
            }
            Section("Körper") {
                if let bodyweight {
                    BodyweightTrendRow(trend: bodyweight)
                } else {
                    Text("Für das Gewichtstempo braucht es 3 Einträge über mindestens 2 Wochen (Training → Körper).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(measurements, id: \.self) { line in
                    Label(line, systemImage: "ruler")
                        .font(.subheadline)
                }
                NavigationLink {
                    ProgressPhotosView()
                } label: {
                    Label("Fortschrittsfotos", systemImage: "person.crop.rectangle.stack")
                }
                .accessibilityIdentifier("progress.photos")
            }
            Section {
                Button {
                    askingClaude = true
                } label: {
                    Label("Mit Claude bewerten", systemImage: "sparkles")
                }
                .accessibilityIdentifier("progress.claude")
            } footer: {
                Text("Claude bekommt Kraftverlauf, Gewicht und Maße (keine Fotos) und sagt, ob es zu schnell oder zu langsam geht.")
            }
        }
        .navigationTitle("Fortschritt")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $askingClaude) {
            ClaudeRequestSheet(task: .progress)
        }
    }
}

struct BodyweightTrendRow: View {
    let trend: BodyweightTrend

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: trend.pace.symbol)
                .font(.title3)
                .foregroundStyle(trend.pace.color)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Körpergewicht")
                    .font(.body.weight(.semibold))
                Text("\(WeightFormat.number(trend.first)) → \(WeightFormat.number(trend.last)) kg · \(trend.rateText)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(trend.pace.color)
                Text(trend.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Fotos

/// Fortschrittsfotos: privat in Orbit, mit Vergleich und Einschätzung durch Claude.
struct ProgressPhotosView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var takingPhoto = false
    @State private var comparing = false
    @State private var sharing = false
    @State private var selected: ProgressPhoto?

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 104), spacing: Spacing.xs)]
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Card {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Label("So werden Fotos vergleichbar", systemImage: "lightbulb")
                            .font(.headline)
                        Text("Gleiche Uhrzeit (am besten morgens), gleiches Licht, gleicher Abstand, entspannt und ohne Pump. Vorne, Seite und hinten, alle 2–4 Wochen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Die Fotos bleiben in Orbit, nicht in deiner Fotomediathek und nicht in der Datensicherung.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: Spacing.xs) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Aus Fotos", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            takingPhoto = true
                        } label: {
                            Label("Kamera", systemImage: "camera")
                                .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .tint(ModuleAccent.training)
                if photos.count >= 2 {
                    HStack(spacing: Spacing.xs) {
                        Button {
                            comparing = true
                        } label: {
                            Label("Vergleichen", systemImage: "rectangle.split.2x1")
                                .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ModuleAccent.training)
                        .accessibilityIdentifier("photos.compare")
                        Button {
                            sharing = true
                        } label: {
                            Label("Claude", systemImage: "sparkles")
                                .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.bordered)
                        .tint(.purple)
                        .accessibilityIdentifier("photos.claude")
                    }
                } else if photos.count == 1 {
                    Button {
                        sharing = true
                    } label: {
                        Label("Von Claude einschätzen lassen", systemImage: "sparkles")
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                }
                if photos.isEmpty {
                    ContentUnavailableView(
                        "Noch keine Fotos",
                        systemImage: "person.crop.rectangle",
                        description: Text("Mach heute dein erstes Foto. In ein paar Wochen siehst du den Unterschied.")
                    )
                } else {
                    LazyVGrid(columns: columns, spacing: Spacing.xs) {
                        ForEach(photos) { photo in
                            Button {
                                selected = photo
                            } label: {
                                PhotoThumbnail(photo: photo)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.tagwerkPage)
        .navigationTitle("Fortschrittsfotos")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    pendingImage = image
                }
                pickerItem = nil
            }
        }
        .sheet(isPresented: $takingPhoto) {
            CameraPicker { image in
                pendingImage = image
            }
            .ignoresSafeArea()
        }
        .sheet(item: Binding(
            get: { pendingImage.map(PendingPhoto.init) },
            set: { if $0 == nil { pendingImage = nil } }
        )) { pending in
            NewPhotoSheet(image: pending.image)
        }
        .sheet(item: $selected) { photo in
            PhotoDetailSheet(photo: photo)
        }
        .sheet(isPresented: $comparing) {
            PhotoCompareView(photos: photos)
        }
        .sheet(isPresented: $sharing) {
            PhotoClaudeSheet(photos: photos)
        }
    }
}

private struct PendingPhoto: Identifiable {
    let image: UIImage
    var id: ObjectIdentifier { ObjectIdentifier(image) }
}

struct PhotoThumbnail: View {
    let photo: ProgressPhoto

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if let data = photo.thumbnailData ?? photo.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            Text(photo.date.formatted(.dateTime.day().month(.abbreviated).year()))
                .font(.caption.weight(.semibold))
            Text(photo.pose.title + (photo.weight.map { " · \(WeightFormat.number($0)) kg" } ?? ""))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Foto \(photo.pose.title), \(photo.date.formatted(date: .long, time: .omitted))")
    }
}

/// Neues Foto: Pose und Datum wählen, dann verkleinert speichern.
private struct NewPhotoSheet: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var pose: PhotoPose = .front
    @State private var date = Date.now
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 320)
                        .frame(maxWidth: .infinity)
                }
                Section {
                    Picker("Pose", selection: $pose) {
                        ForEach(PhotoPose.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Datum", selection: $date, in: ...Date.now, displayedComponents: .date)
                    TextField("Notiz (optional)", text: $note)
                }
            }
            .navigationTitle("Foto sichern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        if let full = ImageResizer.jpeg(image, maxSide: 1_600, quality: 0.8),
                           let thumb = ImageResizer.jpeg(image, maxSide: 420, quality: 0.7) {
                            ProgressActions.addPhoto(imageData: full, thumbnailData: thumb, date: date, pose: pose, note: note, in: context)
                        }
                        dismiss()
                    }
                    .accessibilityIdentifier("photo.save")
                }
            }
        }
    }
}

private struct PhotoDetailSheet: View {
    let photo: ProgressPhoto

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.s) {
                if let data = photo.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                }
                Text(ProgressActions.label(for: photo, calendar: AppModel.calendar))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !photo.note.isEmpty {
                    Text(photo.note)
                        .font(.footnote)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(photo.pose.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Foto löschen")
                }
            }
            .confirmationDialog("Foto löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    ProgressActions.delete(photo, in: context)
                    dismiss()
                }
            }
        }
    }
}

/// Zwei Fotos übereinander mit Schieberegler.
struct PhotoCompareView: View {
    let photos: [ProgressPhoto]

    @Environment(\.dismiss) private var dismiss
    @State private var pose: PhotoPose = .front
    @State private var beforeID: String?
    @State private var afterID: String?
    @State private var split: CGFloat = 0.5

    var body: some View {
        let ofPose = photos.filter { $0.pose == pose }.sorted { $0.date < $1.date }
        let candidates = ofPose.count >= 2 ? ofPose : photos.sorted { $0.date < $1.date }
        let before = candidates.first { $0.stableID == beforeID } ?? candidates.first
        let after = candidates.first { $0.stableID == afterID } ?? candidates.last
        NavigationStack {
            VStack(spacing: Spacing.s) {
                Picker("Pose", selection: $pose) {
                    ForEach(PhotoPose.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                if let before, let after, let beforeImage = before.imageData.flatMap(UIImage.init(data:)), let afterImage = after.imageData.flatMap(UIImage.init(data:)) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Image(uiImage: afterImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                            Image(uiImage: beforeImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .mask(alignment: .leading) {
                                    Rectangle().frame(width: proxy.size.width * split)
                                }
                            Rectangle()
                                .fill(.white)
                                .frame(width: 3, height: proxy.size.height)
                                .shadow(radius: 2)
                                .offset(x: proxy.size.width * split - 1.5)
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            split = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                        })
                        .accessibilityElement()
                        .accessibilityLabel("Vergleich vorher und nachher")
                        .accessibilityValue("\(Int(split * 100)) Prozent vorher")
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: split = min(split + 0.1, 1)
                            case .decrement: split = max(split - 0.1, 0)
                            @unknown default: break
                            }
                        }
                    }
                    HStack {
                        photoMenu("Vorher", selection: $beforeID, current: before, options: candidates)
                        Spacer()
                        photoMenu("Nachher", selection: $afterID, current: after, options: candidates)
                    }
                    if let days = Calendar.current.dateComponents([.day], from: before.date, to: after.date).day, days > 0 {
                        Text("\(days) Tage dazwischen" + weightChange(before, after))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView("Zu wenige Fotos", systemImage: "rectangle.split.2x1", description: Text("Für einen Vergleich braucht es zwei Fotos."))
                }
            }
            .padding()
            .navigationTitle("Vergleich")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("compare.done")
                }
            }
        }
    }

    private func photoMenu(_ title: String, selection: Binding<String?>, current: ProgressPhoto, options: [ProgressPhoto]) -> some View {
        Menu {
            ForEach(options) { photo in
                Button(ProgressActions.label(for: photo, calendar: AppModel.calendar)) {
                    selection.wrappedValue = photo.stableID
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(current.date.formatted(.dateTime.day().month(.abbreviated).year()))
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func weightChange(_ before: ProgressPhoto, _ after: ProgressPhoto) -> String {
        guard let first = before.weight, let last = after.weight else { return "" }
        let change = ((last - first) * 10).rounded() / 10
        let sign = change > 0 ? "+" : (change < 0 ? "−" : "±")
        return " · Gewicht \(sign)\(WeightFormat.number(abs(change))) kg"
    }
}

/// Fotos mit Text über das Teilen-Menü an die Claude-App schicken. Die Antwort fügst du danach ein.
private struct PhotoClaudeSheet: View {
    let photos: [ProgressPhoto]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var chosen: Set<String> = []
    @State private var wish = ""
    @State private var ref = ClaudePromptBuilder.makeRef()
    @State private var data: ClaudePromptBuilder.ProgressContext?
    @State private var showsShare = false
    @State private var exchange: ClaudeExchange?

    var body: some View {
        NavigationStack {
            Group {
                if let exchange {
                    ClaudeExchangeView(exchange: exchange)
                } else {
                    form
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
        .onAppear {
            guard data == nil else { return }
            data = ProgressActions.claudeContext(in: context)
            // Vorauswahl: ältestes und neuestes Foto derselben Pose.
            let sorted = photos.sorted { $0.date < $1.date }
            let pose = photos.first?.pose ?? .front
            let samePose = sorted.filter { $0.pose == pose }
            let pick = [samePose.first, samePose.last].compactMap { $0?.stableID }
            chosen = Set(pick.isEmpty ? sorted.suffix(2).map(\.stableID) : pick)
        }
    }

    private var selectedPhotos: [ProgressPhoto] {
        photos.filter { chosen.contains($0.stableID) }.sorted { $0.date < $1.date }
    }

    private var prompt: ClaudePrompt? {
        guard let data, !selectedPhotos.isEmpty else { return nil }
        let labels = selectedPhotos.map { ProgressActions.label(for: $0, calendar: AppModel.calendar) }
        return ClaudePromptBuilder.photos(data, photos: labels, wish: wish.trimmingCharacters(in: .whitespacesAndNewlines), ref: ref)
    }

    private var form: some View {
        Form {
            Section {
                ForEach(photos) { photo in
                    Button {
                        if chosen.contains(photo.stableID) {
                            chosen.remove(photo.stableID)
                        } else if chosen.count < 4 {
                            chosen.insert(photo.stableID)
                        }
                    } label: {
                        HStack(spacing: Spacing.s) {
                            if let data = photo.thumbnailData, let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            Text(ProgressActions.label(for: photo, calendar: AppModel.calendar))
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Image(systemName: chosen.contains(photo.stableID) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(chosen.contains(photo.stableID) ? Color.purple : Color.secondary)
                        }
                    }
                }
            } header: {
                Text("Fotos (höchstens 4)")
            }
            Section {
                LabeledField(title: "Frage (optional)", text: $wish, prompt: "z. B. Sieht man an den Schultern etwas?", lines: 1...4)
            }
            if let prompt {
                Section {
                    ForEach(prompt.includedData, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .labelStyle(TintedIconLabelStyle(tint: .purple))
                    }
                } header: {
                    Text("Das geht an Claude")
                } footer: {
                    Text("Fotos kann der Kurzbefehl nicht übergeben. Deshalb öffnet sich das Teilen-Menü: Wähle die Claude-App, schick die Nachricht ab, kopiere Claudes Antwort und füge sie hier ein. Der Text liegt zusätzlich in der Zwischenablage.")
                }
                Section {
                    Button {
                        UIPasteboard.general.string = prompt.text
                        showsShare = true
                    } label: {
                        Label("An die Claude-App teilen", systemImage: "square.and.arrow.up")
                            .font(.headline)
                    }
                    .accessibilityIdentifier("photos.share")
                }
            }
        }
        .navigationTitle("Fotos bewerten")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsShare) {
            if let prompt {
                ActivityShareSheet(items: shareItems(prompt)) { completed in
                    showsShare = false
                    guard completed else { return }
                    let created = InsightsActions.createExchange(prompt, title: "Fotos vom \(selectedPhotos.last.map { $0.date.formatted(.dateTime.day().month(.abbreviated)) } ?? "")", in: context)
                    InsightsActions.markSent(created, in: context)
                    exchange = created
                }
            }
        }
    }

    private func shareItems(_ prompt: ClaudePrompt) -> [Any] {
        let images: [Any] = selectedPhotos.compactMap { $0.imageData.flatMap(UIImage.init(data:)) }
        return [prompt.text] + images
    }
}

/// Teilen-Menü von UIKit (gemischte Inhalte: Text und Bilder).
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete(completed)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Kamera (Fotos werden nicht in der Mediathek gespeichert).
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Bilder verkleinern und als JPEG ablegen.
enum ImageResizer {
    static func jpeg(_ image: UIImage, maxSide: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
