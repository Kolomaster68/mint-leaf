import Foundation

// MARK: - Parsed Transaction (shared between OFX and QIF)

struct ParsedBankTransaction: Identifiable {
    let id = UUID()
    let date: Date
    let amount: Decimal
    let title: String
    let memo: String
    let fitID: String? // OFX unique transaction ID
}

struct BankFileParseResult {
    let transactions: [ParsedBankTransaction]
    let accountName: String?
    let accountType: String?
    let currency: String?
}

// MARK: - OFX Parser

enum OFXParser {
    /// Parse an OFX/QFX file and return structured transactions
    static func parse(from url: URL) throws -> BankFileParseResult {
        let content = try String(contentsOf: url, encoding: .utf8)
        // Some OFX files use Latin1 encoding
        let text: String
        if content.contains("<OFX>") || content.contains("<ofx>") {
            text = content
        } else if let latin = try? String(contentsOf: url, encoding: .isoLatin1),
                  latin.contains("<OFX>") || latin.contains("<ofx>") {
            text = latin
        } else {
            throw BankFileError.invalidFormat("Not a valid OFX file")
        }

        var transactions: [ParsedBankTransaction] = []
        var accountName: String?
        var currency: String?

        // Extract currency
        if let curr = extractTag("CURDEF", from: text) {
            currency = curr
        }

        // Extract account ID as name
        if let acctId = extractTag("ACCTID", from: text) {
            accountName = "Account ···\(String(acctId.suffix(4)))"
        }

        // Find all STMTTRN blocks
        let pattern = "<STMTTRN>(.*?)</STMTTRN>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        let range = NSRange(text.startIndex..., in: text)

        regex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let matchRange = match?.range(at: 1),
                  let swiftRange = Range(matchRange, in: text) else { return }

            let block = String(text[swiftRange])

            guard let dateStr = extractTag("DTPOSTED", from: block),
                  let date = parseOFXDate(dateStr),
                  let amountStr = extractTag("TRNAMT", from: block),
                  let amount = Decimal(string: amountStr) else { return }

            let name = extractTag("NAME", from: block) ?? extractTag("MEMO", from: block) ?? "Unknown"
            let memo = extractTag("MEMO", from: block) ?? ""
            let fitID = extractTag("FITID", from: block)

            transactions.append(ParsedBankTransaction(
                date: date,
                amount: amount,
                title: name.trimmingCharacters(in: .whitespacesAndNewlines),
                memo: (name != memo) ? memo.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                fitID: fitID
            ))
        }

        // Fallback: if regex didn't work (SGML-style OFX without closing tags)
        if transactions.isEmpty {
            transactions = parseSGMLStyle(text)
        }

        guard !transactions.isEmpty else {
            throw BankFileError.noTransactions
        }

        return BankFileParseResult(
            transactions: transactions.sorted { $0.date < $1.date },
            accountName: accountName,
            accountType: nil,
            currency: currency
        )
    }

    /// Parse SGML-style OFX (no closing tags, which is common)
    private static func parseSGMLStyle(_ text: String) -> [ParsedBankTransaction] {
        var transactions: [ParsedBankTransaction] = []
        let lines = text.components(separatedBy: .newlines)

        var inTransaction = false
        var dateStr: String?
        var amountStr: String?
        var name: String?
        var memo: String?
        var fitID: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("<STMTTRN>") {
                inTransaction = true
                dateStr = nil; amountStr = nil; name = nil; memo = nil; fitID = nil
            } else if trimmed.hasPrefix("</STMTTRN>") || (!trimmed.hasPrefix("<") && inTransaction && dateStr != nil && amountStr != nil && name != nil && trimmed.hasPrefix("<STMTTRN>")) {
                if let ds = dateStr, let date = parseOFXDate(ds),
                   let as_ = amountStr, let amount = Decimal(string: as_) {
                    transactions.append(ParsedBankTransaction(
                        date: date,
                        amount: amount,
                        title: (name ?? "Unknown").trimmingCharacters(in: .whitespacesAndNewlines),
                        memo: (memo ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                        fitID: fitID
                    ))
                }
                if trimmed.hasPrefix("<STMTTRN>") {
                    dateStr = nil; amountStr = nil; name = nil; memo = nil; fitID = nil
                } else {
                    inTransaction = false
                }
            } else if inTransaction {
                if let val = extractSGMLValue("DTPOSTED", from: trimmed) { dateStr = val }
                if let val = extractSGMLValue("TRNAMT", from: trimmed) { amountStr = val }
                if let val = extractSGMLValue("NAME", from: trimmed) { name = val }
                if let val = extractSGMLValue("MEMO", from: trimmed) { memo = val }
                if let val = extractSGMLValue("FITID", from: trimmed) { fitID = val }
            }
        }

        // Handle last transaction if file doesn't end with </STMTTRN>
        if inTransaction, let ds = dateStr, let date = parseOFXDate(ds),
           let as_ = amountStr, let amount = Decimal(string: as_) {
            transactions.append(ParsedBankTransaction(
                date: date,
                amount: amount,
                title: (name ?? "Unknown").trimmingCharacters(in: .whitespacesAndNewlines),
                memo: (memo ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                fitID: fitID
            ))
        }

        return transactions
    }

    private static func extractTag(_ tag: String, from text: String) -> String? {
        // Try XML-style: <TAG>value</TAG>
        let xmlPattern = "<\(tag)>(.*?)</\(tag)>"
        if let regex = try? NSRegularExpression(pattern: xmlPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            return String(text[range])
        }
        // Try SGML-style: <TAG>value\n
        return extractSGMLValue(tag, from: text)
    }

    private static func extractSGMLValue(_ tag: String, from text: String) -> String? {
        let prefix = "<\(tag)>"
        guard let range = text.range(of: prefix, options: .caseInsensitive) else { return nil }
        let after = text[range.upperBound...]
        let value = after.prefix(while: { $0 != "\n" && $0 != "\r" && $0 != "<" })
        let result = String(value).trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? nil : result
    }

    /// Parse OFX date format: YYYYMMDDHHMMSS or YYYYMMDD
    private static func parseOFXDate(_ str: String) -> Date? {
        let clean = str.prefix(8) // Take just YYYYMMDD
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: String(clean))
    }
}

