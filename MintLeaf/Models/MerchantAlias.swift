import Foundation
import SwiftData

@Model
final class MerchantAlias {
    var id: UUID
    var rawPattern: String
    var cleanName: String
    var matchType: RuleMatchType
    var isEnabled: Bool

    init(rawPattern: String, cleanName: String, matchType: RuleMatchType = .contains) {
        self.id = UUID()
        self.rawPattern = rawPattern
        self.cleanName = cleanName
        self.matchType = matchType
        self.isEnabled = true
    }
}
