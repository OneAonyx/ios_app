import CoreLocation
import SwiftUI
import TagwerkCore
import TagwerkKit
import UIKit

/// App-Sperre und Gym-Ankunft in den Einstellungen.
struct PrivacyGymSection: View {
    @AppStorage(SettingsKeys.appLock) private var appLock = false
    @State private var lockMessage: String?

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { appLock }, set: { newValue in
                if newValue {
                    Task {
                        if await AppLock.confirm() {
                            appLock = true
                            lockMessage = nil
                        } else {
                            lockMessage = "Face ID oder Code konnte nicht geprüft werden."
                        }
                    }
                } else {
                    appLock = false
                }
            })) {
                Label("App-Sperre mit \(AppLock.biometryName)", systemImage: "lock.fill")
            }
            .disabled(!AppLock.canUse && !appLock)
            .accessibilityIdentifier("settings.appLock")
            if let lockMessage {
                Text(lockMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            NavigationLink {
                GymArrivalSettingsView()
            } label: {
                Label("Gym-Ankunft", systemImage: "location.fill")
            }
            .accessibilityIdentifier("settings.gym")
        } header: {
            Text("Privatsphäre und Orte")
        } footer: {
            Text(AppLock.canUse
                ? "Mit App-Sperre ist Orbit nach dem Verlassen verdeckt, auch im App-Umschalter."
                : "Für die App-Sperre braucht dein iPhone einen Code.")
        }
    }
}

struct GymArrivalSettingsView: View {
    @State private var gym = GymArrival.shared
    @AppStorage(SettingsKeys.gymArrival) private var isEnabled = false
    @AppStorage(SettingsKeys.gymLatitude) private var latitude: Double = 0
    @State private var isLocating = false
    @State private var message: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                if let location = gym.gymLocation, latitude != 0 {
                    LabeledContent("Gespeicherter Ort", value: String(format: "%.4f, %.4f", location.latitude, location.longitude))
                } else {
                    Text("Noch kein Ort gespeichert. Speichere ihn, wenn du im Gym bist.")
                        .foregroundStyle(.secondary)
                }
                Button {
                    isLocating = true
                    message = nil
                    Task {
                        let saved = await gym.saveCurrentLocation()
                        isLocating = false
                        message = saved ? "Ort gespeichert." : "Standort nicht verfügbar. Erlaube den Ortszugriff in den Einstellungen."
                        if saved, isEnabled { await gym.enable() }
                    }
                } label: {
                    HStack {
                        Label("Aktuellen Ort als Gym speichern", systemImage: "mappin.and.ellipse")
                        if isLocating {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isLocating)
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Ort")
            }

            Section {
                Toggle("Mitteilung bei Ankunft", isOn: Binding(get: { isEnabled }, set: { newValue in
                    Task {
                        if newValue { await gym.enable() } else { await gym.disable() }
                        gym.refreshAuthorization()
                    }
                }))
                .disabled(gym.gymLocation == nil || latitude == 0)
                if isEnabled && !gym.hasAlwaysAccess {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Label("Ortszugriff „Immer“ fehlt", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Ohne „Immer“ merkt Orbit die Ankunft nur, solange die App offen ist. Ändern unter Einstellungen → Orbit → Standort.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Einstellungen öffnen") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }
            } footer: {
                Text("Einmal am Tag, wenn du im Umkreis von \(Int(GymArrival.radius)) m ankommst: „Du bist im Gym – Push starten?“. Der Ort bleibt auf deinem iPhone.")
            }
        }
        .navigationTitle("Gym-Ankunft")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { gym.refreshAuthorization() }
    }
}
