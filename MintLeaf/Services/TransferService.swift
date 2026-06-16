import Foundation
import SwiftData

/// Keeps the two sides of a transfer (a transaction and its mirror in the destination
/// account) consistent when transactions are created, edited, or deleted.
enum TransferService {

    /// Finds the mirror transaction for a transfer, if one exists.
    /// Prefers the shared `transferPairID`; falls back to a heuristic for legacy
    /// transfers created before pairing ids existed.
    static func findMirror(of txn: Transaction) -> Transaction? {
        guard let dest = txn.transferDestination else { return nil }

        if let pairID = txn.transferPairID {
            if let match = dest.transactions.first(where: { $0.transferPairID == pairID && $0.id != txn.id }) {
                return match
            }
        }

        // Legacy fallback: opposite amount, same day, pointing back at this account.
        return dest.transactions.first { candidate in
            candidate.id != txn.id &&
            candidate.transferDestination?.id == txn.account?.id &&
            candidate.amount == -txn.amount &&
            Calendar.current.isDate(candidate.date, inSameDayAs: txn.date)
        }
    }

    /// Deletes a transaction and, if it's part of a transfer, its mirror — reversing
    /// the balance impact on both accounts.
    @MainActor
    static func delete(_ txn: Transaction, context: ModelContext) {
        if let mirror = findMirror(of: txn) {
            mirror.account?.adjustBalance(by: -mirror.amount)
            context.delete(mirror)
        }
        txn.account?.adjustBalance(by: -txn.amount)
        context.delete(txn)
    }
}
