import SwiftUI

struct ComingSoonView: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let icon: String
    let description: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.accent(for: scheme).opacity(0.3))

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            Text("Coming Soon")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent(for: scheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(AppTheme.accent(for: scheme).opacity(0.1), in: Capsule())

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.surfaceBackground(for: scheme))
        .navigationTitle(title)
    }
}
