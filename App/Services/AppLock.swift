import LocalAuthentication
import SwiftUI
import TagwerkCore
import TagwerkKit
import UIKit

/// App-Sperre: Beim Verlassen der App wird ein Sichtschutz über alles gelegt (auch über
/// offene Blätter und den App-Umschalter). Entsperrt wird mit Face ID oder dem Gerätecode.
@MainActor
final class AppLock {
    static let shared = AppLock()

    private var window: UIWindow?
    private var isAuthenticating = false
    private var hasActivated = false
    /// Nach dem Sperren einmal automatisch nach Face ID fragen, nicht nach jedem Abbrechen.
    private var promptsOnActivate = false

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.appLock) && !AppInfo.isUITesting
    }

    var isLocked: Bool { window != nil }

    /// Face ID, Touch ID oder Code verfügbar?
    static var canUse: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Gerätecode"
        }
    }

    /// App ist aktiv: beim ersten Start sperren, dann einmal nach Face ID fragen.
    func appBecameActive() {
        if !hasActivated {
            hasActivated = true
            lock()
        }
        guard promptsOnActivate else { return }
        promptsOnActivate = false
        Task { await unlock() }
    }

    /// App geht in den Hintergrund (oder wird beim Start gesperrt).
    func lock() {
        guard isEnabled, window == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let host = UIHostingController(rootView: LockScreen(onUnlock: { [weak self] in
            Task { await self?.unlock() }
        }))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        promptsOnActivate = true
    }

    /// App ist wieder aktiv: entsperren lassen.
    func unlock() async {
        guard window != nil, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedCancelTitle = "Abbrechen"
        let success = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Orbit entsperren")) ?? false
        if success {
            UIView.animate(withDuration: 0.25, animations: {
                self.window?.alpha = 0
            }, completion: { _ in
                self.window?.isHidden = true
                self.window = nil
            })
        }
    }

    /// Einmal prüfen, bevor die Sperre eingeschaltet wird.
    static func confirm() async -> Bool {
        let context = LAContext()
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "App-Sperre für Orbit einschalten")) ?? false
    }
}

private struct LockScreen: View {
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThickMaterial)
                .ignoresSafeArea()
            VStack(spacing: Spacing.m) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(ModuleAccent.today)
                Text("Orbit ist gesperrt")
                    .font(.title2.weight(.bold))
                Text("Deine Gesundheitsdaten sind geschützt.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action: onUnlock) {
                    Label("Entsperren mit \(AppLock.biometryName)", systemImage: "faceid")
                        .font(.headline)
                        .padding(.horizontal, Spacing.m)
                        .padding(.vertical, Spacing.s)
                }
                .buttonStyle(.borderedProminent)
                .tint(ModuleAccent.today)
                .padding(.top, Spacing.s)
            }
            .padding(Spacing.l)
        }
    }
}
