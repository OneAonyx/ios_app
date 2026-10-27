import SwiftUI
import TagwerkCore
import TagwerkKit

/// Erster Start: Name, was Orbit kann, Berechtigungen.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CalendarService.self) private var calendarService
    @AppStorage(SettingsKeys.userName) private var userName = ""
    @AppStorage(SettingsKeys.onboardingDone) private var onboardingDone = false
    @State private var page = 0
    @State private var notificationsGranted: Bool?

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                features.tag(1)
                permissions.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < 2 {
                    withAnimation { page += 1 }
                } else {
                    onboardingDone = true
                    dismiss()
                }
            } label: {
                Text(page < 2 ? "Weiter" : "Los geht's")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.l)
            .accessibilityIdentifier("onboarding.next")
        }
        .background(Color.tagwerkPage)
        .interactiveDismissDisabled()
    }

    private var welcome: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            OrbitLogo(size: 112)
            VStack(spacing: Spacing.xs) {
                Text("Willkommen bei Orbit")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Dein Tag an einem Ort: Aufgaben, Termine, Medikamente, Training, Ernährung und alles, was sonst ansteht.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            TextField("Wie dürfen wir dich nennen?", text: $userName)
                .textContentType(.givenName)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(Spacing.s)
                .background(Color.tagwerkCard, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            Spacer()
            Spacer()
        }
        .padding(.horizontal, Spacing.l)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Spacer()
            Text("So hilft dir Orbit")
                .font(.largeTitle.bold())
            feature("sun.max", ModuleAccent.today, "Heute", "Fokus, Fälliges und der nächste Termin auf einen Blick.")
            feature("text.cursor", ModuleAccent.tasks, "Schnellerfassung", "„morgen 10 Uhr Zahnarzt“ – Datum und Uhrzeit erkennt Orbit selbst.")
            feature("calendar", ModuleAccent.calendar, "Agenda", "Deine Kalendertermine und Aufgaben der nächsten 14 Tage zusammen.")
            feature("lock.shield", .green, "Privat", "Alles bleibt auf deinem iPhone. Tägliche Sicherung in der Dateien-App.")
            Spacer()
            Spacer()
        }
        .padding(.horizontal, Spacing.l)
    }

    private func feature(_ symbol: String, _ tint: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            IconBadge(systemImage: symbol, tint: tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Spacer()
            Text("Zwei Erlaubnisse")
                .font(.largeTitle.bold())
            Text("Beides kannst du später in den Einstellungen ändern.")
                .foregroundStyle(.secondary)

            permissionRow(
                symbol: "bell.badge", tint: .orange, title: "Mitteilungen",
                text: "Für Erinnerungen an Aufgaben – mit „Erledigt“ direkt in der Mitteilung.",
                granted: notificationsGranted
            ) {
                Task { notificationsGranted = (try? await NotificationSetup.requestAuthorization()) ?? false }
            }
            permissionRow(
                symbol: "calendar", tint: ModuleAccent.calendar, title: "Kalender",
                text: "Damit deine Termine in „Heute“ und der Agenda erscheinen.",
                granted: calendarService.access == .notDetermined ? nil : calendarService.canRead
            ) {
                Task { await calendarService.requestAccess() }
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, Spacing.l)
    }

    private func permissionRow(symbol: String, tint: Color, title: String, text: String, granted: Bool?, request: @escaping () -> Void) -> some View {
        Card {
            HStack(spacing: Spacing.s) {
                IconBadge(systemImage: symbol, tint: tint, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(text).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let granted {
                    Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.title2)
                        .foregroundStyle(granted ? Color.green : Color.secondary)
                } else {
                    Button("Erlauben", action: request)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }
}

/// Das App-Symbol als Logo in der App (Willkommen, App-Sperre).
struct OrbitLogo: View {
    var size: CGFloat = 96

    var body: some View {
        Image("OrbitLogo")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            .shadow(color: .indigo.opacity(0.35), radius: size * 0.12, y: size * 0.05)
            .accessibilityHidden(true)
    }
}
