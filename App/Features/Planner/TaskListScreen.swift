import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Was eine Aufgabenliste zeigt: eine feste Liste („Heute“) oder eine eigene Liste.
enum TaskScope {
    case smart(SmartList)
    case list(TaskList)

    var title: String {
        switch self {
        case .smart(let smart): smart.title
        case .list(let list): list.name
        }
    }

    func includes(_ task: TaskItem, now: Date, calendar: Calendar) -> Bool {
        switch self {
        case .smart(let smart):
            smart.includes(task.facts, now: now, calendar: calendar)
        case .list(let list):
            task.list?.stableID == list.stableID
        }
    }

    /// Erledigte Aufgaben dieser Ansicht (unter „Erledigt“ einklappbar).
    func includesDone(_ task: TaskItem) -> Bool {
        guard task.isDone else { return false }
        switch self {
        case .smart(let smart):
            return smart == .done
        case .list(let list):
            return task.list?.stableID == list.stableID
        }
    }

    var presetList: TaskList? {
        if case .list(let list) = self { return list }
        return nil
    }

    var emptyText: (title: String, message: String, symbol: String) {
        switch self {
        case .smart(.today): ("Alles erledigt", "Für heute steht nichts mehr an.", "sun.max")
        case .smart(.inbox): ("Eingang leer", "Neue Aufgaben ohne Datum und Liste landen hier.", "tray")
        case .smart(.flagged): ("Nichts markiert", "Markiere wichtige Aufgaben über das Kontextmenü.", "flag")
        case .smart(.done): ("Noch nichts erledigt", "Erledigte Aufgaben erscheinen hier.", "checkmark.circle")
        case .smart: ("Keine Aufgaben", "Hier ist gerade nichts geplant.", "calendar")
        case .list: ("Liste ist leer", "Füge über „+“ die erste Aufgabe hinzu.", "list.bullet")
        }
    }
}

struct TaskListScreen: View {
    let scope: TaskScope

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.createdAt) private var allTasks: [TaskItem]
    @State private var showDone = false

    var body: some View {
        let now = Date.now
        let calendar = AppModel.calendar
        let open = TaskOrdering.sorted(
            allTasks.filter { !$0.isDone && scope.includes($0, now: now, calendar: calendar) },
            facts: \.facts, now: now, calendar: calendar
        )
        let done = TaskOrdering.sorted(
            allTasks.filter { scope.includesDone($0) },
            facts: \.facts, now: now, calendar: calendar
        )
        let isDoneList: Bool = {
            if case .smart(.done) = scope { return true }
            return false
        }()

        List {
            if isDoneList {
                ForEach(done.prefix(200)) { task in
                    row(task)
                }
            } else {
                ForEach(open) { task in
                    row(task)
                }
                if !done.isEmpty {
                    Section {
                        if showDone {
                            ForEach(done.prefix(50)) { task in
                                row(task)
                            }
                        }
                    } header: {
                        Button {
                            withAnimation { showDone.toggle() }
                        } label: {
                            HStack {
                                Text("Erledigt (\(done.count))")
                                Spacer()
                                Image(systemName: showDone ? "chevron.up" : "chevron.down")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .overlay {
            if (isDoneList && done.isEmpty) || (!isDoneList && open.isEmpty && done.isEmpty) {
                let empty = scope.emptyText
                ContentUnavailableView(empty.title, systemImage: empty.symbol, description: Text(empty.message))
            }
        }
        .navigationTitle(scope.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    app.openQuickAdd(list: scope.presetList)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Neue Aufgabe")
            }
        }
    }

    private func row(_ task: TaskItem) -> some View {
        TaskRow(task: task, showList: scope.presetList == nil) { app.editingTask = $0 }
            .taskRowActions(task, allTasks: allTasks)
    }
}
