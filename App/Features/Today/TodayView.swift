import SwiftUI
import TagwerkCore
import TagwerkKit

struct TodayView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    TodayHeader()
                    SigningBanner()
                    SystemCheckCard()
                    RoadmapCard()
                }
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, Spacing.xl)
            }
            .background(Color.tagwerkPage)
            .navigationTitle("Heute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        app.isShowingSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Suche")
                    .accessibilityIdentifier("today.search")

                    Button {
                        app.isShowingSettings = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Einstellungen")
                    .accessibilityIdentifier("today.settings")
                }
            }
            .navigationDestination(isPresented: $app.isShowingSystemCheck) {
                SystemCheckView()
            }
        }
    }
}

/// Datum und Begrüßung, aktualisiert sich jede Minute.
private struct TodayHeader: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ModuleAccent.today)
                    .textCase(.uppercase)
                Text(DayPeriod(date: context.date).greeting)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .padding(.top, Spacing.xs)
    }
}

/// Hinweis, wenn die kostenlose Signatur bald abläuft.
private struct SigningBanner: View {
    private let status = SigningInfo.currentStatus()

    var body: some View {
        let level = status.level(now: .now)
        if status.kind == .freeAppleID, level != .ok {
            Card {
                HStack(alignment: .top, spacing: Spacing.s) {
                    IconBadge(systemImage: "exclamationmark.triangle.fill", tint: .orange)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(level == .expired ? "Signatur abgelaufen" : "App läuft bald ab")
                            .font(.headline)
                        Text("Signatur \(status.remainingText(now: .now)). Öffne SideStore und tippe bei Tagwerk auf „Refresh“.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct SystemCheckCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let passed = app.systemCheck.passedCount
        let total = SystemCheckID.allCases.count
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader("Phase 0", systemImage: "checkmark.seal", tint: .indigo)
                Text("Systemcheck")
                    .font(.title3.bold())
                Text("Sechs kurze Tests zeigen, was auf deinem iPhone funktioniert: Health, Widget, Wecker, Mitteilungen und die Claude-Brücke.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(passed), total: Double(total))
                    .tint(.green)
                HStack {
                    Text("\(passed) von \(total) bestanden")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Öffnen") {
                        app.isShowingSystemCheck = true
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("today.systemcheck")
                }
            }
        }
    }
}

/// Fahrplan der Phasen, damit klar ist, was als Nächstes kommt.
private struct RoadmapCard: View {
    private struct Phase: Identifiable {
        let id: Int
        let title: String
        let systemImage: String
    }

    private let phases: [Phase] = [
        Phase(id: 0, title: "Fundament & Systemcheck", systemImage: "hammer"),
        Phase(id: 1, title: "Heute, Aufgaben, Agenda", systemImage: "checklist"),
        Phase(id: 2, title: "Medikamente", systemImage: "pills"),
        Phase(id: 3, title: "Training", systemImage: "dumbbell"),
        Phase(id: 4, title: "Ernährung & Histamin", systemImage: "fork.knife"),
        Phase(id: 5, title: "Health & Claude-Brücke", systemImage: "heart.text.square"),
        Phase(id: 6, title: "Leben & Feinschliff", systemImage: "sparkles"),
        Phase(id: 7, title: "Developer-Account & iCloud", systemImage: "icloud"),
    ]

    private let currentPhase = 0

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader("Fahrplan", systemImage: "map", tint: ModuleAccent.today)
                ForEach(phases) { phase in
                    HStack(spacing: Spacing.s) {
                        Image(systemName: phase.systemImage)
                            .frame(width: 24)
                            .foregroundStyle(phase.id == currentPhase ? ModuleAccent.today : Color.secondary)
                        Text("Phase \(phase.id): \(phase.title)")
                            .font(.subheadline)
                            .fontWeight(phase.id == currentPhase ? .semibold : .regular)
                            .foregroundStyle(phase.id <= currentPhase ? Color.primary : Color.secondary)
                        Spacer()
                        if phase.id == currentPhase {
                            Text("jetzt")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, 2)
                                .foregroundStyle(ModuleAccent.today)
                                .background(ModuleAccent.today.opacity(0.15), in: Capsule())
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
