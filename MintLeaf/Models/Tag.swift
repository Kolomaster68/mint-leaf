import Foundation
import SwiftData

@Model
final class Tag {
    var id: UUID
    var name: String
    var colorHex: String
    var sortOrder: Int

    @Relationship
    var transactions: [Transaction]

    init(name: String, colorHex: String = "D9B138", sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.transactions = []
    }
}
