import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID
    var name: String
    var icon: String
    var colorHex: String
    var isIncome: Bool
    var sortOrder: Int
    var parentCategory: Category?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction]

    @Relationship(deleteRule: .cascade, inverse: \Category.parentCategory)
    var subcategories: [Category]

    @Relationship(deleteRule: .nullify, inverse: \BudgetItem.category)
    var budgetItems: [BudgetItem]

    init(
        name: String,
        icon: String = "tag",
        colorHex: String = "#2196F3",
        isIncome: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.isIncome = isIncome
        self.sortOrder = sortOrder
        self.transactions = []
        self.subcategories = []
        self.budgetItems = []
    }
}
