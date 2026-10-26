import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Runder Abhak-Knopf. Der Rand zeigt die Priorität.
struct CompletionButton: View {
    let isDone: Bool
    let priority: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(isDone ? Color.green : ringColor)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: TouchTarget.standard, height: TouchTarget.standard)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDone ? "Als offen markieren" : "Als erledigt markieren")
    }

    private var ringColor: Color {
        switch priority {
        case 3: .red
        case 2: .orange
        case 1: .blue
        default: Color.secondary
        }
    }
}

/// Eine Aufgabe in Listen und Karten.
struct TaskRow: View {
    let task: TaskItem
    var showList = true
    /// Wird beim Antippen aufgerufen (öffnet den Editor).
    var onOpen: (TaskItem) -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.xxs) {
            CompletionButton(isDone: task.isDone, priority: task.priority) {
                withAnimation(.snappy) {
                    TaskActions.toggleCompletion(task, in: context, calendar: AppModel.calendar)
                }
                app.tasksChanged()
            }
            .sensoryFeedback(.success, trigger: task.isDone) { _, isDone in isDone }

            // Ein eigener Knopf für „öffnen“: zuverlässig antippbar und für VoiceOver klar.
            Button {
                onOpen(task)
            } label: {
                HStack(spacing: Spacing.xs) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                            if task.priority > 0 {
                                Text(String(repeating: "!", count: task.priority))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(task.priority == 3 ? Color.red : Color.orange)
                            }
                            Text(task.title.isEmpty ? "Ohne Titel" : task.title)
                                .strikethrough(task.isDone)
                                .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
                                .lineLimit(typeSize.isAccessibilitySize ? 5 : 2)
                        }
                        metaLine
                    }
                    Spacer(minLength: Spacing.xs)
                    if task.isFlagged {
                        Image(systemName: "flag.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Markiert")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Öffnet die Aufgabe")
        }
    }

    /// Zusatzinfos brechen um statt abgeschnitten zu werden (wichtig bei großer Schrift).
    @ViewBuilder
    private var metaLine: some View {
        let parts = metaParts
        if !parts.isEmpty {
            FlowLayout(spacing: Spacing.xs, lineSpacing: 2) {
                ForEach(parts, id: \.text) { part in
                    Label(part.text, systemImage: part.symbol)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(part.color)
                        .lineLimit(1)
                }
            }
            .font(.caption)
        }
    }

    private struct MetaPart {
        let text: String
        let symbol: String
        let color: Color
    }

    private var metaParts: [MetaPart] {
        var parts: [MetaPart] = []
        let now = Date.now
        let calendar = AppModel.calendar
        if let due = task.dueDate {
            let overdue = task.isOverdue(now: now, calendar: calendar)
            parts.append(MetaPart(
                text: DueFormatter.label(due: due, hasTime: task.hasDueTime, now: now, calendar: calendar),
                symbol: overdue ? "exclamationmark.circle" : "calendar",
                color: overdue && !task.isDone ? .red : .secondary
            ))
        }
        if task.recurrence != nil {
            parts.append(MetaPart(text: "Wdh.", symbol: "repeat", color: .secondary))
        }
        let progress = task.subtaskProgress
        if progress.total > 0 {
            parts.append(MetaPart(text: "\(progress.done)/\(progress.total)", symbol: "checklist", color: .secondary))
        }
        if showList, let list = task.list {
            parts.append(MetaPart(text: list.name, symbol: list.symbol, color: ListColor.color(named: list.colorName)))
        }
        if task.facts.isFocus(on: now, calendar: calendar), !task.isDone {
            parts.append(MetaPart(text: "Fokus", symbol: "scope", color: ModuleAccent.today))
        }
        return parts
    }
}

/// Kontextmenü und Wischgesten für Aufgaben in Listen.
struct TaskRowActions: ViewModifier {
    let task: TaskItem
    let allTasks: [TaskItem]

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var focusLimitReached = false

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    TaskActions.toggleCompletion(task, in: context, calendar: AppModel.calendar)
                    app.tasksChanged()
                } label: {
                    Label(task.isDone ? "Öffnen" : "Erledigt", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
                }
                .tint(.green)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    TaskActions.delete(task, in: context)
                    app.tasksChanged()
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
                if !task.isDone {
                    Button {
                        TaskActions.moveToTomorrow(task, in: context, calendar: AppModel.calendar)
                        app.tasksChanged()
                    } label: {
                        Label("Morgen", systemImage: "arrow.turn.up.right")
                    }
                    .tint(.indigo)
                }
            }
            .contextMenu {
                if !task.isDone {
                    Button {
                        focusLimitReached = !TaskActions.toggleFocus(task, allTasks: allTasks, in: context, calendar: AppModel.calendar)
                    } label: {
                        let inFocus = task.facts.isFocus(on: .now, calendar: AppModel.calendar)
                        Label(inFocus ? "Aus dem Fokus nehmen" : "Fokus heute", systemImage: "scope")
                    }
                    Button {
                        task.isFlagged.toggle()
                        TaskActions.save(context)
                    } label: {
                        Label(task.isFlagged ? "Markierung entfernen" : "Markieren", systemImage: "flag")
                    }
                    Button {
                        TaskActions.moveToTomorrow(task, in: context, calendar: AppModel.calendar)
                        app.tasksChanged()
                    } label: {
                        Label("Auf morgen", systemImage: "arrow.turn.up.right")
                    }
                    Button {
                        TaskActions.moveToNextWeek(task, in: context, calendar: AppModel.calendar)
                        app.tasksChanged()
                    } label: {
                        Label("Auf nächste Woche", systemImage: "calendar.badge.clock")
                    }
                }
                Button(role: .destructive) {
                    TaskActions.delete(task, in: context)
                    app.tasksChanged()
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            }
            .alert("Fokus ist voll", isPresented: $focusLimitReached) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Es sind schon \(FocusRules.maximum) Aufgaben im Fokus. Nimm zuerst eine heraus.")
            }
    }
}

extension View {
    func taskRowActions(_ task: TaskItem, allTasks: [TaskItem]) -> some View {
        modifier(TaskRowActions(task: task, allTasks: allTasks))
    }
}
