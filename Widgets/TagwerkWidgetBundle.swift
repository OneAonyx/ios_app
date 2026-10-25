import SwiftUI
import WidgetKit

/// Die einzige Extension der App (wegen des 3-App-Limits bei kostenlosem SideStore-Betrieb).
/// Hier landen später alle Widgets, Live Activities und Kontrollzentrum-Controls.
@main
struct TagwerkWidgetBundle: WidgetBundle {
    var body: some Widget {
        SystemCheckWidget()
        AlarmLiveActivity()
    }
}
