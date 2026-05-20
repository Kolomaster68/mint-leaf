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

    static func similarity(_ a: String, _ b: String) -> Double {
        let setA = Set(a.lowercased().components(separatedBy: .whitespaces))
        let setB = Set(b.lowercased().components(separatedBy: .whitespaces))
        guard !setA.isEmpty || !setB.isEmpty else { return 1.0 }
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        return Double(intersection) / Double(union)
    }
}
