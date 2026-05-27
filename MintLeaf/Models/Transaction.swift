import Foundation
import SwiftData

@Model
final class Transaction {
    var id: UUID
    var amount: Decimal
    var title: String
    var notes: String
    var date: Date
    var isReconciled: Bool
    var checkNumber: String?
    var location: String?

    var account: Account?

    @Relationship
    var category: Category?

    @Relationship
    var transferDestination: Account?

    @Relationship(inverse: \ScheduledTransaction.generatedTransactions)
    var scheduledSource: ScheduledTransaction?

    @Relationship(inverse: \Tag.transactions)
    var tags: [Tag]

    var isExpense: Bool { amount < 0 && !isTransfer }
    var isIncome: Bool { amount > 0 && !isTransfer }
    var isTransfer: Bool { transferDestination != nil }

    var absoluteAmount: Decimal { abs(amount) }

    init(
        amount: Decimal,
        title: String,
        date: Date = Date(),
        notes: String = "",
        category: Category? = nil,
        account: Account? = nil
    ) {
        self.id = UUID()
        self.amount = amount
        self.title = title
        self.date = date
        self.notes = notes
        self.isReconciled = false
        self.category = category
        self.account = account
        self.tags = []
    }
}
