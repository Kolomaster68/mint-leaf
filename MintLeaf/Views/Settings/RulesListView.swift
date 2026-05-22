import SwiftUI
import SwiftData

struct RulesListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \CategoryRule.sortOrder) private var rules: [CategoryRule]
    @Query(sort: \MerchantAlias.rawPattern) private var aliases: [MerchantAlias]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @State private var showingNewRule = false
    @State private var showingNewAlias = false
    @State private var editingRule: CategoryRule?
    @State private var editingAlias: MerchantAlias?
    @State private var ruleToDelete: CategoryRule?
    @State private var aliasToDelete: MerchantAlias?

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rules")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(rules.count)")
                            .font(.title3.bold().monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .center, spacing: 2) {
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(rules.filter(\.isEnabled).count)")
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    VStack(alignment: .center, spacing: 2) {
                        Text("Aliases")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(aliases.count)")
                            .font(.title3.bold().monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Categorized")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(transactions.filter { $0.category != nil }.count)")
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(AppTheme.accent(for: scheme))
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label("Summary", systemImage: "chart.bar.xaxis.ascending")
            }

            Section("Category Rules") {
                ForEach(rules) { rule in
                    ruleRow(rule)
                        .swipeActions(edge: .leading) {
                            Button {
                                editingRule = rule
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                ruleToDelete = rule
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }

                Button {
                    showingNewRule = true
                } label: {
                    Label("Add Rule", systemImage: "plus.circle")
                }
            }

            Section("Merchant Aliases") {
                ForEach(aliases) { alias in
                    aliasRow(alias)
                        .swipeActions(edge: .leading) {
                            Button {
                                editingAlias = alias
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                aliasToDelete = alias
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }

                Button {
                    showingNewAlias = true
                } label: {
                    Label("Add Alias", systemImage: "plus.circle")
                }
            }
        }
        .premiumList()
        .navigationTitle("Rules")
        .sheet(isPresented: $showingNewRule) {
            NewRuleSheet()
        }
        .sheet(item: $editingRule) { rule in
            NewRuleSheet(editing: rule)
        }
        .sheet(isPresented: $showingNewAlias) {
            NewAliasSheet()
        }
        .sheet(item: $editingAlias) { alias in
            NewAliasSheet(editing: alias)
        }
        .alert("Delete Rule?", isPresented: .init(
            get: { ruleToDelete != nil },
            set: { if !$0 { ruleToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { ruleToDelete = nil }
            Button("Delete", role: .destructive) {
                if let rule = ruleToDelete {
                    context.delete(rule)
                    ruleToDelete = nil
                }
            }
        } message: {
            Text("This will permanently delete this rule.")
        }
        .alert("Delete Alias?", isPresented: .init(
            get: { aliasToDelete != nil },
            set: { if !$0 { aliasToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { aliasToDelete = nil }
            Button("Delete", role: .destructive) {
                if let alias = aliasToDelete {
                    context.delete(alias)
                    aliasToDelete = nil
                }
            }
        } message: {
            Text("This will permanently delete this alias.")
        }
    }

    private func ruleRow(_ rule: CategoryRule) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(rule.pattern)
                        .font(.body.monospaced())
                    Text(rule.matchType.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }
                if let cat = rule.category {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Label(cat.name, systemImage: cat.icon)
                            .font(.caption)
                            .foregroundStyle(Color(hex: cat.colorHex))
                    }
                }
                let matchCount = transactions.filter { rule.matches($0.title) }.count
                if matchCount > 0 {
                    Text("\(matchCount) matching transactions")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { rule.isEnabled = $0 }
            ))
            .labelsHidden()
        }
        .opacity(rule.isEnabled ? 1 : 0.5)
        .contextMenu {
            Button {
                editingRule = rule
            } label: {
                Label("Edit Rule", systemImage: "pencil")
            }
            Button {
                rule.isEnabled.toggle()
            } label: {
                Label(rule.isEnabled ? "Disable" : "Enable", systemImage: rule.isEnabled ? "pause" : "play")
            }
            Divider()
            Button(role: .destructive) {
                ruleToDelete = rule
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func aliasRow(_ alias: MerchantAlias) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(alias.rawPattern)
                        .font(.body.monospaced())
                    Text(alias.matchType.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(alias.cleanName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { alias.isEnabled },
                set: { alias.isEnabled = $0 }
            ))
            .labelsHidden()
        }
        .opacity(alias.isEnabled ? 1 : 0.5)
        .contextMenu {
            Button {
                editingAlias = alias
            } label: {
                Label("Edit Alias", systemImage: "pencil")
            }
            Button {
                alias.isEnabled.toggle()
            } label: {
                Label(alias.isEnabled ? "Disable" : "Enable", systemImage: alias.isEnabled ? "pause" : "play")
            }
            Divider()
            Button(role: .destructive) {
                aliasToDelete = alias
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct NewRuleSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    var editing: CategoryRule?

    @State private var pattern = ""
    @State private var matchType: RuleMatchType = .contains
    @State private var selectedCategory: Category?

    private var isEditing: Bool { editing != nil }

    private var matchingCount: Int {
        guard !pattern.isEmpty else { return 0 }
        let lowered = pattern.lowercased()
        return transactions.filter { txn in
            let title = txn.title.lowercased()
            switch matchType {
            case .contains: return title.contains(lowered)
            case .startsWith: return title.hasPrefix(lowered)
            case .endsWith: return title.hasSuffix(lowered)
            case .exact: return title == lowered
            case .regex:
                return (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))
                    .map { $0.firstMatch(in: txn.title, range: NSRange(txn.title.startIndex..., in: txn.title)) != nil } ?? false
            }
        }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Pattern (e.g. STARBUCKS)", text: $pattern)
                    Picker("Match Type", selection: $matchType) {
                        ForEach(RuleMatchType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    Picker("Category", selection: $selectedCategory) {
                        Text("None").tag(nil as Category?)
                        ForEach(categories) { cat in
                            Label(cat.name, systemImage: cat.icon).tag(cat as Category?)
                        }
                    }
                }

                if !pattern.isEmpty {
                    Section {
                        HStack {
                            Image(systemName: matchingCount > 0 ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(matchingCount > 0 ? .green : .secondary)
                            Text("\(matchingCount) existing transactions match this rule")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Rule Preview")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Rule" : "New Rule")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        if let editing {
                            editing.pattern = pattern
                            editing.matchType = matchType
                            editing.category = selectedCategory
                        } else {
                            let rule = CategoryRule(pattern: pattern, matchType: matchType, category: selectedCategory)
                            context.insert(rule)
                        }
                        dismiss()
                    }
                    .disabled(pattern.isEmpty)
                }
            }
            .onAppear {
                if let editing {
                    pattern = editing.pattern
                    matchType = editing.matchType
                    selectedCategory = editing.category
                }
            }
        }
        .formStyle(.grouped)
        .macOSSheet(width: 480, height: 420)
    }
}

struct NewAliasSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var editing: MerchantAlias?

    @State private var rawPattern = ""
    @State private var cleanName = ""
    @State private var matchType: RuleMatchType = .contains

    private var isEditing: Bool { editing != nil }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Raw pattern (e.g. TESCO STORES 4332)", text: $rawPattern)
                TextField("Clean name (e.g. Tesco)", text: $cleanName)
                Picker("Match Type", selection: $matchType) {
                    ForEach(RuleMatchType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Alias" : "New Merchant Alias")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        if let editing {
                            editing.rawPattern = rawPattern
                            editing.cleanName = cleanName
                            editing.matchType = matchType
                        } else {
                            let alias = MerchantAlias(rawPattern: rawPattern, cleanName: cleanName, matchType: matchType)
                            context.insert(alias)
                        }
                        dismiss()
                    }
                    .disabled(rawPattern.isEmpty || cleanName.isEmpty)
                }
            }
            .onAppear {
                if let editing {
                    rawPattern = editing.rawPattern
                    cleanName = editing.cleanName
                    matchType = editing.matchType
                }
            }
        }
        .formStyle(.grouped)
        .macOSSheet(width: 480, height: 320)
    }
}
