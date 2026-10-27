import SwiftUI
import TagwerkKit

/// Planer-Tab mit vier Ansichten: Aufgaben, Agenda (14 Tage), Woche, Leben.
struct PlannerView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case tasks = "Aufgaben"
        case agenda = "Agenda"
        case week = "Woche"
        case life = "Leben"

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
                case .life: LifeView()
                }
            }
            .navigationTitle("Planer")
            .onChange(of: app.plannerModeRequest) { _, request in
                guard let request, let requested = Mode(rawValue: request) else { return }
                mode = requested
                app.plannerModeRequest = nil
            }
            .onAppear {
                if let request = app.plannerModeRequest, let requested = Mode(rawValue: request) {
                    mode = requested
                    app.plannerModeRequest = nil
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Ansicht", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 330)
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
