import SwiftUI
import TagwerkKit
import TipKit

/// Dezente Hinweise statt eines Tutorials. Jeder erscheint höchstens einmal.
enum OrbitTips {
    static func configure() {
        if AppInfo.isUITesting {
            Tips.hideAllTipsForTesting()
        }
        try? Tips.configure([.displayFrequency(.daily)])
    }
}

struct QuickAddTip: Tip {
    var title: Text { Text("Schnell eintragen") }
    var message: Text? { Text("Schreib einfach „morgen 10 Uhr Zahnarzt“ oder „jeden Montag Müll raus“. Orbit erkennt Tag, Uhrzeit und Wiederholung.") }
    var image: Image? { Image(systemName: "plus.bubble") }
}

struct WidgetTip: Tip {
    var title: Text { Text("Orbit auf dem Home-Bildschirm") }
    var message: Text? { Text("Lange auf den Home-Bildschirm tippen → Bearbeiten → Widget hinzufügen → Orbit. „Aufgaben“ lässt sich direkt abhaken.") }
    var image: Image? { Image(systemName: "square.grid.2x2") }
}

struct LifeTip: Tip {
    var title: Text { Text("Routinen, Verträge, Geburtstage") }
    var message: Text? { Text("Starte mit einer Vorlage, z. B. Morgenroutine oder Handyvertrag. Orbit erinnert an Kündigungsfristen und Geburtstage.") }
    var image: Image? { Image(systemName: "sparkles") }
}

struct ProgressTip: Tip {
    var title: Text { Text("Wie schnell geht's voran?") }
    var message: Text? { Text("„Fortschritt“ zeigt pro Übung, ob du zu schnell, gut oder zu langsam steigerst, und bewertet dein Körpergewicht.") }
    var image: Image? { Image(systemName: "chart.line.uptrend.xyaxis") }
}
