import Foundation
import SwiftData

struct DuplicateMatch: Identifiable {
    let id = UUID()
    let incoming: Transaction
    let existing: Transaction
    let confidence: Double
}

final class DuplicateDetector {
    static func findDuplicates(
        incoming: [Transaction],
        existing: [Transaction],
        toleranceDays: Int = 1
    ) -> [DuplicateMatch] {
        var matches: [DuplicateMatch] = []
        let calendar = Calendar.current

        for new in incoming {
            for old in existing {
                let daysDiff = abs(calendar.dateComponents([.day], from: old.date, to: new.date).day ?? 999)
                guard daysDiff <= toleranceDays else { continue }

                var confidence = 0.0

                if new.amount == old.amount { confidence += 0.5 }
                if daysDiff == 0 { confidence += 0.3 }
                else if daysDiff == 1 { confidence += 0.15 }

                let titleSimilarity = Self.similarity(new.title, old.title)
                confidence += titleSimilarity * 0.2

                if confidence >= 0.7 {
                    matches.append(DuplicateMatch(incoming: new, existing: old, confidence: confidence))
                }
            }
        }
        return matches
    }

    /// One-to-one duplicate check for importers. A matched existing transaction is
    /// removed from `pool`, so two genuine identical charges on one day (two £6.20 tube
    /// fares) can't both be swallowed by a single existing entry.
    ///
    /// Also matches an auto-posted scheduled charge of the same amount within five days:
    /// the bank's line and the app's placeholder are the same money (a "Rent" auto-post
    /// on the 31st and the real payment on the 3rd). The placeholder takes the bank's date.
    static func consumeDuplicate(of candidate: Transaction, in pool: inout [Transaction]) -> Bool {
        if let best = findDuplicates(incoming: [candidate], existing: pool).max(by: { $0.confidence < $1.confidence }) {
            confirm(best.existing, with: candidate)
            pool.removeAll { $0 === best.existing }
            return true
        }
        let calendar = Calendar.current
        if let placeholder = pool.first(where: { old in
            old.scheduledSource != nil && old.amount == candidate.amount &&
            abs(calendar.dateComponents([.day], from: old.date, to: candidate.date).day ?? 999) <= 5
        }) {
            placeholder.date = candidate.date
            confirm(placeholder, with: candidate)
            pool.removeAll { $0 === placeholder }
            return true
        }
        return false
    }

    /// The bank has the charge, so an auto-posted placeholder is real: drop its
    /// "Auto-charged" note (cancelled-subscription detection keys off it).
    private static func confirm(_ existing: Transaction, with bankLine: Transaction) {
        if ScheduledTransactionProcessor.isUnconfirmed(existing) { existing.notes = bankLine.notes }
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        let setA = Set(a.lowercased().components(separatedBy: .whitespaces))
        let setB = Set(b.lowercased().components(separatedBy: .whitespaces))
        guard !setA.isEmpty || !setB.isEmpty else { return 1.0 }
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        return Double(intersection) / Double(union)
    }
}
