import Foundation
import UniformTypeIdentifiers

/// Lightweight XLSX parser — no third-party dependencies.
/// An .xlsx file is a ZIP archive of XML files.
final class XLSXImporter {

    // MARK: - Public types

    struct Sheet: Identifiable {
        let id: Int
        let name: String
        let rows: [[String]]
    }

    struct ParseResult {
        let sheets: [Sheet]
    }

    // MARK: - Public API

    static let supportedType: UTType = UTType(filenameExtension: "xlsx") ?? .data

    static func parse(url: URL) throws -> ParseResult {
        // 1. Unzip the XLSX into a temp directory
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        try unzip(url, to: tmp)

        // 2. Parse shared strings (xl/sharedStrings.xml)
        let sharedStrings = parseSharedStrings(at: tmp)

        // 3. Parse workbook to get sheet names (xl/workbook.xml)
        let sheetNames = parseWorkbook(at: tmp)

        // 4. Parse each sheet's data (xl/worksheets/sheet1.xml, sheet2.xml, ...)
        var sheets: [Sheet] = []
        for (index, name) in sheetNames.enumerated() {
            let sheetFile = tmp.appendingPathComponent("xl/worksheets/sheet\(index + 1).xml")
            guard fm.fileExists(atPath: sheetFile.path) else { continue }
            let rows = parseSheet(at: sheetFile, sharedStrings: sharedStrings)
            if !rows.isEmpty {
                sheets.append(Sheet(id: index, name: name, rows: rows))
            }
        }

        guard !sheets.isEmpty else { throw XLSXError.noSheets }
        return ParseResult(sheets: sheets)
    }

    // MARK: - ZIP extraction using /usr/bin/ditto

    private static func unzip(_ source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", source.path, destination.path]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw XLSXError.unzipFailed
        }
    }

    // MARK: - XML parsing

    private static func parseSharedStrings(at root: URL) -> [String] {
        let file = root.appendingPathComponent("xl/sharedStrings.xml")
        guard let data = try? Data(contentsOf: file) else { return [] }
        let parser = SharedStringsParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.strings
    }

    private static func parseWorkbook(at root: URL) -> [String] {
        let file = root.appendingPathComponent("xl/workbook.xml")
        guard let data = try? Data(contentsOf: file) else { return [] }
        let parser = WorkbookParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.sheetNames
    }

    private static func parseSheet(at url: URL, sharedStrings: [String]) -> [[String]] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let parser = SheetParser(sharedStrings: sharedStrings)
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.rows
    }
}

// MARK: - SharedStrings XML Parser

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var currentText = ""
    private var inSI = false
    private var inT = false

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if element == "si" {
            inSI = true
            currentText = ""
        } else if element == "t" && inSI {
            inT = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inT { currentText += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        if element == "t" { inT = false }
        if element == "si" {
            strings.append(currentText)
            inSI = false
        }
    }
}

// MARK: - Workbook XML Parser

private final class WorkbookParser: NSObject, XMLParserDelegate {
    var sheetNames: [String] = []

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if element == "sheet", let name = attributes["name"] {
            sheetNames.append(name)
        }
    }
}

// MARK: - Sheet XML Parser

private final class SheetParser: NSObject, XMLParserDelegate {
    let sharedStrings: [String]
    var rows: [[String]] = []
    private var currentRow: [CellValue] = []
    private var currentCellRef: String?
    private var currentCellType: String?
    private var currentValue = ""
    private var inlineText = ""
    private var inV = false
    private var inT = false  // Inside <t> tag (for inline strings)
    private var inIS = false // Inside <is> tag (inline string container)
    private var inRow = false

    struct CellValue {
        let column: Int
        let value: String
    }

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch element {
        case "row":
            inRow = true
            currentRow = []
        case "c":
            currentCellRef = attributes["r"]
            currentCellType = attributes["t"]
            currentValue = ""
            inlineText = ""
        case "v":
            inV = true
            currentValue = ""
        case "is":
            inIS = true
            inlineText = ""
        case "t":
            if inIS { inT = true }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inV { currentValue += string }
        if inT { inlineText += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        switch element {
        case "v":
            inV = false
        case "t":
            inT = false
        case "is":
            inIS = false
        case "c":
            let value: String
            if currentCellType == "inlineStr" {
                // Inline string: text is inside <is><t>...</t></is>
                value = inlineText
            } else if currentCellType == "s", let idx = Int(currentValue), idx < sharedStrings.count {
                // Shared string reference
                value = sharedStrings[idx]
            } else {
                value = currentValue
            }
            let col = columnIndex(from: currentCellRef ?? "A1")
            currentRow.append(CellValue(column: col, value: value))
        case "row":
            inRow = false
            guard !currentRow.isEmpty else { return }
            let maxCol = currentRow.map(\.column).max() ?? 0
            var row = Array(repeating: "", count: maxCol + 1)
            for cell in currentRow {
                row[cell.column] = cell.value
            }
            rows.append(row)
        default:
            break
        }
    }

    /// Convert Excel column reference (e.g. "A", "B", "AA") to 0-based index
    private func columnIndex(from ref: String) -> Int {
        let letters = ref.prefix(while: { $0.isLetter })
        var index = 0
        for char in letters.uppercased() {
            index = index * 26 + Int(char.asciiValue! - Character("A").asciiValue!) + 1
        }
        return index - 1
    }
}

// MARK: - Errors

enum XLSXError: LocalizedError {
    case unzipFailed
    case noSheets
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .unzipFailed: return "Could not open the Excel file."
        case .noSheets: return "No sheets with data found in the workbook."
        case .invalidFormat: return "The file is not a valid .xlsx spreadsheet."
        }
    }
}

// MARK: - Date conversion

extension XLSXImporter {
    /// Excel stores dates as serial numbers (days since 1899-12-30).
    /// Convert to a Date.
    static func excelSerialToDate(_ serial: Double) -> Date? {
        // Excel epoch: 1899-12-30 (accounting for the Lotus 1-2-3 leap year bug)
        let excelEpoch = DateComponents(calendar: Calendar(identifier: .gregorian),
                                         year: 1899, month: 12, day: 30).date!
        // Serial 1 = 1900-01-01
        return Calendar.current.date(byAdding: .day, value: Int(serial), to: excelEpoch)
    }

    /// Try to parse a cell value as a date — handles both serial numbers and text dates.
    static func parseDate(_ value: String) -> Date? {
        // Try as serial number first (e.g. "45648")
        if let serial = Double(value), serial > 30000 && serial < 100000 {
            return excelSerialToDate(serial)
        }

        // Try common text date formats
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
            "dd/MM/yyyy",
            "MM/dd/yyyy",
            "dd MMM yyyy",
            "dd MMM yy",
        ]
        for format in formats {
            let f = DateFormatter()
            f.dateFormat = format
            f.locale = Locale(identifier: "en_GB")
            if let d = f.date(from: value) {
                let year = Calendar.current.component(.year, from: d)
                if year >= 2000 { return d }
            }
        }
        return nil
    }
}
