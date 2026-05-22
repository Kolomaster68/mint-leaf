import SwiftUI

struct TransactionRow: View {
    @Environment(\.colorScheme) private var scheme
    let transaction: Transaction
    var showAccount: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if let category = transaction.category {
                Image(systemName: category.icon)
                    .font(.body)
                    .foregroundStyle(Color(hex: category.colorHex))
                    .frame(width: 32, height: 32)
                    .background(Color(hex: category.colorHex).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(transaction.title)
                        .font(.body)
                        .lineLimit(1)
                    if transaction.isReconciled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.accent(for: scheme))
                    }
                }
                HStack(spacing: 4) {
                    if let cat = transaction.category {
                        Text(cat.name)
                    }
                    if showAccount, let acc = transaction.account {
                        Text("· \(acc.name)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            Text(CurrencyFormatter.shared.format(transaction.amount, currency: transaction.account?.currency ?? "USD"))
                .font(.body.monospacedDigit())
                .foregroundStyle(transaction.amount < 0 ? .red : .green)
        }
        .padding(.vertical, 2)
    }
}
