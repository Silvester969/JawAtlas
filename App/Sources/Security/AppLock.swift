import SwiftUI
import Observation
import LocalAuthentication

@MainActor
@Observable
final class AppLock {
    static let enabledKey = "com.jawatlas.appLockEnabled"

    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    private(set) var lastFailureMessage: String?

    init(defaults: UserDefaults = .standard) {
        let enabled = defaults.bool(forKey: AppLock.enabledKey)
        isEnabled = enabled
        isLocked = enabled
    }

    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Passcode"
        }
    }

    var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func setEnabled(_ enabled: Bool) async {
        if enabled {
            guard await authenticate(reason: "Confirm you can unlock JawAtlas") else { return }
        }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: AppLock.enabledKey)
        if !enabled { isLocked = false }
    }

    func lockIfNeeded() {
        if isEnabled { isLocked = true }
    }

    func unlock() async {
        guard isLocked else { return }
        if await authenticate(reason: "Unlock JawAtlas") {
            isLocked = false
        }
    }

    private func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            lastFailureMessage = "Set a device passcode to use the app lock."
            return false
        }
        do {
            let granted = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if granted { lastFailureMessage = nil }
            return granted
        } catch {
            lastFailureMessage = "Could not verify it is you. Try again."
            return false
        }
    }
}

struct LockScreen: View {
    let lock: AppLock

    var body: some View {
        ZStack {
            Color.dsBackground.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.dsBrandPrimary)
                Text("JawAtlas is locked")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                Text("Scans stay private to you on this device.")
                    .font(.subheadline)
                    .foregroundStyle(Color.dsTextSecondary)
                if let message = lock.lastFailureMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Color.dsSafetyOrange)
                        .multilineTextAlignment(.center)
                }
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("Unlock with \(lock.biometryName)", systemImage: "faceid")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(32)
        }
        .task { await lock.unlock() }
    }
}
