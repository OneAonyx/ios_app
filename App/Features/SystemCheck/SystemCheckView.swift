import SwiftUI
import TagwerkCore
import TagwerkKit

struct SystemCheckView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    private var model: SystemCheckModel { app.systemCheck }

    var body: some View {
        List {
            Section {
                summary
            }

            ForEach(SystemCheckID.allCases) { id in
                Section {
                    SystemCheckRow(id: id, state: model.state(for: id))
                    actions(for: id)
                    if id == .claudeBridge {
                        claudeExtras
                    }
                }
            }

            Section {
                ShareLink(item: model.reportText()) {
                    Label("Bericht teilen", systemImage: "square.and.arrow.up")
                }
                Button {
                    model.copyReport()
                } label: {
                    Label("Bericht kopieren", systemImage: "doc.on.doc")
                }
            } header: {
                Text("Bericht")
            } footer: {
                Text("Schick den Bericht an Claude. Danach legen wir fest, welche Funktionen im kostenlosen Betrieb aktiv sind.")
            }

            Section {
                Button("Alle Tests zurücksetzen", role: .destructive) {
                    model.reset()
                }
            }
        }
        .navigationTitle("Systemcheck")
        .onAppear { model.refreshOnActivate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshOnActivate() }
        }
    }

    private var summary: some View {
        let total = SystemCheckID.allCases.count
        return VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text("\(model.passedCount) von \(total) bestanden")
                    .font(.headline)
                Spacer()
                Button("Tests 1–3 starten") {
                    Task { await model.runQuickChecks() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("systemcheck.quick")
            }
            ProgressView(value: Double(model.passedCount), total: Double(total))
                .tint(.green)
            Text("Zeigt, was mit deiner Signatur auf diesem iPhone funktioniert. Die Tests 4–6 brauchen kurz deine Mithilfe.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Spacing.xxs)
    }

    private func actions(for id: SystemCheckID) -> some View {
        let state = model.state(for: id)
        return HStack(spacing: Spacing.xs) {
            Button {
                Task { await model.run(id) }
            } label: {
                Label(buttonTitle(for: id, state: state), systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(state == .running)

            if model.needsConfirmation(id) {
                Button("Hat geklappt") { model.confirm(id, worked: true) }
                    .buttonStyle(.bordered)
                    .tint(.green)
                Button("Nein") { model.confirm(id, worked: false) }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
        }
        .controlSize(.small)
    }

    private func buttonTitle(for id: SystemCheckID, state: SystemCheckState) -> String {
        if id == .claudeBridge { return "Kurzbefehl starten" }
        return state == .pending ? "Testen" : "Erneut testen"
    }

    @ViewBuilder
    private var claudeExtras: some View {
        HStack(spacing: Spacing.xs) {
            Button {
                model.copyClaudePrompt()
            } label: {
                Label("Anfrage kopieren", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            PasteButton(payloadType: String.self) { strings in
                Task { @MainActor in
                    model.verifyPasted(strings.first ?? "")
                }
            }
            .buttonBorderShape(.capsule)
        }
        .controlSize(.small)

        NavigationLink {
            ClaudeShortcutGuideView()
        } label: {
            Label("Anleitung: Kurzbefehl anlegen", systemImage: "list.number")
        }

        if let response = model.lastClaudeResponse {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Letzte Antwort")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(response)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(6)
            }
        }
    }
}

struct SystemCheckRow: View {
    let id: SystemCheckID
    let state: SystemCheckState

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            IconBadge(systemImage: id.systemImage, tint: tint)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(id.number). \(id.title)")
                        .font(.headline)
                    Spacer(minLength: Spacing.xs)
                    SystemCheckStatePill(state)
                }
                Text(id.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let detail = state.detail {
                    Text(detail)
                        .font(.footnote)
                        .padding(.top, Spacing.xxs)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch id {
        case .installation: .indigo
        case .healthKit: ModuleAccent.health
        case .appGroup: ModuleAccent.calendar
        case .alarmKit: ModuleAccent.medication
        case .notifications: ModuleAccent.nutrition
        case .claudeBridge: ModuleAccent.sleep
        }
    }
}
