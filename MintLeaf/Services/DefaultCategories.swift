import Foundation
import SwiftData

struct DefaultCategories {
    static func seed(context: ModelContext) {
        let expenses: [(String, String, String)] = [
            ("Food & Dining", "fork.knife", "#FF9800"),
            ("Groceries", "cart", "#8BC34A"),
            ("Transportation", "car", "#607D8B"),
            ("Gas & Fuel", "fuelpump", "#795548"),
            ("Housing", "house", "#9C27B0"),
            ("Utilities", "bolt", "#FFC107"),
            ("Insurance", "shield", "#3F51B5"),
            ("Healthcare", "heart", "#F44336"),
            ("Entertainment", "tv", "#E91E63"),
            ("Shopping", "bag", "#00BCD4"),
            ("Clothing", "tshirt", "#673AB7"),
            ("Education", "book", "#2196F3"),
            ("Personal Care", "sparkles", "#FF5722"),
            ("Subscriptions", "arrow.triangle.2.circlepath", "#009688"),
            ("Travel", "airplane", "#03A9F4"),
            ("Gifts & Donations", "gift", "#EC407A"),
            ("Fees & Charges", "exclamationmark.triangle", "#757575"),
            ("Taxes", "doc.text", "#455A64"),
            ("Other", "ellipsis.circle", "#9E9E9E"),
        ]

        let incomes: [(String, String, String)] = [
            ("Salary", "briefcase", "#4CAF50"),
            ("Freelance", "laptopcomputer", "#66BB6A"),
            ("Interest", "percent", "#43A047"),
            ("Dividends", "chart.bar", "#388E3C"),
            ("Rental Income", "building.2", "#2E7D32"),
            ("Refunds", "arrow.uturn.backward", "#81C784"),
            ("Other Income", "plus.circle", "#A5D6A7"),
        ]

        for (index, (name, icon, color)) in expenses.enumerated() {
            let cat = Category(name: name, icon: icon, colorHex: color, isIncome: false, sortOrder: index)
            context.insert(cat)
        }

        for (index, (name, icon, color)) in incomes.enumerated() {
            let cat = Category(name: name, icon: icon, colorHex: color, isIncome: true, sortOrder: index)
            context.insert(cat)
        }
    }
}
