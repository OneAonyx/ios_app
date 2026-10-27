import SwiftUI
import WidgetKit

/// Die einzige Extension der App (wegen des 3-App-Limits bei kostenlosem SideStore-Betrieb).
/// Hier liegen alle Widgets, Live Activities und Kontrollzentrum-Controls.
@main
struct TagwerkWidgetBundle: WidgetBundle {
    var body: some Widget {
        DailyWidgets().body
        MedicationWidget()
        TrainingWidget()
        NutritionWidget()
        MedicationControl()
        TrainingControl()
        WaterControl()
        WorkoutLiveActivity()
        SystemCheckWidget()
        AlarmLiveActivity()
    }
}

/// Heute, Aufgaben und die Knöpfe fürs Kontrollzentrum (eigenes Bündel, weil ein
/// Bündel höchstens zehn Einträge direkt enthalten kann).
struct DailyWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        TasksWidget()
        QuickTaskControl()
        CheckInControl()
    }
}
