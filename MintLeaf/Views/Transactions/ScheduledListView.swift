import SwiftUI
import SwiftData

struct ScheduledListView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context
    @Query(sort: \ScheduledTransaction.nextDate) private var scheduled: [ScheduledTransaction]
    @State private var showingNew = false
    @State private var editingItem: ScheduledTransaction?
    @State private var filter: ScheduledFilter = .all

    var filterMode: ScheduledFilter?

    init(filterMode: ScheduledFilter? = nil) {
        self.filterMode = filterMode
        if let filterMode {
            _filter = State(initialValue: filterMode)
        }
    }

    enum ScheduledFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case subscriptions = "Subscriptions"
        case bills = "Bills & Payments"

        var id: String { rawValue }
    }

    private var filteredItems: [ScheduledTransaction] {
        switch filter {
        case .all: return scheduled
        case .subscriptions: return scheduled.filter { $0.isSubscription }
        case .bills: return scheduled.filter { !$0.isSubscription }
        }
    }

    private var summaryItems: [ScheduledTransaction] {
        filteredItems.filter { $0.isActive }
    }

    private var summaryMonthly: Decimal {
        summaryItems.reduce(Decimal.zero) { $0 + $1.monthlyEquivalent }
    }

    private var summaryLabel: String {
        switch filter {
        case .all: return "Summary"
        case .subscriptions: return "Subscription Summary"
        case .bills: return "Bills & Payments Summary"
        }
    }

    private var summaryIcon: String {
        switch filter {
        case .all: return "chart.bar.xaxis.ascending"
        case .subscriptions: return "arrow.triangle.2.circlepath"
        case .bills: return "creditcard"
        }
    }

    var body: some View {
        List {
            if !summaryItems.isEmpty {
                Section {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Monthly")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(CurrencyFormatter.shared.format(summaryMonthly))
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Yearly")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(CurrencyFormatter.shared.format(summaryMonthly * 12))
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Active")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(summaryItems.count)")
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(AppTheme.accent(for: scheme))
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label(summaryLabel, systemImage: summaryIcon)
                }
            }

            Section {
                ForEach(filteredItems) { item in
                ScheduledRowView(item: item)
                .contentShape(Rectangle())
                #if os(macOS)
                .onTapGesture(count: 2) { editingItem = item }
                #endif
                .contextMenu {
                    Button {
                        editingItem = item
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button {
                        item.isActive.toggle()
                    } label: {
                        Label(item.isActive ? "Pause" : "Resume", systemImage: item.isActive ? "pause" : "play")
                    }
                    Divider()
                    Button(role: .destructive) {
                        context.delete(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        context.delete(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        item.isActive.toggle()
                    } label: {
                        Label(item.isActive ? "Pause" : "Resume", systemImage: item.isActive ? "pause" : "play")
                    }
                    .tint(item.isActive ? .orange : .accentColor)
                }
                .swipeActions(edge: .leading) {
                    Button {
                        editingItem = item
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
                .opacity(item.isActive ? 1 : 0.5)
                }
            }
        }
        .overlay {
            if filteredItems.isEmpty {
                ContentUnavailableView(
                    filter == .subscriptions ? "No Subscriptions" : filter == .bills ? "No Bills" : "No Scheduled Transactions",
                    systemImage: filter == .subscriptions ? "arrow.triangle.2.circlepath" : "clock.arrow.circlepath",
                    description: Text(filter == .subscriptions ? "Subscriptions you add will appear here." : "Set up recurring bills and income.")
                )
            }
        }
        .premiumList()
        .navigationTitle(filterMode == .bills ? "Bills & Payments" : "Scheduled")
        .toolbar {
            if filterMode == nil {
                ToolbarItem(placement: .automatic) {
                    Picker("Filter", selection: $filter) {
                        ForEach(ScheduledFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingNew = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNew) {
            NewScheduledSheet()
        }
        .sheet(item: $editingItem) { item in
            NewScheduledSheet(editing: item)
        }
    }
}

struct ScheduledRowView: View {
    let title: String
    let frequency: String
    let formattedAmount: String
    let isExpense: Bool
    let nextDate: Date
    let isSubscription: Bool

    init(item: ScheduledTransaction) {
        self.title = item.title
        self.frequency = item.frequency.rawValue
        self.formattedAmount = CurrencyFormatter.shared.format(item.amount)
        self.isExpense = item.amount < 0
        self.nextDate = item.nextDate
        self.isSubscription = item.isSubscription
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.body)
                    if isSubscription {
                        Text("SUB")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.15), in: Capsule())
                    }
                }
                Text(frequency)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(formattedAmount)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(isExpense ? .red : .green)
                Text("Next: \(nextDate, style: .date)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct NewScheduledSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    var editing: ScheduledTransaction?

    @State private var title = ""
    @State private var amount = ""
    @State private var isExpense = true
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var nextDate = Date()
    @State private var selectedAccount: Account?
    @State private var selectedCategory: Category?
    @State private var isSubscription = false
    @State private var showSubscriptionSuggestion = false

    private var isEditing: Bool { editing != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Description", text: $title)
                        .onChange(of: title) { _, _ in checkSubscription() }
                    TextField("Amount", text: $amount)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .onChange(of: amount) { _, _ in checkSubscription() }
                    Picker("Type", selection: $isExpense) {
                        Text("Expense").tag(true)
                        Text("Income").tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(RecurrenceFrequency.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .onChange(of: frequency) { _, _ in checkSubscription() }
                    DatePicker("Next Date", selection: $nextDate, displayedComponents: .date)
                }

                Section {
                    Picker("Account", selection: $selectedAccount) {
                        Text("None").tag(nil as Account?)
                        ForEach(accounts.filter { !$0.isArchived }) { acc in
                            Text(acc.name).tag(acc as Account?)
                        }
                    }
                    Picker("Category", selection: $selectedCategory) {
                        Text("None").tag(nil as Category?)
                        ForEach(categories.filter { $0.isIncome == !isExpense }) { cat in
                            Label(cat.name, systemImage: cat.icon).tag(cat as Category?)
                        }
                    }
                }

                Section {
                    Toggle(isOn: $isSubscription) {
                        Label("Subscription", systemImage: "arrow.triangle.2.circlepath")
                    }

                    if showSubscriptionSuggestion && !isSubscription {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.orange)
                            Text("This looks like a subscription. Mark it as one?")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Yes") {
                                withAnimation { isSubscription = true; showSubscriptionSuggestion = false }
                            }
                            .font(.caption.bold())
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Scheduled" : "New Scheduled")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .disabled(title.isEmpty || amount.isEmpty)
                }
            }
            .onAppear {
                if let editing {
                    title = editing.title
                    amount = "\(abs(editing.amount))"
                    isExpense = editing.amount < 0
                    frequency = editing.frequency
                    nextDate = editing.nextDate
                    selectedAccount = editing.account
                    selectedCategory = editing.category
                    isSubscription = editing.isSubscription
                }
            }
        }
        .macOSSheet(width: 560, height: 620)
    }

    private func checkSubscription() {
        guard !isEditing, !isSubscription else { return }
        let amt = Decimal(string: amount) ?? 0
        let signed = isExpense ? -abs(amt) : abs(amt)
        let detected = SubscriptionDetector.looksLikeSubscription(title: title, amount: signed, frequency: frequency)
        withAnimation { showSubscriptionSuggestion = detected }
    }

    private func save() {
        guard let value = Decimal(string: amount) else { return }
        let signed = isExpense ? -abs(value) : abs(value)

        if let editing {
            editing.title = title
            editing.amount = signed
            editing.frequency = frequency
            editing.nextDate = nextDate
            editing.account = selectedAccount
            editing.category = selectedCategory
            editing.isSubscription = isSubscription
        } else {
            let s = ScheduledTransaction(
                amount: signed,
                title: title,
                frequency: frequency,
                nextDate: nextDate,
                account: selectedAccount,
                category: selectedCategory,
                isSubscription: isSubscription
            )
            context.insert(s)
        }
        dismiss()
    }
}
