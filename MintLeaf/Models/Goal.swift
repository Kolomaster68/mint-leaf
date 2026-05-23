import Foundation
import SwiftData

@Model
final class Goal {
    var id: UUID
    var name: String
    var icon: String
    var colorHex: String
    var targetAmount: Decimal
    var savedAmount: Decimal
    var targetDate: Date?
    var notes: String
    var isWishlistItem: Bool
    var linkURL: String?
    var imageURL: String?
    var isPurchased: Bool
    var createdDate: Date
    var sortOrder: Int

    @Relationship
    var account: Account?   // Optional: track savings in a specific account

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(1.0, Double(truncating: (savedAmount / targetAmount) as NSDecimalNumber))
    }

    var remaining: Decimal {
        max(0, targetAmount - savedAmount)
    }

    var isComplete: Bool {
        savedAmount >= targetAmount
    }

    var daysRemaining: Int? {
        guard let target = targetDate else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: target).day ?? 0)
    }

    /// Estimated daily savings needed to hit the target date
    var dailySavingsNeeded: Decimal? {
        guard let days = daysRemaining, days > 0 else { return nil }
        return remaining / Decimal(days)
    }

    init(
        name: String,
        icon: String = "target",
        colorHex: String = "D9B138",
        targetAmount: Decimal,
        savedAmount: Decimal = 0,
        targetDate: Date? = nil,
        notes: String = "",
        isWishlistItem: Bool = false,
        linkURL: String? = nil,
        imageURL: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.targetAmount = targetAmount
        self.savedAmount = savedAmount
        self.targetDate = targetDate
        self.notes = notes
        self.isWishlistItem = isWishlistItem
        self.linkURL = linkURL
        self.imageURL = imageURL
        self.isPurchased = false
        self.createdDate = Date()
        self.sortOrder = sortOrder
    }
}
