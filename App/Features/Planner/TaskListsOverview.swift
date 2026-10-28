import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Planer → Aufgaben: feste Listen mit Anzahl und eigene Listen.
struct TaskListsOverview: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.createdAt) private var allTasks: [TaskItem]
    @Query(sort: \TaskList.sortIndex) private var lists: [TaskList]
    @State private var editingList: TaskList?
    @State private var isCreatingList = false

    private let smartLists: [SmartList] = [.today, .planned, .inbox, .flagged, .done]

    var body: some View {
        let now = Date.now
        let calendar = AppModel.calendar
        List {
            Section {
                ForEach(smartLists) { smart in
                    NavigationLink {
                        TaskListScreen(scope: .smart(smart))
                    } label: {
                        ListRowLabel(
                            title: smart.title,
                            symbol: smart.systemImage,
                            tint: tint(for: smart),
                            count: smart == .done ? nil : allTasks.filter { smart.includes($0.facts, now: now, calendar: calendar) }.count
                        )
                    }
                    .accessibilityIdentifier("smartlist.\(smart.rawValue)")
                }
            }

            Section {
                ForEach(lists) { list in
                    NavigationLink {
                        TaskListScreen(scope: .list(list))
                    } label: {
                        ListRowLabel(
                            title: list.name,
                            symbol: list.symbol,
                            tint: ListColor.color(named: list.colorName),
                            count: list.openTaskCount
                        )
                    }
                    .contextMenu {
                        Button {
                            editingList = list
                        } label: {
                            Label("Bearbeiten", systemImage: "pencil")
                        }
                    }
                }
                .onDelete(perform: deleteLists)
                .onMove(perform: moveLists)

                Button {
                    isCreatingList = true
                } label: {
                    Label("Neue Liste", systemImage: "plus.circle")
                }
                NavigationLink {
                    ReminderImportView()
                } label: {
                    Label("Aus Erinnerungen übernehmen", systemImage: "square.and.arrow.down.on.square")
                }
                .accessibilityIdentifier("lists.importReminders")
            } header: {
                Text("Listen")
            } footer: {
                if lists.isEmpty {
                    Text("Tipp: „#Arbeit“ in der Schnellerfassung legt die Liste „Arbeit“ automatisch an.")
                }
            }
        }
        .sheet(item: $editingList) { list in
            ListEditorView(list: list)
        }
        .sheet(isPresented: $isCreatingList) {
            ListEditorView(list: nil)
        }
    }

    private func tint(for smart: SmartList) -> Color {
        switch smart {
        case .today: ModuleAccent.today
        case .planned: ModuleAccent.calendar
        case .inbox: .gray
        case .flagged: .orange
        case .all: ModuleAccent.tasks
        case .done: .green
        }
    }

    private func deleteLists(at offsets: IndexSet) {
        for index in offsets {
            context.delete(lists[index])
        }
        TaskActions.save(context)
    }

    private func moveLists(from source: IndexSet, to destination: Int) {
        var reordered = lists
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, list) in reordered.enumerated() {
            list.sortIndex = Double(index)
        }
        TaskActions.save(context)
    }
}

struct ListRowLabel: View {
    let title: String
    let symbol: String
    let tint: Color
    let count: Int?

    var body: some View {
        HStack(spacing: Spacing.s) {
            IconBadge(systemImage: symbol, tint: tint, size: 30)
            Text(title)
            Spacer()
            if let count, count > 0 {
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Neue Liste anlegen oder bestehende bearbeiten.
struct ListEditorView: View {
    let list: TaskList?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskList.sortIndex) private var lists: [TaskList]
    @State private var name = ""
    @State private var symbol = "list.bullet"
    @State private var colorName = ListColor.indigo.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: Spacing.s) {
                        IconBadge(systemImage: symbol, tint: ListColor.color(named: colorName), size: 40)
                        TextField("Name der Liste", text: $name)
                            .font(.title3)
                    }
                }
                Section("Farbe") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: Spacing.s) {
                        ForEach(ListColor.allCases) { option in
                            Circle()
                                .fill(option.color)
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if option.rawValue == colorName {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { colorName = option.rawValue }
                                .accessibilityLabel(option.rawValue)
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                }
                Section("Symbol") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: Spacing.s) {
                        ForEach(ListSymbol.all, id: \.self) { option in
                            Image(systemName: option)
                                .frame(width: 40, height: 40)
                                .background(
                                    option == symbol ? ListColor.color(named: colorName).opacity(0.2) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                                )
                                .onTapGesture { symbol = option }
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                }
            }
            .navigationTitle(list == nil ? "Neue Liste" : "Liste bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let list {
                    name = list.name
                    symbol = list.symbol
                    colorName = list.colorName
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let list {
            list.name = trimmed
            list.symbol = symbol
            list.colorName = colorName
        } else {
            let newList = TaskList(name: trimmed, symbol: symbol, colorName: colorName, sortIndex: Double(lists.count))
            context.insert(newList)
        }
        TaskActions.save(context)
        dismiss()
    }
}
