import SwiftUI

struct LockScreenView: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage("biometricLockEnabled") private var biometricEnabled = false
    @Binding var isUnlocked: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppTheme.accentGradient(for: scheme))

            Text("Mint Leaf")
                .font(.largeTitle.bold())

            Text("Locked")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                Task { await unlock() }
            } label: {
                Label("Unlock with \(BiometricAuth.biometricName)", systemImage: biometricIcon)
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: 280)
                    .background(AppTheme.accentGradient(for: scheme), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(scheme == .dark ? .black : .white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.surfaceBackground(for: scheme))
        .task {
            if biometricEnabled {
                await unlock()
            } else {
                isUnlocked = true
            }
        }
    }

    private var biometricIcon: String {
        switch BiometricAuth.biometricType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.shield"
        }
    }

    private func unlock() async {
        let result = await BiometricAuth.authenticate()
        switch result {
        case .success:
            withAnimation { isUnlocked = true }
        case .failed, .unavailable:
            break
        }
    }
}
