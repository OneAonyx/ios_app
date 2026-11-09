import PhotosUI
import SwiftUI
import TagwerkCore
import TagwerkKit
import UIKit

/// Gespeicherte Ranglisten (Einstellungen-Schlüssel, wandern mit in die Sicherung).
@MainActor
enum TierStore {
    static func load() -> [TierList] {
        TierList.decode(UserDefaults.standard.string(forKey: SettingsKeys.tierLists) ?? "")
    }

    static func save(_ lists: [TierList]) {
        UserDefaults.standard.set(TierList.encode(lists), forKey: SettingsKeys.tierLists)
    }

    /// Kleines Vorschaubild (höchstens 200 px), damit die Sicherung klein bleibt.
    static func thumbnail(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 200
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.65)
    }
}

extension TierRow {
    var color: Color {
        switch colorName {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "teal": .teal
        case "blue": .blue
        case "purple": .purple
        default: .gray
        }
    }

    static func colorTitle(_ name: String) -> String {
        switch name {
        case "red": "Rot"
        case "orange": "Orange"
        case "yellow": "Gelb"
        case "green": "Grün"
        case "teal": "Türkis"
        case "blue": "Blau"
        case "purple": "Lila"
        default: "Grau"
        }
    }
}

// MARK: - Übersicht

/// Leben → Ranglisten: alle Tier-Listen.
struct TierListsView: View {
    @AppStorage(SettingsKeys.tierLists) private var storedText = ""
    @State private var creating = false
    @State private var newTitle = ""

