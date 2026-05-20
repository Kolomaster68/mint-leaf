import Foundation
import PDFKit

struct ParsedStatement {
    let transactions: [ParsedTransaction]
    let bankName: String?
    let rawText: String
    let pageCount: Int
}

struct ParsedTransaction {
    let date: Date?
    let title: String
    let amount: Decimal?
    let balance: Decimal?
    let rawLine: String
}

final class PDFStatementParser {

    // MARK: - Public

    static func parse(url: URL) throws -> ParsedStatement {
        guard let document = PDFDocument(url: url) else {
            throw ParserError.cannotOpenFile
        }

        var fullText = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let text = page.string {
                fullText += text + "\n"
            }
        }

        guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParserError.noTextContent
        }

        // Strategy A: position-aware extraction (reconstructs table columns)
        var transactions = parseWithPositions(document: document)

        // Strategy B: concatenated-date splitting (HSBC-style where all txns run together)
        if transactions.count < 2 {
            transactions = parseConcatenatedDates(fullText)
        }

        // Strategy C: line-by-line fallbacks
        if transactions.count < 2 {
            let lines = fullText.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            transactions = parseLineByLine(lines)
        }

        let bankName = detectBank(from: fullText)

        return ParsedStatement(
            transactions: transactions,
            bankName: bankName,
            rawText: fullText,
            pageCount: document.pageCount
        )
    }

    // MARK: - Strategy A: Position-aware table reconstruction

    private struct WordBox {
        let text: String
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let pageIndex: Int
    }

    private static func parseWithPositions(document: PDFDocument) -> [ParsedTransaction] {
        var allWords: [WordBox] = []

        for pageIdx in 0..<document.pageCount {
            guard let page = document.page(at: pageIdx) else { continue }
            let pageHeight = page.bounds(for: .mediaBox).height

            guard let pageText = page.string else { continue }

            for word in splitIntoWords(pageText) {
                guard let wordRange = pageText.range(of: word.text, range: pageText.index(pageText.startIndex, offsetBy: max(0, word.offset))..<pageText.endIndex) else { continue }

                let nsRange = NSRange(wordRange, in: pageText)
                if let sel = page.selection(for: nsRange) {
                    let bounds = sel.bounds(for: page)
                    // PDF coordinates: origin at bottom-left, flip Y
                    allWords.append(WordBox(
                        text: word.text,
                        x: bounds.origin.x,
                        y: pageHeight - bounds.origin.y - bounds.height + CGFloat(pageIdx) * pageHeight * 2,
                        width: bounds.width,
                        height: bounds.height,
                        pageIndex: pageIdx
                    ))
                }
            }
        }

        guard !allWords.isEmpty else { return [] }

        // Cluster words into rows by Y position (words within ~4pt are same row)
        let rows = clusterIntoRows(allWords, tolerance: 4.0)

        // For each row, sort by X to get left-to-right order
        let sortedRows = rows.map { row in
            row.sorted { $0.x < $1.x }
        }.sorted { $0.first!.y < $1.first!.y }

        // Identify which rows are transaction rows:
        // A transaction row has a date-like pattern and a number-like pattern
        var transactions: [ParsedTransaction] = []

        for row in sortedRows {
            let rowText = row.map(\.text).joined(separator: " ")
            guard let _ = findDate(in: rowText) else { continue }
            let amounts = findAmounts(in: rowText)
            guard !amounts.isEmpty else { continue }

            // Determine columns: leftmost words = date, rightmost numbers = amounts, middle = description
            let dateWords = takeWhileDateLike(row)
            let amountWords = takeTrailingAmounts(row)
            let middleStart = dateWords.count
            let middleEnd = row.count - amountWords.count
            let descWords = middleStart < middleEnd ? row[middleStart..<middleEnd] : []

            let dateStr = dateWords.map(\.text).joined(separator: " ")
            let desc = cleanTitle(descWords.map(\.text).joined(separator: " "))
            let amountStr = amountWords.map(\.text).joined(separator: "")

            guard desc.count >= 2 else { continue }

            transactions.append(ParsedTransaction(
                date: parseDate(dateStr),
                title: desc,
                amount: parseAmountStr(amountStr),
                balance: nil,
                rawLine: rowText
            ))
        }

        return transactions
    }

    private struct WordOffset {
        let text: String
        let offset: Int
    }

    private static func splitIntoWords(_ text: String) -> [WordOffset] {
        var results: [WordOffset] = []
        var i = text.startIndex
        while i < text.endIndex {
            // Skip whitespace
            while i < text.endIndex && text[i].isWhitespace || text[i].isNewline {
                i = text.index(after: i)
            }
            guard i < text.endIndex else { break }
            let start = i
            while i < text.endIndex && !text[i].isWhitespace && !text[i].isNewline {
                i = text.index(after: i)
            }
            let word = String(text[start..<i])
            let offset = text.distance(from: text.startIndex, to: start)
            results.append(WordOffset(text: word, offset: offset))
        }
        return results
    }

    private static func clusterIntoRows(_ words: [WordBox], tolerance: CGFloat) -> [[WordBox]] {
        guard !words.isEmpty else { return [] }
        let sorted = words.sorted { $0.y < $1.y }
        var rows: [[WordBox]] = [[sorted[0]]]

        for word in sorted.dropFirst() {
            if abs(word.y - rows.last!.last!.y) <= tolerance {
                rows[rows.count - 1].append(word)
            } else {
                rows.append([word])
            }
        }
        return rows
    }

    private static func takeWhileDateLike(_ row: [WordBox]) -> [WordBox] {
        // Take leading words that look like date components: digits, month names
        let months = Set(["jan","feb","mar","apr","may","jun","jul","aug","sep","oct","nov","dec",
                          "january","february","march","april","june","july","august","september","october","november","december"])
        var result: [WordBox] = []
        for word in row {
            let lower = word.text.lowercased()
            let isDigits = lower.allSatisfy { $0.isNumber || $0 == "/" || $0 == "-" || $0 == "." }
            let isMonth = months.contains(lower)
            if isDigits || isMonth {
                result.append(word)
            } else {
                break
            }
            // Stop after we've consumed enough for a date (typically 3-5 tokens max)
            if result.count >= 6 { break }
        }
        return result
    }

    private static func takeTrailingAmounts(_ row: [WordBox]) -> [WordBox] {
        var result: [WordBox] = []
        for word in row.reversed() {
            let cleaned = word.text
                .replacingOccurrences(of: "£", with: "")
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: "€", with: "")
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "-", with: "")
                .uppercased()
                .replacingOccurrences(of: "CR", with: "")
                .replacingOccurrences(of: "DR", with: "")
                .trimmingCharacters(in: .whitespaces)
            if Decimal(string: cleaned) != nil || word.text == "CR" || word.text == "DR" {
                result.insert(word, at: 0)
            } else {
                break
            }
        }
        return result
    }

    // MARK: - Strategy B: Concatenated dates (HSBC-style)

    private static func parseConcatenatedDates(_ text: String) -> [ParsedTransaction] {
        let shortDatePattern = #"\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{2,4}"#
        let numericDatePattern = #"\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4}"#

        // Try text-month dates first, then numeric
        for datePattern in [shortDatePattern, numericDatePattern] {
            let result = extractConcatenated(text, datePattern: datePattern)
            if result.count >= 2 { return result }
        }
        return []
    }

    private static func extractConcatenated(_ text: String, datePattern: String) -> [ParsedTransaction] {
        guard let dateRegex = try? NSRegularExpression(pattern: datePattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let dateMatches = dateRegex.matches(in: text, range: range)
        guard dateMatches.count >= 4 else { return [] }

        struct DatePos {
            let text: String
            let location: Int
            let length: Int
        }

        var datePosns: [DatePos] = []
        for match in dateMatches {
            if let swiftRange = Range(match.range, in: text) {
                datePosns.append(DatePos(text: String(text[swiftRange]), location: match.range.location, length: match.range.length))
            }
        }

        // Try pairing consecutive dates (received + transaction date pattern)
        var pairs: [(receivedLoc: Int, transDate: String, descStart: Int)] = []
        var i = 0
        while i < datePosns.count - 1 {
            let first = datePosns[i]
            let second = datePosns[i + 1]
            let gap = second.location - (first.location + first.length)
            if gap <= 3 {
                pairs.append((receivedLoc: first.location, transDate: second.text, descStart: second.location + second.length))
                i += 2
            } else {
                i += 1
            }
        }

        // If no pairs found, treat each date as a single entry
        if pairs.isEmpty {
            for dp in datePosns {
                pairs.append((receivedLoc: dp.location, transDate: dp.text, descStart: dp.location + dp.length))
            }
        }

        guard !pairs.isEmpty else { return [] }

        // Extract description between entries
        var entries: [(date: String, description: String)] = []
        for (idx, pair) in pairs.enumerated() {
            let descStart = text.index(text.startIndex, offsetBy: pair.descStart, limitedBy: text.endIndex) ?? text.endIndex
            let descEnd: String.Index
            if idx + 1 < pairs.count {
                descEnd = text.index(text.startIndex, offsetBy: pairs[idx + 1].receivedLoc, limitedBy: text.endIndex) ?? text.endIndex
            } else {
                descEnd = text.endIndex
            }
            let desc = cleanTitle(String(text[descStart..<descEnd]))
            if !desc.isEmpty { entries.append((date: pair.transDate, description: desc)) }
        }

        // Find amounts: look for a block of consecutive decimal numbers
        let amountPattern = #"(\d{1,3}(?:,\d{3})*\.\d{2})\s*(CR)?"#
        guard let amountRegex = try? NSRegularExpression(pattern: amountPattern, options: .caseInsensitive) else { return [] }

        // Collect all amounts in the text, then take the consecutive block that matches our entry count
        var allAmounts: [(value: Decimal, isCredit: Bool, location: Int)] = []
        let amountMatches = amountRegex.matches(in: text, range: range)
        for match in amountMatches {
            if let numRange = Range(match.range(at: 1), in: text) {
                let numStr = String(text[numRange]).replacingOccurrences(of: ",", with: "")
                let isCredit = match.range(at: 2).location != NSNotFound
                if let val = Decimal(string: numStr) {
                    allAmounts.append((value: val, isCredit: isCredit, location: match.range.location))
                }
            }
        }

        // Find the best consecutive run of amounts that matches entry count
        var amounts: [(Decimal, Bool)] = []
        let target = entries.count
        if allAmounts.count >= target {
            // Try to find a run of `target` amounts where they're near each other
            for startIdx in 0...(allAmounts.count - target) {
                let slice = Array(allAmounts[startIdx..<(startIdx + target)])
                // Check they're reasonably consecutive (within ~200 chars of each other)
                var consecutive = true
                for j in 1..<slice.count {
                    if slice[j].location - slice[j-1].location > 200 {
                        consecutive = false
                        break
                    }
                }
                if consecutive {
                    amounts = slice.map { ($0.value, $0.isCredit) }
                    break
                }
            }
        }

        // If no good run found, just take the last N amounts
        if amounts.isEmpty && allAmounts.count >= target {
            amounts = allAmounts.suffix(target).map { ($0.value, $0.isCredit) }
        }

        // Pair entries with amounts
        var transactions: [ParsedTransaction] = []
        let count = min(entries.count, amounts.count)
        for idx in 0..<count {
            let entry = entries[idx]
            let (amount, isCredit) = amounts[idx]
            let signedAmount = isCredit ? amount : -amount

            transactions.append(ParsedTransaction(
                date: parseDate(entry.date),
                title: entry.description,
                amount: signedAmount,
                balance: nil,
                rawLine: "\(entry.date) \(entry.description)"
            ))
        }

        return transactions
    }

    // MARK: - Strategy C: Line-by-line

    private static func parseLineByLine(_ lines: [String]) -> [ParsedTransaction] {
        var transactions: [ParsedTransaction] = []

        // Pass 1: lines with both date and amount
        for line in lines {
            guard let dateMatch = findDate(in: line) else { continue }
            let amounts = findAmounts(in: line)
            guard !amounts.isEmpty else { continue }

            var title = line
            if let range = Range(dateMatch.range, in: line) {
                title = String(line[range.upperBound...])
            }
            for amount in amounts.reversed() {
                if let r = title.range(of: amount.text) { title.removeSubrange(r) }
            }
            title = cleanTitle(title)
            guard title.count >= 2 else { continue }

            transactions.append(ParsedTransaction(
                date: parseDate(dateMatch.text),
                title: title,
                amount: parseAmountStr(amounts.last!.text),
                balance: amounts.count > 1 ? parseAmountStr(amounts.first!.text) : nil,
                rawLine: line
            ))
        }

        if transactions.count >= 2 { return transactions }

        // Pass 2: multi-line grouping (date on one line, amount on next)
        transactions = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if let dateMatch = findDate(in: line) {
                var desc = line
                if let range = Range(dateMatch.range, in: line) { desc = String(line[range.upperBound...]) }

                var amounts: [TextMatch] = findAmounts(in: desc)
                var lookahead = 1
                while amounts.isEmpty && (i + lookahead) < lines.count && lookahead <= 3 {
                    let next = lines[i + lookahead]
                    if findDate(in: next) != nil { break }
                    amounts = findAmounts(in: next)
                    if amounts.isEmpty { desc += " " + next }
                    lookahead += 1
                }

                if !amounts.isEmpty {
                    for a in amounts { desc = desc.replacingOccurrences(of: a.text, with: "") }
                    let title = cleanTitle(desc)
                    if title.count >= 2 {
                        transactions.append(ParsedTransaction(
                            date: parseDate(dateMatch.text),
                            title: title,
                            amount: parseAmountStr(amounts.last!.text),
                            balance: nil,
                            rawLine: line
                        ))
                    }
                    i += lookahead
                    continue
                }
            }
            i += 1
        }

        if transactions.count >= 2 { return transactions }

        // Pass 3: loose — any line with an amount, skip boilerplate
        transactions = []
        let skip = ["balance","total","summary","statement","page","account","sort code",
                     "opening","closing","credit limit","minimum","interest","apr","payment due",
                     "nominated","allocated","overdraft","available","brought forward"]

        for line in lines {
            let lower = line.lowercased()
            if skip.contains(where: { lower.contains($0) }) { continue }
            let amounts = findAmounts(in: line)
            guard !amounts.isEmpty else { continue }

            var title = line
            for a in amounts { title = title.replacingOccurrences(of: a.text, with: "") }
            let dateMatch = findDate(in: line)
            if let dm = dateMatch { title = title.replacingOccurrences(of: dm.text, with: "") }
            title = cleanTitle(title)
            guard title.count >= 3 else { continue }

            transactions.append(ParsedTransaction(
                date: dateMatch.flatMap { parseDate($0.text) },
                title: title,
                amount: parseAmountStr(amounts.last!.text),
                balance: nil,
                rawLine: line
            ))
        }

        return transactions
    }

    // MARK: - Text matching helpers

    struct TextMatch {
        let text: String
        let range: NSRange
    }

    private static func findDate(in text: String) -> TextMatch? {
        let patterns = [
            #"\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}"#,
            #"\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{2,4}"#,
            #"(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2},?\s+\d{2,4}"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let swiftRange = Range(match.range, in: text) {
                return TextMatch(text: String(text[swiftRange]), range: match.range)
            }
        }
        return nil
    }

    private static func findAmounts(in text: String) -> [TextMatch] {
        let patterns = [
            #"[\-]?[£$€]?\s*\d{1,3}(?:,\d{3})*\.\d{2}\s*(?:DR|CR|db|cr)?"#,
            #"[£$€]\s*\d+(?:,\d{3})*\s*(?:DR|CR|db|cr)?"#,
        ]
        var matches: [TextMatch] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                if let swiftRange = Range(match.range, in: text) {
                    let t = String(text[swiftRange]).trimmingCharacters(in: .whitespaces)
                    if t.contains(".") || t.contains("£") || t.contains("$") || t.contains("€") {
                        matches.append(TextMatch(text: t, range: match.range))
                    }
                }
            }
            if !matches.isEmpty { break }
        }
        return matches
    }

    // MARK: - Parsing helpers

    static func parseAmountStr(_ text: String) -> Decimal? {
        var cleaned = text
            .replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")

        let isDebit = cleaned.range(of: "DR", options: .caseInsensitive) != nil ||
                      cleaned.range(of: "db", options: .caseInsensitive) != nil
        let isCredit = cleaned.range(of: "CR", options: .caseInsensitive) != nil

        cleaned = cleaned
            .replacingOccurrences(of: "DR", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "CR", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "db", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)

        guard var amount = Decimal(string: cleaned) else { return nil }
        if isDebit && amount > 0 { amount = -amount }
        if isCredit && amount < 0 { amount = abs(amount) }
        return amount
    }

    static func parseDate(_ s: String) -> Date? {
        let formats = [
            "dd/MM/yyyy", "MM/dd/yyyy", "yyyy-MM-dd", "dd-MM-yyyy", "dd.MM.yyyy",
            "dd/MM/yy", "MM/dd/yy", "dd-MM-yy",
            "dd MMM yyyy", "dd MMMM yyyy", "dd MMM yy",
            "MMM dd, yyyy", "MMMM dd, yyyy", "MMM dd yyyy",
        ]
        for format in formats {
            let f = DateFormatter()
            f.dateFormat = format
            f.locale = Locale(identifier: "en_GB")
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone.current
            f.calendar = cal
            f.twoDigitStartDate = {
                var c = DateComponents()
                c.year = 2000
                return Calendar.current.date(from: c) ?? Date()
            }()
            if let d = f.date(from: s) { return d }
        }
        // Retry with en_US locale for US-format dates
        for format in ["MM/dd/yyyy", "MM/dd/yy", "MMM dd, yyyy"] {
            let f = DateFormatter()
            f.dateFormat = format
            f.locale = Locale(identifier: "en_US_POSIX")
            f.twoDigitStartDate = {
                var c = DateComponents()
                c.year = 2000
                return Calendar.current.date(from: c) ?? Date()
            }()
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    static func cleanTitle(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "- .,;:"))

        // Remove contactless markers
        while cleaned.hasPrefix(")))") {
            cleaned = String(cleaned.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        }
        // Remove in-app purchase markers
        if cleaned.hasPrefix("IAP ") {
            cleaned = String(cleaned.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        }

        return cleaned
    }

    private static func detectBank(from text: String) -> String? {
        let banks = [
            "Barclays", "HSBC", "Lloyds", "NatWest", "Santander",
            "Monzo", "Starling", "Revolut", "Chase", "Nationwide",
            "Halifax", "TSB", "Metro Bank", "Virgin Money", "First Direct",
            "Bank of America", "Wells Fargo", "Citibank", "Capital One",
            "JP Morgan", "US Bank", "PNC", "TD Bank",
            "Commonwealth Bank", "ANZ", "Westpac", "NAB",
        ]
        let upper = text.uppercased()
        return banks.first { upper.contains($0.uppercased()) }
    }
}

enum ParserError: LocalizedError {
    case cannotOpenFile
    case noTextContent

    var errorDescription: String? {
        switch self {
        case .cannotOpenFile: return "Could not open the PDF file."
        case .noTextContent: return "No readable text found in the PDF. It may be a scanned image — try a digitally-generated statement."
        }
    }
}
