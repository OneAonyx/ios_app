import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Suche über Funktionen, Aufgaben (Titel, Notizen, Liste), Medikamente, Lebensmittel, Rezepte und Übungen.
/// Ohne Suchbegriff zeigt sie das Verzeichnis aller Funktionen.
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @Query(sort: \Medication.name) private var medications: [Medication]
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
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
        let foodCatalog = NutritionActions.catalog(in: context)
        let foodMatches = trimmed.count < 2 ? [] : foodCatalog.search(trimmed, limit: 5)
        let recipeMatches = trimmed.count < 2 ? [] : Array(NutritionActions.recipes(in: context).search(trimmed, catalog: foodCatalog).prefix(4))
        let exerciseMatches = trimmed.count < 2 ? [] : Array(TrainingActions.catalog(in: context).search(trimmed).prefix(4))
        let featureMatches = trimmed.isEmpty ? [] : FeatureIndex.search(trimmed, limit: 5)
        let nothing = featureMatches.isEmpty && matches.isEmpty && medicationMatches.isEmpty && foodMatches.isEmpty && recipeMatches.isEmpty && exerciseMatches.isEmpty

        NavigationStack {
            List {
                if trimmed.isEmpty {
                    FeatureDirectorySections()
                }
                if !featureMatches.isEmpty {
                    Section("Funktionen") {
                        ForEach(featureMatches) { feature in
                            FeatureRow(feature: feature)
                        }
                    }
                }
                if !medicationMatches.isEmpty {
                    Section("Medikamente") {
                        ForEach(medicationMatches) { medication in
                            Button {
                                dismiss()
                                app.openMedications()
                                app.healthPath = NavigationPath([medication.stableID])
                            } label: {
                                MedicationSummaryRow(medication: medication, now: .now)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !foodMatches.isEmpty {
                    Section("Lebensmittel") {
                        ForEach(foodMatches) { food in
                            NavigationLink {
                                FoodDetailView(foodID: food.id)
                            } label: {
                                FoodRow(food: food, tolerance: NutritionActions.tolerance(for: food.id, in: context))
                            }
                        }
                    }
                }
                if !recipeMatches.isEmpty {
                    Section("Rezepte") {
                        ForEach(recipeMatches) { recipe in
                            NavigationLink {
                                RecipeDetailView(recipeID: recipe.id)
                            } label: {
                                RecipeRow(recipe: recipe, catalog: foodCatalog, tolerances: NutritionActions.tolerances(in: context))
                            }
                        }
                    }
                }
                if !exerciseMatches.isEmpty {
                    Section("Übungen") {
                        ForEach(exerciseMatches) { exercise in
                            NavigationLink {
                                ExerciseDetailView(exerciseID: exercise.id)
                            } label: {
                                ExerciseListRow(exercise: exercise)
                            }
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
                if !trimmed.isEmpty, nothing {
                    ContentUnavailableView.search(text: trimmed)
                }
            }
            .navigationTitle("Suche")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Funktionen, Aufgaben, Lebensmittel …")
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
