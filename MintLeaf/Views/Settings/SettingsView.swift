import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @AppStorage("appAppearance") private var appearance: String = AppAppearance.system.rawValue
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("textSizeOffset") private var textSizeOffset: Int = 0
    @AppStorage("highContrastMode") private var highContrastMode = false
    @AppStorage("reduceMotion") private var reduceMotion = false
    @State private var pendingAppearance: String = AppAppearance.system.rawValue
    @State private var showingNewCategory = false
    @State private var editingCategory: Category?
    @State private var categoryToDelete: Category?
    @State private var showingResetConfirmation = false
    @State private var showingExporter = false
    @State private var showingSampleDataConfirmation = false
    @State private var csvContent = ""
    @State private var statusMessage = ""
    @State private var categorySearch = ""
    @State private var categoryFilter: CategoryFilter = .all
    @AppStorage("appIconStyle") private var appIconStyle: String = "system"
    @State private var settingsTab: SettingsTab = .general
    @State private var categorySortKey: CategorySortKey = .name
    @State private var categorySortAscending = true
    @State private var showingIconPicker = false

    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case categories = "Categories"

        var icon: String {
            switch self {
            case .general: return "gear"
            case .categories: return "tag"
            }
        }
    }

    enum CategoryFilter: String, CaseIterable {
        case all = "All"
        case expense = "Expense"
        case income = "Income"
    }

    enum CategorySortKey: String {
        case name, type, transactions, total
    }

    private var hasSampleData: Bool {
        !accounts.isEmpty
    }

    private var textSizeLabel: String {
        switch textSizeOffset {
        case -2: return "Smallest"
        case -1: return "Smaller"
        case 0: return "Default"
        case 1: return "Larger"
        case 2: return "Largest"
        default: return "Default"
        }
    }

    private var previewScale: CGFloat {
        switch textSizeOffset {
        case -2: return 0.85
        case -1: return 0.92
        case 0: return 1.0
        case 1: return 1.1
        case 2: return 1.2
        default: return 1.0
        }
    }

    var body: some View {
        #if os(macOS)
        macOSSettings
        #else
        iOSSettings
        #endif
    }

    #if os(macOS)
    private var macOSSettings: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        settingsTab = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.title2)
                            Text(tab.rawValue)
                                .font(.caption)
                        }
                        .foregroundStyle(settingsTab == tab ? AppTheme.accent(for: scheme) : .secondary)
                        .frame(width: 64, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(settingsTab == tab ? AppTheme.accent(for: scheme).opacity(0.1) : .clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(settingsTab == tab ? AppTheme.accent(for: scheme).opacity(0.4) : .clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            Group {
                switch settingsTab {
                case .general:
                    generalTab
                case .categories:
                    categoriesTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 560, minHeight: 550)
        .onAppear { pendingAppearance = appearance }
        .overlay(alignment: .bottom) {
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent(for: scheme))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showingNewCategory) {
            NewCategorySheet()
        }
        .sheet(item: $editingCategory) { cat in
            NewCategorySheet(editing: cat)
        }
        .alert("Delete Category?", isPresented: .init(
            get: { categoryToDelete != nil },
            set: { if !$0 { categoryToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { categoryToDelete = nil }
            Button("Delete", role: .destructive) {
                if let cat = categoryToDelete {
                    context.delete(cat)
                    categoryToDelete = nil
                }
            }
        } message: {
            Text("This will remove \"\(categoryToDelete?.name ?? "")\" from all transactions that use it.")
        }
        .alert("Reset All Data?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Everything", role: .destructive) {
                resetAllData()
                showStatus("All data has been reset")
            }
        } message: {
            Text("This will permanently delete all accounts, transactions, budgets, rules, and categories. This cannot be undone.")
        }
        .alert("Load Sample Data?", isPresented: $showingSampleDataConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Load") {
                SampleDataGenerator.populate(context: context)
                try? context.save()
                showStatus("Sample data loaded successfully")
            }
        } message: {
            Text("This will add sample accounts, transactions, budgets and scheduled items. Your existing data will not be affected.")
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: CSVDocument(content: csvContent),
            contentType: .commaSeparatedText,
            defaultFilename: "MintLeaf-Export-\(exportDateString).csv"
        ) { _ in }
    }

    private var generalTab: some View {
        Form {
            settingsContent
        }
        .formStyle(.grouped)
    }

    private var filteredCategories: [Category] {
        var cats = categories
        switch categoryFilter {
        case .all: break
        case .expense: cats = cats.filter { !$0.isIncome }
        case .income: cats = cats.filter { $0.isIncome }
        }
        if !categorySearch.isEmpty {
            cats = cats.filter { $0.name.localizedCaseInsensitiveContains(categorySearch) }
        }
        switch categorySortKey {
        case .name:
            cats.sort { categorySortAscending ? $0.name.localizedCompare($1.name) == .orderedAscending : $0.name.localizedCompare($1.name) == .orderedDescending }
        case .type:
            cats.sort { categorySortAscending ? (!$0.isIncome && $1.isIncome) : ($0.isIncome && !$1.isIncome) }
        case .transactions:
            cats.sort { categorySortAscending ? $0.transactions.count < $1.transactions.count : $0.transactions.count > $1.transactions.count }
        case .total:
            let totals: [UUID: Decimal] = Dictionary(uniqueKeysWithValues: cats.map { ($0.id, $0.transactions.reduce(Decimal.zero) { $0 + abs($1.amount) }) })
            cats.sort { categorySortAscending ? (totals[$0.id] ?? 0) < (totals[$1.id] ?? 0) : (totals[$0.id] ?? 0) > (totals[$1.id] ?? 0) }
        }
        return cats
    }

    private var categoriesTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search categories...", text: $categorySearch)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppTheme.accent(for: scheme).opacity(0.15), lineWidth: 1))

                HStack(spacing: 0) {
                    ForEach(CategoryFilter.allCases, id: \.self) { filter in
                        if filter != .all {
                            Rectangle()
                                .fill(AppTheme.accent(for: scheme).opacity(0.2))
                                .frame(width: 1)
                                .padding(.vertical, 4)
                        }
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { categoryFilter = filter }
                        } label: {
                            Text(filter.rawValue)
                                .font(.subheadline.weight(categoryFilter == filter ? .semibold : .regular))
                                .foregroundStyle(categoryFilter == filter ? AppTheme.accent(for: scheme) : .secondary)
                                .padding(.horizontal, 12)
                                .frame(height: 26)
                                .contentShape(Rectangle())
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(categoryFilter == filter ? AppTheme.accent(for: scheme).opacity(0.1) : .clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(categoryFilter == filter ? AppTheme.accent(for: scheme).opacity(0.4) : .clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .frame(height: 30)
                .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))

                Button(action: { showingNewCategory = true }) {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent(for: scheme))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                }
                .buttonStyle(.plain)
                .background(AppTheme.accent(for: scheme).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppTheme.accent(for: scheme).opacity(0.4), lineWidth: 1))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            HStack(spacing: 0) {
                columnHeader("Category", key: .name, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                columnHeader("Type", key: .type, alignment: .center)
                    .frame(width: 80)
                columnHeader("Used", key: .transactions, alignment: .trailing)
                    .frame(width: 70)
                columnHeader("Total", key: .total, alignment: .trailing)
                    .frame(width: 100)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
            .background(AppTheme.cardBackground(for: scheme).opacity(0.5))

            Divider().opacity(0.3)

            List {
                ForEach(filteredCategories) { cat in
                    categoryRow(cat)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
        }
    }
    #endif

    private var iOSSettings: some View {
        NavigationStack {
            Form {
                settingsContent

                Section {
                    NavigationLink {
                        RulesListView()
                    } label: {
                        Label("Rules & Automation", systemImage: "wand.and.rays")
                    }
                    NavigationLink {
                        PrivacyDashboardView()
                    } label: {
                        Label("Privacy & Security", systemImage: "lock.shield")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        Section("Appearance") {
            OutlineSegmentedPicker(
                selection: Binding(
                    get: { AppAppearance(rawValue: pendingAppearance) ?? .system },
                    set: { pendingAppearance = $0.rawValue }
                ),
                label: "Theme"
            )
        }

        #if os(macOS)
        Section("App Icon") {
            HStack(spacing: 16) {
                iconOption("System", style: "system")
                iconOption("Light", style: "light")
                iconOption("Dark", style: "dark")
                iconOption("Custom", style: "custom")
            }
            .padding(.vertical, 4)

            if appIconStyle == "custom" {
                Button("Choose Image...") {
                    chooseCustomIcon()
                }
                .font(.subheadline)
            }
        }
        #endif

        Section("Accessibility") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Text Size")
                    Spacer()
                    Text(textSizeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "textformat.size.smaller")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { Double(textSizeOffset) },
                        set: { textSizeOffset = Int($0) }
                    ), in: -2...2, step: 1)
                    .tint(AppTheme.accent(for: scheme))
                    Image(systemName: "textformat.size.larger")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Preview: The quick brown fox")
                    .font(.system(size: 13 * previewScale))
                    .padding(.top, 2)
            }

            Toggle(isOn: $highContrastMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("High Contrast")
                    Text("Thicker borders and bolder text for better visibility")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $reduceMotion) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reduce Motion")
                    Text("Minimise animations throughout the app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        Section("Interactive Guides") {
            ForEach(TutorialLibrary.allFlows) { flow in
                HStack(spacing: 12) {
                    Image(systemName: flow.icon)
                        .font(.title3)
                        .foregroundStyle(AppTheme.accent(for: scheme))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(flow.title)
                            .font(.subheadline.weight(.medium))
                        Text(flow.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if TutorialEngine.shared.isCompleted(flow.id) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                    Button("Replay") {
                        appearance = pendingAppearance
                        try? context.save()
                        NSApp.keyWindow?.close()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            TutorialEngine.shared.start(flow)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent(for: scheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppTheme.accent(for: scheme).opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(AppTheme.accent(for: scheme).opacity(0.3), lineWidth: 1))
                }
            }
        }

        Section("Data") {
            Button("Export All Data as CSV") {
                csvContent = buildCSVExport()
                showingExporter = true
            }
            Button("Load Sample Data") {
                showingSampleDataConfirmation = true
            }
            .disabled(hasSampleData)
            Button("Reset All Data", role: .destructive) {
                showingResetConfirmation = true
            }
        }

        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundStyle(.secondary)
            }
        }

        #if os(macOS)
        Section {
            HStack {
                Spacer()
                Button("Save & Close") {
                    appearance = pendingAppearance
                    try? context.save()
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent(for: scheme))
            }
        }
        #endif
    }

    private func columnHeader(_ title: String, key: CategorySortKey, alignment: Alignment) -> some View {
        Button {
            if categorySortKey == key {
                categorySortAscending.toggle()
            } else {
                categorySortKey = key
                categorySortAscending = key == .name
            }
        } label: {
            HStack(spacing: 3) {
                if alignment == .trailing { Spacer() }
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(categorySortKey == key ? AppTheme.accent(for: scheme) : .secondary)
                if categorySortKey == key {
                    Image(systemName: categorySortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.accent(for: scheme))
                }
                if alignment == .leading { Spacer() }
            }
        }
        .buttonStyle(.plain)
    }

    private func categoryRow(_ cat: Category) -> some View {
        let count = cat.transactions.count
        let total = cat.transactions.reduce(Decimal.zero) { $0 + abs($1.amount) }

        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: cat.icon)
                    .font(.caption)
                    .foregroundStyle(Color(hex: cat.colorHex))
                    .frame(width: 24, height: 24)
                    .background(Color(hex: cat.colorHex).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(cat.name)
                    .font(.subheadline)
                    .foregroundStyle(Color(hex: cat.colorHex))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(cat.isIncome ? "Income" : "Expense")
                .font(.caption2)
                .foregroundStyle(cat.isIncome ? .green : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    (cat.isIncome ? Color.green : Color.secondary).opacity(0.1),
                    in: Capsule()
                )
                .frame(width: 80)

            Text(count > 0 ? "\(count)" : "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(count > 0 ? .secondary : .tertiary)
                .frame(width: 70, alignment: .trailing)

            Text(count > 0 ? CurrencyFormatter.shared.format(total) : "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(count > 0 ? .secondary : .tertiary)
                .frame(width: 100, alignment: .trailing)
        }
        .contextMenu {
                Button {
                    editingCategory = cat
                } label: {
                    Label("Edit Category", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) {
                    categoryToDelete = cat
                } label: {
                    Label("Delete Category", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button {
                    editingCategory = cat
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.orange)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    categoryToDelete = cat
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    #if os(macOS)
    private func iconPreview(isDark: Bool, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(isDark
                    ? Color(red: 0.06, green: 0.06, blue: 0.06)
                    : Color(red: 0.96, green: 0.96, blue: 0.97))
            Image(systemName: "leaf.fill")
                .font(.system(size: size * 0.42, weight: .regular))
                .foregroundStyle(
                    isDark
                        ? AppTheme.accentGradient(for: .dark)
                        : AppTheme.accentGradient(for: .light)
                )
        }
        .frame(width: size, height: size)
    }

    private func iconOption(_ label: String, style: String) -> some View {
        let selected = appIconStyle == style
        return Button {
            appIconStyle = style
            applyIconStyle(style)
        } label: {
            VStack(spacing: 6) {
                Group {
                    if style == "system" {
                        ZStack {
                            iconPreview(isDark: false, size: 56)
                            iconPreview(isDark: true, size: 56)
                                .clipShape(HalfShape())
                        }
                    } else if style == "light" {
                        iconPreview(isDark: false, size: 56)
                    } else if style == "dark" {
                        iconPreview(isDark: true, size: 56)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppTheme.cardBackground(for: scheme))
                            Image(systemName: "photo.badge.plus")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 56, height: 56)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(selected ? AppTheme.accent(for: scheme) : .clear, lineWidth: 2)
                )

                Text(label)
                    .font(.caption)
                    .foregroundStyle(selected ? AppTheme.accent(for: scheme) : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func applyIconStyle(_ style: String) {
        switch style {
        case "light":
            NSApplication.shared.applicationIconImage = renderLeafIcon(isDark: false)
        case "dark":
            NSApplication.shared.applicationIconImage = renderLeafIcon(isDark: true)
        case "system":
            NSApplication.shared.applicationIconImage = nil
        case "custom":
            if let data = UserDefaults.standard.data(forKey: "customIconData"),
               let img = NSImage(data: data) {
                NSApplication.shared.applicationIconImage = img
            }
        default:
            break
        }
    }

    private func renderLeafIcon(isDark: Bool) -> NSImage? {
        let size: CGFloat = 512
        let view = ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(isDark
                    ? Color(red: 0.06, green: 0.06, blue: 0.06)
                    : Color(red: 0.96, green: 0.96, blue: 0.97))
            Image(systemName: "leaf.fill")
                .font(.system(size: size * 0.52, weight: .regular))
                .foregroundStyle(
                    isDark
                        ? AppTheme.accentGradient(for: .dark)
                        : AppTheme.accentGradient(for: .light)
                )
        }
        .frame(width: size, height: size)

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: size, height: size)
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let img = NSImage(size: NSSize(width: size, height: size))
        img.addRepresentation(rep)
        return img
    }

    private func chooseCustomIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an image for your app icon"
        if panel.runModal() == .OK, let url = panel.url,
           let img = NSImage(contentsOf: url) {
            if let tiff = img.tiffRepresentation {
                UserDefaults.standard.set(tiff, forKey: "customIconData")
            }
            NSApplication.shared.applicationIconImage = img
        }
    }
    #endif

    private func showStatus(_ message: String) {
        withAnimation { statusMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { statusMessage = "" }
        }
    }

    private var exportDateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func buildCSVExport() -> String {
        var lines = ["Date,Account,Payee,Amount,Category,Notes,Reconciled"]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for account in accounts {
            for txn in account.transactions.sorted(by: { $0.date < $1.date }) {
                let date = dateFormatter.string(from: txn.date)
                let acct = csvEscape(account.name)
                let payee = csvEscape(txn.title)
                let amount = "\(txn.amount)"
                let category = csvEscape(txn.category?.name ?? "")
                let notes = csvEscape(txn.notes)
                let reconciled = txn.isReconciled ? "Yes" : "No"
                lines.append("\(date),\(acct),\(payee),\(amount),\(category),\(notes),\(reconciled)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }

    private func resetAllData() {
        do {
            try context.delete(model: Transaction.self)
            try context.delete(model: BudgetItem.self)
            try context.delete(model: Budget.self)
            try context.delete(model: ScheduledTransaction.self)
            try context.delete(model: CategoryRule.self)
            try context.delete(model: MerchantAlias.self)
            try context.delete(model: Account.self)
            try context.delete(model: Category.self)
            try context.save()
            DefaultCategories.seed(context: context)
            try context.save()
            hasCompletedOnboarding = false
        } catch {
            print("Reset failed: \(error)")
        }
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var content: String

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        content = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: content.data(using: .utf8) ?? Data())
    }
}

struct NewCategorySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let editing: Category?

    @State private var name = ""
    @State private var icon = "tag"
    @State private var isIncome = false
    @State private var colorHex = "#2196F3"
    @State private var useCustomColor = false
    @State private var customColor = Color.blue
    @State private var iconSearch = ""

    init(editing: Category? = nil) {
        self.editing = editing
    }

    private static let allIcons: [(String, [String])] = [
        ("Shopping", ["cart", "cart.fill", "bag", "bag.fill", "basket", "basket.fill", "handbag", "creditcard", "giftcard", "tag", "tag.fill"]),
        ("Food & Drink", ["fork.knife", "cup.and.saucer", "takeoutbag.and.cup.and.straw", "wineglass", "birthday.cake", "carrot", "leaf"]),
        ("Transport", ["car", "car.fill", "bus", "tram", "bicycle", "fuelpump", "airplane", "ferry"]),
        ("Home", ["house", "house.fill", "bed.double", "sofa", "washer", "lightbulb", "bolt", "bolt.fill", "drop", "flame"]),
        ("Health", ["heart", "heart.fill", "cross.case", "pills", "bandage", "stethoscope", "figure.run", "dumbbell"]),
        ("Entertainment", ["tv", "tv.fill", "gamecontroller", "headphones", "music.note", "film", "theatermasks", "party.popper", "sportscourt"]),
        ("Finance", ["banknote", "dollarsign.circle", "percent", "chart.line.uptrend.xyaxis", "chart.pie", "building.columns", "safe"]),
        ("Work & Education", ["briefcase", "briefcase.fill", "laptopcomputer", "desktopcomputer", "book", "book.fill", "graduationcap", "pencil.and.ruler"]),
        ("Travel", ["globe", "globe.americas", "map", "suitcase", "suitcase.fill", "camera", "binoculars", "tent"]),
        ("People & Gifts", ["gift", "gift.fill", "person.2", "figure.and.child.holdinghands", "teddybear", "pawprint"]),
        ("Other", ["wrench", "hammer", "paintbrush", "scissors", "doc.text", "envelope", "phone", "wifi", "cloud", "sun.max", "snowflake", "star", "star.fill"]),
    ]

    private static let nameToIcons: [String: [String]] = [
        "food": ["fork.knife", "takeoutbag.and.cup.and.straw", "cup.and.saucer"],
        "dining": ["fork.knife", "wineglass", "cup.and.saucer"],
        "grocery": ["cart", "basket", "carrot"],
        "groceries": ["cart", "basket", "carrot"],
        "transport": ["car", "bus", "fuelpump"],
        "gas": ["fuelpump", "car", "bolt"],
        "fuel": ["fuelpump", "car", "flame"],
        "housing": ["house", "house.fill", "bed.double"],
        "rent": ["house", "building.columns", "house.fill"],
        "utilities": ["bolt", "lightbulb", "drop"],
        "health": ["heart", "cross.case", "stethoscope"],
        "fitness": ["figure.run", "dumbbell", "heart"],
        "entertainment": ["tv", "gamecontroller", "film"],
        "shopping": ["bag", "cart", "tag"],
        "clothing": ["tshirt", "bag", "tag"],
        "education": ["book", "graduationcap", "pencil.and.ruler"],
        "travel": ["airplane", "suitcase", "globe"],
        "subscription": ["arrow.triangle.2.circlepath", "tv", "music.note"],
        "insurance": ["shield", "umbrella", "doc.text"],
        "salary": ["banknote", "dollarsign.circle", "building.columns"],
        "freelance": ["laptopcomputer", "briefcase", "desktopcomputer"],
        "interest": ["percent", "chart.line.uptrend.xyaxis", "banknote"],
        "gift": ["gift", "gift.fill", "teddybear"],
        "coffee": ["cup.and.saucer", "leaf", "takeoutbag.and.cup.and.straw"],
        "car": ["car", "fuelpump", "wrench"],
        "phone": ["phone", "wifi", "desktopcomputer"],
        "pet": ["pawprint", "teddybear", "heart"],
        "kids": ["figure.and.child.holdinghands", "teddybear", "birthday.cake"],
        "tax": ["percent", "doc.text", "building.columns"],
    ]

    private var recommendedIcons: [String] {
        let lower = name.lowercased()
        for (keyword, icons) in Self.nameToIcons {
            if lower.contains(keyword) { return icons }
        }
        return []
    }

    private var filteredIcons: [(String, [String])] {
        if iconSearch.isEmpty { return Self.allIcons }
        let q = iconSearch.lowercased()
        return Self.allIcons.compactMap { group in
            let matching = group.1.filter { $0.lowercased().contains(q) }
            if group.0.lowercased().contains(q) { return group }
            if matching.isEmpty { return nil }
            return (group.0, matching)
        }
    }

    private let presetColors = [
        "#2196F3", "#4CAF50", "#FF9800", "#E91E63",
        "#9C27B0", "#00BCD4", "#795548", "#607D8B",
        "#F44336", "#3F51B5", "#009688", "#FFC107",
    ]

    private func iconButton(_ ic: String) -> some View {
        Image(systemName: ic)
            .font(.body)
            .frame(width: 32, height: 32)
            .background(ic == icon ? Color(hex: colorHex).opacity(0.25) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(ic == icon ? Color(hex: colorHex).opacity(0.6) : .clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .onTapGesture { icon = ic }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(editing != nil ? "Edit Category" : "New Category")
                    .font(.headline)
                Spacer()
                Button(editing != nil ? "Save" : "Add") {
                    if let existing = editing {
                        existing.name = name
                        existing.icon = icon
                        existing.colorHex = colorHex
                        existing.isIncome = isIncome
                    } else {
                        let cat = Category(name: name, icon: icon, colorHex: colorHex, isIncome: isIncome)
                        context.insert(cat)
                    }
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(name.isEmpty ? .secondary : AppTheme.accent(for: scheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(AppTheme.accent(for: scheme).opacity(name.isEmpty ? 0.05 : 0.1), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppTheme.accent(for: scheme).opacity(name.isEmpty ? 0.1 : 0.4), lineWidth: 1))
                .disabled(name.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.title2)
                            .foregroundStyle(Color(hex: colorHex))
                            .frame(width: 40, height: 40)
                            .background(Color(hex: colorHex).opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        TextField("Category Name", text: $name)
                            .font(.title3.bold())
                            .textFieldStyle(.plain)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        HStack(spacing: 0) {
                            Button {
                                isIncome = false
                            } label: {
                                Text("Expense")
                                    .font(.caption.weight(!isIncome ? .semibold : .regular))
                                    .foregroundStyle(!isIncome ? AppTheme.accent(for: scheme) : .secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(!isIncome ? AppTheme.accent(for: scheme).opacity(0.1) : .clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(!isIncome ? AppTheme.accent(for: scheme).opacity(0.4) : .clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            Rectangle()
                                .fill(AppTheme.accent(for: scheme).opacity(0.2))
                                .frame(width: 1)
                                .padding(.vertical, 6)
                            Button {
                                isIncome = true
                            } label: {
                                Text("Income")
                                    .font(.caption.weight(isIncome ? .semibold : .regular))
                                    .foregroundStyle(isIncome ? AppTheme.accent(for: scheme) : .secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(isIncome ? AppTheme.accent(for: scheme).opacity(0.1) : .clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(isIncome ? AppTheme.accent(for: scheme).opacity(0.4) : .clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(2)
                        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))
                        .fixedSize()
                    }

                    if !recommendedIcons.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Suggested")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                ForEach(recommendedIcons, id: \.self) { ic in
                                    iconButton(ic)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Icons")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Search icons...", text: $iconSearch)
                                    .textFieldStyle(.plain)
                                    .frame(width: 120)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                        }

                        ForEach(filteredIcons, id: \.0) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.0)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.tertiary)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 11), spacing: 4) {
                                    ForEach(group.1, id: \.self) { ic in
                                        iconButton(ic)
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Color")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                            ForEach(presetColors, id: \.self) { color in
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if color == colorHex && !useCustomColor {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.white)
                                                .font(.caption.bold())
                                        }
                                    }
                                    .onTapGesture {
                                        colorHex = color
                                        useCustomColor = false
                                    }
                            }
                        }
                        HStack {
                            Toggle("Custom", isOn: $useCustomColor)
                                .font(.subheadline)
                            if useCustomColor {
                                ColorPicker("", selection: $customColor, supportsOpacity: false)
                                    .labelsHidden()
                                    .onChange(of: customColor) { _, newVal in
                                        colorHex = newVal.toHex()
                                    }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .onAppear {
            if let cat = editing {
                name = cat.name
                icon = cat.icon
                isIncome = cat.isIncome
                colorHex = cat.colorHex
                if !presetColors.contains(cat.colorHex) {
                    useCustomColor = true
                    customColor = Color(hex: cat.colorHex)
                }
            }
        }
        .macOSSheet(width: 500, height: 640)
    }
}

private struct HalfShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.midX, y: 0, width: rect.width / 2, height: rect.height))
    }
}