// MARK: - QIF Parser

enum QIFParser {
    static func parse(from url: URL) throws -> BankFileParseResult {
        let content: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            content = utf8
        } else if let latin = try? String(contentsOf: url, encoding: .isoLatin1) {
            content = latin
        } else {
            throw BankFileError.invalidFormat("Cannot read QIF file")
        }

        var transactions: [ParsedBankTransaction] = []
        var accountType: String?

        let lines = content.components(separatedBy: .newlines)

        var date: Date?
        var amount: Decimal?
        var payee: String?
        var memo: String?

        let dateFormatters: [DateFormatter] = {
            let formats = ["MM/dd/yyyy", "dd/MM/yyyy", "MM/dd'yy", "yyyy-MM-dd", "M/d/yyyy", "M/d'yy"]
            return formats.map { fmt in
                let f = DateFormatter()
                f.dateFormat = fmt
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }
        }()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let code = trimmed.prefix(1)
            let value = String(trimmed.dropFirst())

            switch code {
            case "!":
                // Header line — e.g. !Type:Bank
                if value.lowercased().hasPrefix("type:") {
                    accountType = String(value.dropFirst(5))
                }
            case "D":
                // Date — try multiple formats
                let cleaned = value.replacingOccurrences(of: "'", with: "/")
                for formatter in dateFormatters {
                    if let d = formatter.date(from: cleaned) {
                        date = d
                        break
                    }
                }
            case "T", "U":
                // Amount
                let cleaned = value
                    .replacingOccurrences(of: ",", with: "")
                    .replacingOccurrences(of: "$", with: "")
                    .replacingOccurrences(of: "£", with: "")
                    .replacingOccurrences(of: "€", with: "")
                amount = Decimal(string: cleaned)
            case "P":
                payee = value
            case "M":
                memo = value
            case "N":
                // Check number — ignore for now
                break
            case "^":
                // End of transaction
                if let d = date, let a = amount {
                    transactions.append(ParsedBankTransaction(
                        date: d,
                        amount: a,
                        title: (payee ?? memo ?? "Unknown").trimmingCharacters(in: .whitespacesAndNewlines),
                        memo: (memo ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                        fitID: nil
                    ))
                }
                date = nil; amount = nil; payee = nil; memo = nil
            default:
                break
            }
        }

        guard !transactions.isEmpty else {
            throw BankFileError.noTransactions
        }

        return BankFileParseResult(
            transactions: transactions.sorted { $0.date < $1.date },
            accountName: nil,
            accountType: accountType,
            currency: nil
        )
    }
}

// MARK: - Errors

enum BankFileError: LocalizedError {
    case invalidFormat(String)
    case noTransactions

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg): return msg
        case .noTransactions: return "No transactions found in the file."
        }
    }
}
