import SwiftUI
import SwiftData

struct PrivacyDashboardView: View {
    @Environment(\.colorScheme) private var scheme
    @Query private var accounts: [Account]
    @Query private var transactions: [Transaction]
    @AppStorage("biometricLockEnabled") private var biometricEnabled = false

    private var totalTransactions: Int { transactions.count }
    private var totalAccounts: Int { accounts.count }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Your data is stored locally", systemImage: "lock.shield.fill")
                        .font(.headline)
                        .foregroundStyle(AppTheme.accent(for: scheme))
                    Text("Mint Leaf keeps all financial data on your device. No telemetry, no analytics, no ads.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Security") {
                Toggle("Require \(BiometricAuth.biometricName) to open", isOn: $biometricEnabled)
                    .disabled(!BiometricAuth.isAvailable)

                HStack {
                    Label("Encryption", systemImage: "lock.fill")
                    Spacer()
                    Text("File Protection Complete")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label("Cloud Sync", systemImage: "icloud")
                    Spacer()
                    Text("iCloud (E2E encrypted)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Data Summary") {
                HStack {
                    Text("Accounts")
                    Spacer()
                    Text("\(totalAccounts)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Transactions")
                    Spacer()
                    Text("\(totalTransactions)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("What We Don't Do") {
                Label("No bank credentials stored", systemImage: "checkmark.circle")
                Label("No Plaid or third-party data access", systemImage: "checkmark.circle")
                Label("No usage analytics or tracking", systemImage: "checkmark.circle")
                Label("No advertising or data selling", systemImage: "checkmark.circle")
                Label("No remote servers (local-first)", systemImage: "checkmark.circle")
            }
            .foregroundStyle(AppTheme.accent(for: scheme))
        }
        .navigationTitle("Privacy")
    }
}