    var body: some View {
        let lists = TierList.decode(storedText).sorted { $0.updatedAt > $1.updatedAt }
        List {
            if lists.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Rangliste", systemImage: "list.number")
                } description: {
                    Text("Ordne Snacks, Filme, Übungen oder Restaurants in Stufen von S bis D – mit Emoji oder Foto.")
                } actions: {
                    Button("Erste Rangliste anlegen") { creating = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                }
            }
            ForEach(lists) { list in
                NavigationLink {
                    TierListDetailView(listID: list.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(list.title)
                            .font(.body.weight(.semibold))
                        Text(subtitle(list))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityIdentifier("tier.list.\(list.title)")
            }
            .onDelete { offsets in
                var all = TierList.decode(storedText)
                let ids = offsets.map { lists[$0].id }
                all.removeAll { ids.contains($0.id) }
                storedText = TierList.encode(all)
            }
        }
        .navigationTitle("Ranglisten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Neue Rangliste")
                .accessibilityIdentifier("tier.add")
            }
        }
        .alert("Neue Rangliste", isPresented: $creating) {
            TextField("z. B. Snacks, Filme, Übungen", text: $newTitle)
            Button("Anlegen") {
                let title = newTitle.trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    var all = TierList.decode(storedText)
                    all.append(TierList(title: title))
                    storedText = TierList.encode(all)
                }
                newTitle = ""
            }
            Button("Abbrechen", role: .cancel) { newTitle = "" }
        }
    }

    private func subtitle(_ list: TierList) -> String {
        let top = list.tiers.first.map { list.items(in: $0.id) } ?? []
        var parts = ["\(list.items.count) Einträge"]
        if !top.isEmpty {
            parts.append("\(list.tiers[0].label): " + top.prefix(3).map { $0.emoji.isEmpty ? $0.title : "\($0.emoji) \($0.title)" }.joined(separator: ", "))
        }
        if list.unrankedCount > 0 { parts.append("\(list.unrankedCount) offen") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Eine Rangliste

struct TierListDetailView: View {
    let listID: String

    @AppStorage(SettingsKeys.tierLists) private var storedText = ""
    @State private var addingItem = false
    @State private var editingItem: TierItem?
    @State private var movingItem: TierItem?
    @State private var editingTier: TierRow?
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var addingTier = false
    @State private var newTierLabel = ""
    @State private var sharing: SharedTierImage?
    @State private var confirmReset = false

    var body: some View {
        if let list = TierList.decode(storedText).first(where: { $0.id == listID }) {
            content(list)
        } else {
            ContentUnavailableView("Rangliste gelöscht", systemImage: "list.number")
        }
    }

    private func content(_ list: TierList) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                TierBoard(list: list, onTapItem: { movingItem = $0 }, onTapTier: { editingTier = $0 }, onDrop: { itemID, tierID in
                    update { $0.move(itemID: itemID, to: tierID) }
                })
                UnrankedArea(list: list, onTapItem: { movingItem = $0 }, onDrop: { itemID in
                    update { $0.move(itemID: itemID, to: nil) }
                }, onAdd: { addingItem = true })
                Text("Eintrag antippen: in eine Stufe legen, verschieben, bearbeiten. Lange drücken und ziehen: direkt in eine Stufe. Stufe antippen: umbenennen, Farbe, Reihenfolge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.tagwerkPage)
        .navigationTitle(list.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addingItem = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Eintrag hinzufügen")
                .accessibilityIdentifier("tier.item.add")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        sharing = SharedTierImage(image: render(list), title: list.title)
                    } label: {
                        Label("Als Bild teilen", systemImage: "square.and.arrow.up")
                    }
                    ShareLink(item: "\(list.title)\n\(list.summary)") {
                        Label("Als Text teilen", systemImage: "text.alignleft")
                    }
                    Button {
                        newTitle = list.title
                        renaming = true
                    } label: {
                        Label("Umbenennen", systemImage: "pencil")
                    }
                    Button {
                        addingTier = true
                    } label: {
                        Label("Stufe hinzufügen", systemImage: "plus.rectangle")
                    }
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Label("Alle wieder einordnen", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Mehr")
            }
        }
        .sheet(isPresented: $addingItem) {
            TierItemEditor(tiers: list.tiers, item: nil) { item in
                update { $0.addItem(title: item.title, emoji: item.emoji, imageData: item.imageData, tierID: item.tierID) }
            }
        }
        .sheet(item: $editingItem) { item in
            TierItemEditor(tiers: list.tiers, item: item) { edited in
                update { list in
                    list.updateItem(edited)
                    if edited.tierID != item.tierID { list.move(itemID: edited.id, to: edited.tierID) }
                }
            } onDelete: {
                update { $0.removeItem(id: item.id) }
            }
        }
        .sheet(item: $editingTier) { tier in
            TierRowEditor(tier: tier, isFirst: list.tiers.first?.id == tier.id, isLast: list.tiers.last?.id == tier.id, canDelete: list.tiers.count > 1) { edited in
                update { $0.updateTier(edited) }
            } onMove: { offset in
                update { $0.moveTier(id: tier.id, by: offset) }
            } onDelete: {
                update { $0.removeTier(id: tier.id) }
            }
        }
        .sheet(item: $sharing) { shared in
            TierShareSheet(shared: shared)
        }
        .confirmationDialog(
            movingItem.map { $0.emoji.isEmpty ? $0.title : "\($0.emoji) \($0.title)" } ?? "",
            isPresented: Binding(get: { movingItem != nil }, set: { if !$0 { movingItem = nil } }),
            titleVisibility: .visible,
            presenting: movingItem
        ) { item in
            ForEach(list.tiers) { tier in
                if tier.id != item.tierID {
                    Button("Nach \(tier.label)") { update { $0.move(itemID: item.id, to: tier.id) } }
                }
            }
            if item.tierID != nil {
                Button("Nach vorn") { update { $0.shift(itemID: item.id, by: -1) } }
                Button("Nach hinten") { update { $0.shift(itemID: item.id, by: 1) } }
                Button("Nicht eingeordnet") { update { $0.move(itemID: item.id, to: nil) } }
            }
            Button("Bearbeiten") { editingItem = item }
            Button("Löschen", role: .destructive) { update { $0.removeItem(id: item.id) } }
        }
        .alert("Umbenennen", isPresented: $renaming) {
            TextField("Titel", text: $newTitle)
            Button("Sichern") {
                let title = newTitle.trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { update { $0.title = title } }
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .alert("Stufe hinzufügen", isPresented: $addingTier) {
            TextField("z. B. E oder „Nie wieder“", text: $newTierLabel)
            Button("Hinzufügen") {
                let label = newTierLabel.trimmingCharacters(in: .whitespaces)
                if !label.isEmpty { update { $0.addTier(label: label) } }
                newTierLabel = ""
            }
            Button("Abbrechen", role: .cancel) { newTierLabel = "" }
        }
        .confirmationDialog("Alle Einträge wieder einordnen?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Zurücksetzen", role: .destructive) { update { $0.resetRanking() } }
        } message: {
            Text("Alle Einträge kommen zurück zu „Noch nicht eingeordnet“.")
        }
    }

    private func update(_ change: (inout TierList) -> Void) {
        var all = TierList.decode(storedText)
        guard let index = all.firstIndex(where: { $0.id == listID }) else { return }
        change(&all[index])
        all[index].updatedAt = .now
        withAnimation(.snappy) { storedText = TierList.encode(all) }
    }

    private func render(_ list: TierList) -> UIImage {
        let renderer = ImageRenderer(content:
            VStack(alignment: .leading, spacing: 12) {
                Text(list.title)
                    .font(.title2.weight(.bold))
                TierBoard(list: list, isStatic: true, onTapItem: { _ in }, onTapTier: { _ in }, onDrop: { _, _ in })
            }
            .padding(20)
            .frame(width: 390)
            .background(Color(uiColor: .systemBackground))
        )
        renderer.scale = 3
        return renderer.uiImage ?? UIImage()
    }
}

struct SharedTierImage: Identifiable {
    let id = UUID()
    let image: UIImage
    let title: String
}

private struct TierShareSheet: View {
    let shared: SharedTierImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let image = Image(uiImage: shared.image)
        NavigationStack {
            ScrollView {
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .padding()
            }
            .navigationTitle("Als Bild teilen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: image, preview: SharePreview(shared.title, image: image)) {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

// MARK: - Brett

/// Die Stufen untereinander: farbiges Kürzel links, Einträge rechts.
private struct TierBoard: View {
    let list: TierList
    var isStatic = false
    let onTapItem: (TierItem) -> Void
    let onTapTier: (TierRow) -> Void
    let onDrop: (String, String) -> Void

    @State private var targeted: String?

    var body: some View {
        VStack(spacing: 2) {
            ForEach(list.tiers) { tier in
                let items = list.items(in: tier.id)
                HStack(alignment: .top, spacing: 0) {
                    Button {
                        onTapTier(tier)
                    } label: {
                        Text(tier.label)
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(.black.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.5)
                            .frame(width: 64)
                            .frame(minHeight: 72, maxHeight: .infinity)
                            .background(tier.color)
                    }
                    .buttonStyle(.plain)
                    .disabled(isStatic)
                    .accessibilityLabel("Stufe \(tier.label), \(items.count) Einträge")
                    .accessibilityHint("Umbenennen, Farbe oder Reihenfolge ändern")
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(items) { item in
                            TierChip(item: item, isStatic: isStatic) { onTapItem(item) }
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                    .background(targeted == tier.id ? tier.color.opacity(0.25) : Color.tagwerkCard)
                    .dropDestination(for: String.self) { ids, _ in
                        guard let id = ids.first else { return false }
                        onDrop(id, tier.id)
                        return true
                    } isTargeted: { inside in
                        targeted = inside ? tier.id : (targeted == tier.id ? nil : targeted)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityElement(children: .contain)
            }
        }
    }
}

/// Noch nicht eingeordnete Einträge.
private struct UnrankedArea: View {
    let list: TierList
    let onTapItem: (TierItem) -> Void
    let onDrop: (String) -> Void
    let onAdd: () -> Void

    var body: some View {
        let items = list.items(in: nil)
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    SectionHeader("Noch nicht eingeordnet", systemImage: "tray", tint: .indigo)
                    Button(action: onAdd) {
                        Label("Eintrag", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(.indigo)
                }
                if items.isEmpty {
                    Text(list.items.isEmpty ? "Füge Einträge hinzu und lege sie dann in eine Stufe." : "Alles eingeordnet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(items) { item in
                            TierChip(item: item, isStatic: false) { onTapItem(item) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            onDrop(id)
            return true
        }
    }
}

/// Ein Eintrag als Kachel: Bild oder Emoji, darunter der Name.
private struct TierChip: View {
    let item: TierItem
    let isStatic: Bool
    let onTap: () -> Void

    var body: some View {
        let chip = VStack(spacing: 2) {
            if let data = item.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if !item.emoji.isEmpty {
                Text(item.emoji)
                    .font(.system(size: 30))
                    .frame(width: 52, height: 40)
            }
            if !item.title.isEmpty {
                Text(item.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 76)
            }
        }
        .padding(6)
        .frame(minWidth: 52, minHeight: 52)
        .background(Color.tagwerkPage, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .foregroundStyle(Color.primary)

        if isStatic {
            chip
        } else {
            Button(action: onTap) { chip }
                .buttonStyle(.plain)
                .draggable(item.id) {
                    chip
                }
                .accessibilityLabel(item.title.isEmpty ? item.emoji : item.title)
                .accessibilityHint("Verschieben, bearbeiten oder löschen")
        }
    }
}

// MARK: - Bearbeiten

/// Eintrag anlegen oder bearbeiten: Name, Emoji, Foto, Stufe.
private struct TierItemEditor: View {
    let tiers: [TierRow]
    let item: TierItem?
    let onSave: (TierItem) -> Void
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var emoji = ""
    @State private var imageData: Data?
    @State private var tierID: String?
    @State private var photo: PhotosPickerItem?
    @State private var didLoad = false

    init(tiers: [TierRow], item: TierItem?, onSave: @escaping (TierItem) -> Void, onDelete: (() -> Void)? = nil) {
        self.tiers = tiers
        self.item = item
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $title)
                        .accessibilityIdentifier("tier.item.title")
                    TextField("Emoji (optional)", text: $emoji)
                        .onChange(of: emoji) { _, value in
                            if value.count > 2 { emoji = String(value.prefix(2)) }
                        }
                }
                Section {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label(imageData == nil ? "Foto wählen" : "Anderes Foto", systemImage: "photo")
                    }
                    if let imageData, let image = UIImage(data: imageData) {
                        HStack {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Spacer()
                            Button("Foto entfernen", role: .destructive) { self.imageData = nil }
                        }
                    }
                } footer: {
                    Text("Das Foto wird verkleinert gespeichert und kommt mit in die Sicherung.")
                }
                Section("Stufe") {
                    Picker("Stufe", selection: $tierID) {
                        Text("Noch nicht eingeordnet").tag(String?.none)
                        ForEach(tiers) { tier in
                            Text(tier.label).tag(Optional(tier.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                if let onDelete {
                    Section {
                        Button("Eintrag löschen", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(item == nil ? "Neuer Eintrag" : "Eintrag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        var result = item ?? TierItem(title: "")
                        result.title = title.trimmingCharacters(in: .whitespaces)
                        result.emoji = emoji.trimmingCharacters(in: .whitespaces)
                        result.imageData = imageData
                        result.tierID = tierID
                        onSave(result)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty && emoji.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("tier.item.save")
                }
            }
            .onChange(of: photo) { _, selected in
                guard let selected else { return }
                Task {
                    if let data = try? await selected.loadTransferable(type: Data.self) {
                        imageData = TierStore.thumbnail(from: data)
                    }
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                if let item {
                    title = item.title
                    emoji = item.emoji
                    imageData = item.imageData
                    tierID = item.tierID
                }
            }
        }
    }
}

/// Stufe umbenennen, Farbe wählen, verschieben, löschen.
private struct TierRowEditor: View {
    let tier: TierRow
    let isFirst: Bool
    let isLast: Bool
    let canDelete: Bool
    let onSave: (TierRow) -> Void
    let onMove: (Int) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var colorName = "gray"
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $label)
                }
                Section("Farbe") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: Spacing.s) {
                        ForEach(TierRow.colorNames, id: \.self) { name in
                            let row = TierRow(label: "", colorName: name)
                            Button {
                                colorName = name
                            } label: {
                                Circle()
                                    .fill(row.color)
                                    .frame(width: 40, height: 40)
                                    .overlay {
                                        if colorName == name {
                                            Image(systemName: "checkmark")
                                                .font(.headline)
                                                .foregroundStyle(.black.opacity(0.7))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(TierRow.colorTitle(name))
                            .accessibilityAddTraits(colorName == name ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                }
                Section {
                    Button {
                        onMove(-1)
                        dismiss()
                    } label: {
                        Label("Nach oben", systemImage: "arrow.up")
                    }
                    .disabled(isFirst)
                    Button {
                        onMove(1)
                        dismiss()
                    } label: {
                        Label("Nach unten", systemImage: "arrow.down")
                    }
                    .disabled(isLast)
                }
                if canDelete {
                    Section {
                        Button("Stufe löschen", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    } footer: {
                        Text("Die Einträge der Stufe kommen zurück zu „Noch nicht eingeordnet“.")
                    }
                }
            }
            .navigationTitle("Stufe \(tier.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        var edited = tier
                        let trimmed = label.trimmingCharacters(in: .whitespaces)
                        edited.label = trimmed.isEmpty ? tier.label : String(trimmed.prefix(12))
                        edited.colorName = colorName
                        onSave(edited)
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                label = tier.label
                colorName = tier.colorName
            }
        }
        .presentationDetents([.medium, .large])
    }
}
