import Foundation
import SwiftData

@Model
final class Account {
    var id: UUID
    var name: String
    var type: AccountType
    var currency: String
    var initialBalance: Decimal
    var icon: String
    var colorHex: String
    var sortOrder: Int
    var isArchived: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    var transactions: [Transaction]

    var currentBalance: Decimal {
        initialBalance + transactions.reduce(Decimal.zero) { $0 + $1.amount }
    }

    init(
        name: String,
        type: AccountType = .checking,
        currency: String = "USD",
        initialBalance: Decimal = 0,
        icon: String = "banknote",
        colorHex: String = "#4CAF50",
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.currency = currency
        self.initialBalance = initialBalance
        self.icon = icon
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.isArchived = false
        self.createdAt = Date()
        self.transactions = []
    }
}

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case checking = "Checking"
    case savings = "Savings"
    case creditCard = "Credit Card"
    case cash = "Cash"
    case investment = "Investment"
    case loan = "Loan"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .checking: return "building.columns"
        case .savings: return "banknote"
        case .creditCard: return "creditcard"
        case .cash: return "dollarsign.circle"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .loan: return "arrow.left.arrow.right"
        case .other: return "folder"
        }
    }
}
