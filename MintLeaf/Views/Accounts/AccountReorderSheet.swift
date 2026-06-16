import SwiftUI
import SwiftData

/// A dedicated sheet for reordering accounts. Uses plain (non-button) rows so the
/// drag gesture isn't swallowed — reliable on both macOS and iOS.
struct AccountReorderSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var ordered: [Account] = []

    private var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ordered) { account in
                        HStack(spacing: 12) {
                            Image(systemName: "line.3.horizontal")
                                .font(.caption)
                                .foregroundStyle(.tertiary)

                            Image(systemName: account.type.icon)
                                .font(.body)
                                .foregroundStyle(Color(hex: account.colorHex))
                                .frame(width: 26, height: 26)
                                .background(Color(hex: account.colorHex).opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(account.name)
                                    .font(.subheadline.weight(.medium))
                                Text(account.type.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(CurrencyFormatter.shared.format(account.currentBalance, currency: account.currency))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { source, destination in
                        ordered.move(fromOffsets: source, toOffset: destination)
                    }
                } header: {
                    Text("Drag to reorder")
                }
            }
            .premiumList()
            .navigationTitle("Reorder Accounts")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .onAppear { ordered = activeAccounts }
        .macOSSheet(width: 440, height: 460)
    }

    private func save() {
        for (index, account) in ordered.enumerated() {
            account.sortOrder = index
        }
        let archived = accounts.filter { $0.isArchived }
        for (offset, account) in archived.enumerated() {
            account.sortOrder = ordered.count + offset
        }
        try? context.save()
        dismiss()
    }
}
