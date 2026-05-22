import SwiftUI
import SwiftData

struct SubscriptionCalendarView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context
    @Query(sort: \ScheduledTransaction.nextDate) private var allScheduled: [ScheduledTransaction]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @State private var displayedMonth = Date()
    @State private var selectedDay: DateComponents?
    @State private var editingItem: ScheduledTransaction?
    @State private var showingStats = false
    @State private var showingAddSheet = false
    @State private var addingOnDay: DateComponents?
    @State private var accumulatedScroll: CGFloat = 0
    @State private var drawerVisible = false

    private let calendar = Calendar.current
    private let dayColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var subscriptions: [ScheduledTransaction] {
        allScheduled.filter { $0.isSubscription && $0.isActive }
    }

    private var pausedSubscriptions: [ScheduledTransaction] {
        allScheduled.filter { $0.isSubscription && !$0.isActive }
    }

    private var monthlyTotal: Decimal {
        subscriptions.reduce(Decimal.zero) { $0 + $1.monthlyEquivalent }
    }

    private var topCategory: (name: String, total: Decimal)? {
        let grouped = Dictionary(grouping: subscriptions) { $0.category?.name ?? "Uncategorised" }
        let totals = grouped.mapValues { items in
            items.reduce(Decimal.zero) { $0 + $1.monthlyEquivalent }
        }
        return totals.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
    }

    private var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM, yyyy"
        return formatter.string(from: displayedMonth)
    }

    private var daysInMonth: [DateComponents] {
        let range = calendar.range(of: .day, in: .month, for: displayedMonth) ?? 1..<31
        let year = calendar.component(.year, from: displayedMonth)
        let month = calendar.component(.month, from: displayedMonth)
        return range.map { DateComponents(year: year, month: month, day: $0) }
    }

    private var firstWeekdayOffset: Int {
        guard let firstDay = calendar.date(from: DateComponents(
            year: calendar.component(.year, from: displayedMonth),
            month: calendar.component(.month, from: displayedMonth),
            day: 1
        )) else { return 0 }
        let weekday = calendar.component(.weekday, from: firstDay)
        return (weekday + 5) % 7
    }

    private func subscriptionsForDay(_ dc: DateComponents) -> [ScheduledTransaction] {
        guard let day = dc.day else { return [] }
        return subscriptions.filter { sub in
            let subDay = calendar.component(.day, from: sub.nextDate)
            switch sub.frequency {
            case .daily:
                return true
            case .weekly:
                guard let date = calendar.date(from: dc) else { return false }
                return calendar.component(.weekday, from: date) == calendar.component(.weekday, from: sub.nextDate)
            case .biweekly:
                guard let date = calendar.date(from: dc) else { return false }
                let diff = calendar.dateComponents([.day], from: sub.nextDate, to: date).day ?? 0
                return diff % 14 == 0
            case .monthly:
                return subDay == day
            case .quarterly:
                let subMonth = calendar.component(.month, from: sub.nextDate)
                guard let month = dc.month else { return false }
                return subDay == day && (month - subMonth) % 3 == 0
            case .yearly:
                let subMonth = calendar.component(.month, from: sub.nextDate)
                guard let month = dc.month else { return false }
                return subDay == day && subMonth == month
            }
        }
    }

    private func daySpend(_ dc: DateComponents) -> Decimal {
        subscriptionsForDay(dc).reduce(Decimal.zero) { $0 + abs($1.amount) }
    }

    private var isCurrentMonth: Bool {
        let now = Date()
        return calendar.component(.month, from: displayedMonth) == calendar.component(.month, from: now)
            && calendar.component(.year, from: displayedMonth) == calendar.component(.year, from: now)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.surfaceBackground(for: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection
                calendarGrid
                    .frame(maxHeight: .infinity)

                if !pausedSubscriptions.isEmpty && selectedDay == nil {
                    pausedSection
                }
            }

            // Detail drawer overlays from the bottom
            if let selected = selectedDay {
                let subs = subscriptionsForDay(selected)

                // Dim overlay
                Color.black.opacity(drawerVisible ? 0.2 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { dismissDrawer() }

                selectedDayDetail(day: selected, subs: subs)
                    .onScrollWheel { delta in
                        if delta > 0 {
                            accumulatedScroll += delta
                            if accumulatedScroll > 15 {
                                accumulatedScroll = 0
                                dismissDrawer()
                            }
                        } else {
                            accumulatedScroll = 0
                        }
                    }
                    .offset(y: drawerVisible ? 0 : 500)
                    .opacity(drawerVisible ? 1 : 0)
            }

            if !isCurrentMonth && selectedDay == nil {
                currentMonthButton
                    .padding(.bottom, 16)
            }
        }
        .navigationTitle("Subscriptions")
        .onExitCommand { dismissDrawer() }
        .sheet(item: $editingItem) { item in
            NewScheduledSheet(editing: item)
        }
        .sheet(isPresented: $showingStats) {
            SubscriptionStatsSheet(subscriptions: subscriptions)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddSubscriptionSheet(dayComponents: addingOnDay ?? DateComponents())
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            HStack {
                HStack(spacing: 14) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .background(.quaternary, in: Circle())
                    }
                    .buttonStyle(.plain)

                    Text(monthLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .background(.quaternary, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                HStack(spacing: 6) {
                    Button { showingStats = true } label: {
                        Image(systemName: "chart.bar.xaxis.ascending")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Text(CurrencyFormatter.shared.format(monthlyTotal))
                .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)

            if let top = topCategory {
                HStack(spacing: 5) {
                    Circle()
                        .fill(AppTheme.accent(for: scheme))
                        .frame(width: 5, height: 5)
                    Text(top.name)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("•")
                        .foregroundStyle(.quaternary)
                    Text(CurrencyFormatter.shared.format(top.total))
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(.bottom, 10)
    }

    // MARK: - Calendar Grid

    private let weekdays = [
        (id: 0, label: "M"), (id: 1, label: "T"), (id: 2, label: "W"),
        (id: 3, label: "T"), (id: 4, label: "F"), (id: 5, label: "S"), (id: 6, label: "S")
    ]

    private var numberOfRows: Int {
        let totalCells = firstWeekdayOffset + daysInMonth.count
        return (totalCells + 6) / 7
    }

    private var calendarGrid: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(weekdays, id: \.id) { day in
                    Text(day.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)

            // Use a Grid that fills available height
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                let allCells = makeCellData()
                ForEach(0..<numberOfRows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<7, id: \.self) { col in
                            let index = row * 7 + col
                            if index < allCells.count, let dc = allCells[index] {
                                DayCellView(
                                    day: dc.day ?? 0,
                                    subscriptions: subscriptionsForDay(dc),
                                    spend: daySpend(dc),
                                    isToday: isToday(dc),
                                    isSelected: selectedDay == dc,
                                    scheme: scheme
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .onTapGesture {
                                    if selectedDay == dc {
                                        dismissDrawer()
                                    } else {
                                        selectedDay = dc
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                            drawerVisible = true
                                        }
                                    }
                                }
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func makeCellData() -> [DateComponents?] {
        var cells: [DateComponents?] = Array(repeating: nil, count: firstWeekdayOffset)
        cells.append(contentsOf: daysInMonth)
        let totalCells = numberOfRows * 7
        while cells.count < totalCells {
            cells.append(nil)
        }
        return cells
    }

    // MARK: - Selected Day Detail

    private func selectedDayDetail(day: DateComponents, subs: [ScheduledTransaction]) -> some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(.quaternary)
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 14)

            // Header
            HStack(alignment: .firstTextBaseline) {
                Text(dayTitle(day))
                    .font(.title3.weight(.semibold))
                Spacer()
                if !subs.isEmpty {
                    Text(CurrencyFormatter.shared.format(subs.reduce(Decimal.zero) { $0 + abs($1.amount) }))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AppTheme.accent(for: scheme))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Subscription list with swipe actions
            if !subs.isEmpty {
                List {
                    ForEach(subs) { sub in
                        HStack(spacing: 12) {
                            Image(systemName: sub.category?.icon ?? "arrow.triangle.2.circlepath")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Color(hex: sub.category?.colorHex ?? "FF9500"), in: RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(sub.title)
                                        .font(.body.weight(.medium))
                                    if !sub.isActive {
                                        Text("PAUSED")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.orange)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(.orange.opacity(0.15), in: Capsule())
                                    }
                                }
                                Text(sub.frequency.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(CurrencyFormatter.shared.format(abs(sub.amount)))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 4)
                        .opacity(sub.isActive ? 1 : 0.5)
                        .contentShape(Rectangle())
                        .onTapGesture { editingItem = sub }
                        .swipeActions(edge: .leading) {
                            Button {
                                editingItem = sub
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                withAnimation { context.delete(sub) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                withAnimation { sub.isActive.toggle() }
                            } label: {
                                Label(sub.isActive ? "Pause" : "Resume", systemImage: sub.isActive ? "pause.fill" : "play.fill")
                            }
                            .tint(sub.isActive ? .gray : .green)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: CGFloat(min(subs.count, 4)) * 56)
            } else {
                HStack {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundStyle(.tertiary)
                    Text("No subscriptions on this day")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }

            // Add button
            Button {
                addingOnDay = day
                showingAddSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                    Text("Add Subscription")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(AppTheme.accent(for: scheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.accent(for: scheme).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: -8)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Paused Section

    private var pausedSection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "pause.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Paused")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(pausedSubscriptions.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            List {
                ForEach(pausedSubscriptions) { sub in
                    HStack(spacing: 12) {
                        Image(systemName: sub.category?.icon ?? "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 28, height: 28)
                            .background(Color(hex: sub.category?.colorHex ?? "FF9500").opacity(0.5), in: RoundedRectangle(cornerRadius: 7))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(sub.title)
                                .font(.subheadline.weight(.medium))
                            Text(sub.frequency.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        Text(CurrencyFormatter.shared.format(abs(sub.amount)))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .opacity(0.6)
                    .padding(.vertical, 2)
                    .swipeActions(edge: .leading) {
                        Button {
                            withAnimation { sub.isActive = true }
                        } label: {
                            Label("Resume", systemImage: "play.fill")
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            withAnimation { context.delete(sub) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            editingItem = sub
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: CGFloat(min(pausedSubscriptions.count, 3)) * 48)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Current Month Button

    private var currentMonthButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                displayedMonth = Date()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "leaf.fill")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.accentGradient(for: scheme))
                Text("Current")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(AppTheme.accent(for: scheme).opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func isToday(_ dc: DateComponents) -> Bool {
        let now = Date()
        return dc.day == calendar.component(.day, from: now)
            && dc.month == calendar.component(.month, from: now)
            && dc.year == calendar.component(.year, from: now)
    }

    private func dismissDrawer() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            drawerVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            selectedDay = nil
        }
    }

    private func dayTitle(_ dc: DateComponents) -> String {
        guard let date = calendar.date(from: dc) else { return "Day \(dc.day ?? 0)" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: date)
    }
}

// MARK: - Day Cell

struct DayCellView: View {
    let day: Int
    let subscriptions: [ScheduledTransaction]
    let spend: Decimal
    let isToday: Bool
    let isSelected: Bool
    let scheme: ColorScheme

    private var hasSubscriptions: Bool { !subscriptions.isEmpty }

    private var warmTint: Color {
        if spend > 30 { return Color(red: 0.55, green: 0.35, blue: 0.18).opacity(0.35) }
        if spend > 10 { return Color(red: 0.55, green: 0.40, blue: 0.22).opacity(0.25) }
        if spend > 0 { return Color(red: 0.55, green: 0.45, blue: 0.28).opacity(0.15) }
        return .clear
    }

    private var iconSize: CGFloat {
        switch subscriptions.count {
        case 1: return 32
        case 2: return 24
        case 3: return 20
        default: return 18
        }
    }

    private var iconFontSize: CGFloat {
        switch subscriptions.count {
        case 1: return 14
        case 2: return 10
        case 3: return 9
        default: return 8
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasSubscriptions {
                Spacer(minLength: 2)
                HStack(spacing: subscriptions.count == 1 ? 0 : -4) {
                    ForEach(subscriptions.prefix(4)) { sub in
                        Image(systemName: sub.category?.icon ?? "arrow.triangle.2.circlepath")
                            .font(.system(size: iconFontSize))
                            .foregroundStyle(.white)
                            .frame(width: iconSize, height: iconSize)
                            .background(Color(hex: sub.category?.colorHex ?? "FF9500"), in: Circle())
                            .shadow(color: Color(hex: sub.category?.colorHex ?? "FF9500").opacity(0.4), radius: 3, y: 1)
                    }
                    if subscriptions.count > 4 {
                        Text("+\(subscriptions.count - 4)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .background(.quaternary, in: Circle())
                    }
                }
            }

            Spacer(minLength: 0)

            Text("\(day)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(isToday ? AppTheme.accent(for: scheme) : .secondary)
                .fontWeight(isToday ? .bold : .regular)
                .padding(.bottom, 3)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(scheme == .dark
                    ? (hasSubscriptions ? warmTint : AppTheme.darkCard.opacity(0.6))
                    : (hasSubscriptions ? warmTint : Color(.systemGray).opacity(0.06))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? AppTheme.accent(for: scheme).opacity(0.5)
                    : isToday ? AppTheme.accent(for: scheme).opacity(0.3)
                    : .clear,
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(color: .black.opacity(hasSubscriptions ? 0.06 : 0), radius: 3, y: 1)
    }
}

// MARK: - Add Subscription Sheet

struct AddSubscriptionSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    let dayComponents: DateComponents

    @State private var name = ""
    @State private var amount = ""
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var selectedCategory: Category?
    @State private var selectedAccount: Account?
    @State private var notes = ""

    private var expenseCategories: [Category] {
        categories.filter { !$0.isIncome }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("e.g. Netflix", text: $name)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("", text: $amount, prompt: Text("e.g. 9.99").foregroundStyle(.tertiary))
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }

                    Picker("Payment Schedule", selection: $frequency) {
                        ForEach(RecurrenceFrequency.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }

                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)

                    HStack {
                        Text("End Date")
                        Spacer()
                        Toggle("", isOn: $hasEndDate)
                            .labelsHidden()
                    }
                    if hasEndDate {
                        DatePicker("", selection: $endDate, displayedComponents: .date)
                    }
                }

                Section {
                    Picker(selection: $selectedCategory) {
                        Text("None").tag(nil as Category?)
                        ForEach(expenseCategories) { cat in
                            Label(cat.name, systemImage: cat.icon).tag(cat as Category?)
                        }
                    } label: {
                        Label("Category", systemImage: "tag")
                    }

                    Picker(selection: $selectedAccount) {
                        Text("No Account").tag(nil as Account?)
                        ForEach(accounts.filter { !$0.isArchived }) { acc in
                            HStack {
                                Image(systemName: acc.type.icon)
                                Text(acc.name)
                            }
                            .tag(acc as Account?)
                        }
                    } label: {
                        Label("Pay with", systemImage: "creditcard")
                    }
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...5)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Subscription")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(name.isEmpty || amount.isEmpty)
                }
            }
            .onAppear {
                if let date = Calendar.current.date(from: dayComponents) {
                    startDate = date
                }
            }
        }
        .macOSSheet(width: 560, height: 620)
    }

    private func save() {
        guard let value = Decimal(string: amount) else { return }
        let signed = -abs(value)

        let sub = ScheduledTransaction(
            amount: signed,
            title: name,
            frequency: frequency,
            nextDate: startDate,
            account: selectedAccount,
            category: selectedCategory,
            isSubscription: true
        )
        sub.notes = notes
        if hasEndDate { sub.endDate = endDate }
        context.insert(sub)
        dismiss()
    }
}

extension DateComponents: @retroactive Identifiable {
    public var id: String {
        "\(year ?? 0)-\(month ?? 0)-\(day ?? 0)"
    }
}

// MARK: - Stats Sheet

struct SubscriptionStatsSheet: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    let subscriptions: [ScheduledTransaction]

    private var monthlyTotal: Decimal {
        subscriptions.reduce(Decimal.zero) { $0 + $1.monthlyEquivalent }
    }

    private var yearlyTotal: Decimal {
        monthlyTotal * 12
    }

    private var byCategory: [(name: String, color: String, total: Decimal)] {
        let grouped = Dictionary(grouping: subscriptions) { $0.category?.name ?? "Other" }
        return grouped.map { (name: $0.key, color: $0.value.first?.category?.colorHex ?? "888888", total: $0.value.reduce(Decimal.zero) { $0 + $1.monthlyEquivalent }) }
            .sorted { $0.total > $1.total }
    }

    private var ranked: [ScheduledTransaction] {
        subscriptions.sorted { $0.monthlyEquivalent > $1.monthlyEquivalent }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Monthly")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(CurrencyFormatter.shared.format(monthlyTotal))
                                .font(.title2.bold().monospacedDigit())
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Yearly")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(CurrencyFormatter.shared.format(yearlyTotal))
                                .font(.title2.bold().monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("Total Spend", systemImage: "chart.bar.xaxis.ascending")
                }

                Section {
                    ForEach(byCategory, id: \.name) { cat in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: cat.color))
                                .frame(width: 10, height: 10)
                            Text(cat.name)
                                .font(.subheadline)
                            Spacer()
                            Text(CurrencyFormatter.shared.format(cat.total))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text("/mo")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Label("By Category", systemImage: "circle.grid.2x2")
                }

                Section {
                    ForEach(ranked) { sub in
                        HStack(spacing: 12) {
                            Image(systemName: sub.category?.icon ?? "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(Color(hex: sub.category?.colorHex ?? "FF9500"))
                                .frame(width: 24, height: 24)
                                .background(Color(hex: sub.category?.colorHex ?? "FF9500").opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(sub.title)
                                    .font(.subheadline)
                                Text(sub.frequency.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(CurrencyFormatter.shared.format(abs(sub.amount)))
                                    .font(.subheadline.monospacedDigit())
                                Text(CurrencyFormatter.shared.format(sub.monthlyEquivalent) + "/mo")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                } header: {
                    Label("Most Expensive", systemImage: "arrow.up.right")
                }
            }
            .premiumList()
            .navigationTitle("Subscription Stats")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .macOSSheet(width: 480, height: 560)
    }
}

// MARK: - Scroll Wheel Modifier

#if os(macOS)
struct ScrollWheelModifier: ViewModifier {
    let handler: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content.overlay(
            ScrollWheelView(handler: handler)
        )
    }
}

struct ScrollWheelView: NSViewRepresentable {
    let handler: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.handler = handler
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.handler = handler
    }
}

class ScrollWheelNSView: NSView {
    var handler: ((CGFloat) -> Void)?
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil // Let all clicks pass through to SwiftUI buttons beneath
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, self.window != nil else { return event }
            let loc = self.convert(event.locationInWindow, from: nil)
            if self.bounds.contains(loc) {
                self.handler?(event.scrollingDeltaY)
            }
            return event
        }
    }

    override func removeFromSuperview() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        super.removeFromSuperview()
    }
}

extension View {
    func onScrollWheel(perform handler: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollWheelModifier(handler: handler))
    }
}
#else
extension View {
    func onScrollWheel(perform handler: @escaping (CGFloat) -> Void) -> some View {
        self
    }
}
#endif
