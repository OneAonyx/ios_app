import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Suche über Aufgaben (Titel, Notizen, Liste) und Medikamente. Weitere Bereiche folgen mit ihren Phasen.
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @Query(sort: \Medication.name) private var medications: [Medication]
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var editingTask: TaskItem?

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let matches = trimmed.isEmpty ? [] : tasks.filter { task in
            task.title.localizedStandardContains(trimmed)
                || task.notes.localizedStandardContains(trimmed)
                || (task.list?.name.localizedStandardContains(trimmed) ?? false)
        }
        let open = matches.filter { !$0.isDone }
        let done = matches.filter(\.isDone)
        let medicationMatches = trimmed.isEmpty ? [] : medications.filter { medication in
            medication.name.localizedStandardContains(trimmed)
                || medication.dosage.localizedStandardContains(trimmed)
                || medication.notes.localizedStandardContains(trimmed)
        }

        NavigationStack {
            List {
                if !medicationMatches.isEmpty {
                    Section("Medikamente") {
                        ForEach(medicationMatches) { medication in
                            Button {
                                dismiss()
                                app.openMedications()
                                app.healthPath = [medication.stableID]
                            } label: {
                                MedicationSummaryRow(medication: medication, now: .now)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !open.isEmpty {
                    Section("Offen") {
                        ForEach(open) { task in
                            TaskRow(task: task, onOpen: { editingTask = $0 })
                        }
                    }
                }
                if !done.isEmpty {
                    Section("Erledigt") {
                        ForEach(done.prefix(30)) { task in
                            TaskRow(task: task, onOpen: { editingTask = $0 })
                        }
                    }
                }
            }
            .overlay {
                if trimmed.isEmpty {
                    ContentUnavailableView(
                        "Suche",
                        systemImage: "magnifyingglass",
                        description: Text("Durchsucht Aufgaben, Notizen, Listen und Medikamente. Übungen und Lebensmittel kommen mit ihren Phasen dazu.")
                    )
                } else if matches.isEmpty && medicationMatches.isEmpty {
                    ContentUnavailableView.search(text: trimmed)
                }
            }
            .navigationTitle("Suche")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Aufgaben, Medikamente …")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("search.done")
                }
            }
            .sheet(item: $editingTask) { task in
                TaskEditorView(task: task)
            }
        }
    }
}
