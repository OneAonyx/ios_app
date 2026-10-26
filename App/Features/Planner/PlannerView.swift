import SwiftUI
import TagwerkKit

/// Planer-Tab mit drei Ansichten: Aufgaben, Agenda (14 Tage), Woche.
struct PlannerView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case tasks = "Aufgaben"
        case agenda = "Agenda"
        case week = "Woche"

        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var app
    @SceneStorage("planner.mode") private var mode: Mode = .tasks

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .tasks: TaskListsOverview()
                case .agenda: AgendaView()
                case .week: WeekView()
                }
            }
            .navigationTitle("Planer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Ansicht", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        app.openQuickAdd()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Neue Aufgabe")
                    .accessibilityIdentifier("planner.quickadd")
                }
            }
        }
    }
}
