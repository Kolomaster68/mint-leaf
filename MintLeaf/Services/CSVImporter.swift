import Foundation
import SwiftData
import UniformTypeIdentifiers

struct CSVColumn: Identifiable {
    let id = UUID()
    let index: Int
    let header: String
    var mapping: CSVFieldMapping = .ignore
}

enum CSVFieldMapping: String, CaseIterable, Identifiable {
    case date = "Date"
    case amount = "Amount"
    case title = "Title/Payee"
    case notes = "Notes/Memo"
    case category = "Category"
    case debit = "Debit Amount"
    case credit = "Credit Amount"
    case ignore = "Ignore"

    var id: String { rawValue }
}

struct CSVImportResult {
    let imported: Int
    let skipped: Int
    let duplicatesDetected: Int
    let errors: [String]
}

final class CSVImporter {
    static let supportedTypes: [UTType] = [.commaSeparatedText, UTType(filenameExtension: "ofx"), UTType(filenameExtension: "qif")].compactMap { $0 }

    static func parseCSV(from url: URL) throws -> (headers: [String], rows: [[String]]) {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else { throw ImportError.emptyFile }

        let headers = parseCSVLine(lines[0])
        let rows = lines.dropFirst().map { parseCSVLine($0) }
        return (headers, rows)
    }

    static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }

    static func importTransactions(
        rows: [[String]],
        columns: [CSVColumn],
        account: Account,
        context: ModelContext
    ) -> CSVImportResult {
        var imported = 0
        var skipped = 0
        var duplicatesDetected = 0
        var errors: [String] = []
        let existingTransactions = account.transactions

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd/yyyy"

        let altDateFormatter = DateFormatter()
        altDateFormatter.dateFormat = "yyyy-MM-dd"

        let ukDateFormatter = DateFormatter()
        ukDateFormatter.dateFormat = "dd/MM/yyyy"

        for (index, row) in rows.enumerated() {
            do {
                var date = Date()
                var amount: Decimal = 0
                var title = ""
                var notes = ""
                var debit: Decimal?
                var credit: Decimal?

                for column in columns {
                    guard column.index < row.count else { continue }
                    let value = row[column.index]

                    switch column.mapping {
                    case .date:
                        guard let d = dateFormatter.date(from: value)
                                ?? altDateFormatter.date(from: value)
                                ?? ukDateFormatter.date(from: value) else {
                            throw ImportError.invalidDate(row: index + 2, value: value)
                        }
                        date = d
                    case .amount:
                        let cleaned = value
                            .replacingOccurrences(of: "$", with: "")
                            .replacingOccurrences(of: "£", with: "")
                            .replacingOccurrences(of: "€", with: "")
                            .replacingOccurrences(of: ",", with: "")
                        guard let d = Decimal(string: cleaned) else {
                            throw ImportError.invalidAmount(row: index + 2, value: value)
                        }
                        amount = d
                    case .debit:
                        let cleaned = value
                            .replacingOccurrences(of: "$", with: "")
                            .replacingOccurrences(of: "£", with: "")
                            .replacingOccurrences(of: "€", with: "")
                            .replacingOccurrences(of: ",", with: "")
                        if !cleaned.isEmpty { debit = Decimal(string: cleaned) }
                    case .credit:
                        let cleaned = value
                            .replacingOccurrences(of: "$", with: "")
                            .replacingOccurrences(of: "£", with: "")
                            .replacingOccurrences(of: "€", with: "")
                            .replacingOccurrences(of: ",", with: "")
                        if !cleaned.isEmpty { credit = Decimal(string: cleaned) }
                    case .title:
                        title = value
                    case .notes:
                        notes = value
                    case .category, .ignore:
                        break
                    }
                }

                if let d = debit, d != 0 { amount = -abs(d) }
                if let c = credit, c != 0 { amount = abs(c) }

                guard !title.isEmpty else {
                    skipped += 1
                    continue
                }

                let candidate = Transaction(amount: amount, title: title, date: date, notes: notes, account: account)
                let dupes = DuplicateDetector.findDuplicates(incoming: [candidate], existing: existingTransactions)
                if !dupes.isEmpty {
                    duplicatesDetected += 1
                    continue
                }

                context.insert(candidate)
                imported += 1
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        return CSVImportResult(imported: imported, skipped: skipped, duplicatesDetected: duplicatesDetected, errors: errors)
    }
}

enum ImportError: LocalizedError {
    case emptyFile
    case invalidDate(row: Int, value: String)
    case invalidAmount(row: Int, value: String)

    var errorDescription: String? {
        switch self {
        case .emptyFile: return "The file is empty."
        case .invalidDate(let row, let value): return "Invalid date '\(value)' at row \(row)."
        case .invalidAmount(let row, let value): return "Invalid amount '\(value)' at row \(row)."
        }
    }
}
