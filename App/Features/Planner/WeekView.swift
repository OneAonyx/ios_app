import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Wochenübersicht Mo–So mit Blättern zwischen den Wochen.
struct WeekView: View {
    @Environment(AppModel.self) private var app
    @Environment(CalendarService.self) private var calendarService
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @AppStorage(SettingsKeys.showCalendarEvents) private var showEvents = true
    @AppStorage(SettingsKeys.hiddenCalendarIDs) private var hiddenCalendarIDs = ""
    @State private var weekOffset = 0

    var body: some View {
        let now = Date.now
        let calendar = AppModel.calendar
        let thisMonday = AgendaBuilder.startOfWeek(containing: now, calendar: calendar)
        let monday = calendar.date(byAdding: .day, value: 7 * weekOffset, to: thisMonday) ?? thisMonday
        let sunday = calendar.date(byAdding: .day, value: 7, to: monday) ?? monday
        let source = AgendaSource(tasks: tasks, calendarService: calendarService, showEvents: showEvents, hiddenCalendarIDsText: hiddenCalendarIDs)
        let days = AgendaBuilder.build(items: source.items(from: monday, to: sunday), from: monday, days: 7, now: now, calendar: calendar)

        ScrollView {
            VStack(spacing: Spacing.s) {
                weekHeader(monday: monday, calendar: calendar)
                ForEach(days) { day in
                    dayCard(day, source: source, now: now, calendar: calendar)
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.tagwerkPage)
    }

    private func weekHeader(monday: Date, calendar: Calendar) -> some View {
        let week = calendar.component(.weekOfYear, from: monday)
        let end = calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
        let range = "\(calendar.component(.day, from: monday)). – \(GermanCalendar.shortDate(end, calendar: calendar).components(separatedBy: ", ").last ?? "")"
        return HStack {
            Button {
                withAnimation(.snappy) { weekOffset -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: TouchTarget.standard, height: TouchTarget.standard)
            }
            .accessibilityLabel("Vorige Woche")
            Spacer()
            VStack(spacing: 2) {
                Text("KW \(week)")
                    .font(.headline)
                Text(range)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onTapGesture { withAnimation(.snappy) { weekOffset = 0 } }
            Spacer()
            Button {
                withAnimation(.snappy) { weekOffset += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: TouchTarget.standard, height: TouchTarget.standard)
            }
            .accessibilityLabel("Nächste Woche")
        }
        .padding(.top, Spacing.xs)
    }

    private func dayCard(_ day: AgendaDay, source: AgendaSource, now: Date, calendar: Calendar) -> some View {
        let isToday = calendar.isDate(day.date, inSameDayAs: now)
        let weekday = GermanCalendar.longWeekdays[calendar.component(.weekday, from: day.date) - 1]
        return Card(padding: Spacing.s) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(weekday)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isToday ? ModuleAccent.today : Color.primary)
                    Text("\(calendar.component(.day, from: day.date)).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if isToday {
                        Text("Heute")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(ModuleAccent.today)
                            .background(ModuleAccent.today.opacity(0.15), in: Capsule())
                    }
                    Spacer()
                    if !day.isEmpty {
                        Text("\(day.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if day.isEmpty {
                    Text("frei")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(day.allDay + day.timed) { item in
                        AgendaRow(item: item, task: source.task(for: item), compact: true) { task in
                            app.editingTask = task
                        }
                    }
                }
            }
        }
    }
}
