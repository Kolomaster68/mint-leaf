import SwiftUI
import SwiftData

enum SidebarDestination: Hashable {
    case overview
    case search
    case account(Account)
    case inbox
    case trends
    case insights
    case netWorth
    case reports
    case scheduled
    case subscriptions
    case bills
    case goals
    case forecast
    case budgets
    case rules
    case tags
    case importExport
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appTextScale) private var textScale
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query private var categories: [Category]
    @Query(sort: \ScheduledTransaction.nextDate) private var scheduledItems: [ScheduledTransaction]
    @Query(sort: \Budget.startDate) private var budgets: [Budget]
    @State private var selection: SidebarDestination? = .overview
    @State private var showingNewAccount = false
    @State private var editingAccount: Account?
    @State private var accountToDelete: Account?
    @AppStorage("biometricLockEnabled") private var biometricEnabled = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("sidebarAccountsCollapsed") private var accountsCollapsed = false
    @AppStorage("sidebarAnalyticsCollapsed") private var analyticsCollapsed = false
    @AppStorage("sidebarScheduledCollapsed") private var scheduledCollapsed = false
    @AppStorage("sidebarPlanningCollapsed") private var planningCollapsed = false
    @AppStorage("sidebarToolsCollapsed") private var toolsCollapsed = false
    @AppStorage("shouldStartTutorial") private var shouldStartTutorial = false
    @State private var isUnlocked = false
    @State private var showingNotifications = false
    @State private var tutorial = TutorialEngine.shared

    var body: some View {
        if !hasCompletedOnboarding {
            WelcomeView()
        } else if biometricEnabled && !isUnlocked {
            LockScreenView(isUnlocked: $isUnlocked)
        } else {
            mainContent
                .onAppear { isUnlocked = true }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        #if os(macOS)
        NavigationSplitView {
            GeometryReader { geo in
                sidebar
                    .scaleEffect(textScale, anchor: .topLeading)
                    .frame(width: geo.size.width / textScale, height: geo.size.height / textScale, alignment: .topLeading)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240 * textScale)
        } detail: {
            GeometryReader { geo in
                detail
                    .modifier(HighContrastModifier())
                    .scaleEffect(textScale, anchor: .topLeading)
                    .frame(width: geo.size.width / textScale, height: geo.size.height / textScale, alignment: .topLeading)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .focusedSceneValue(\.sidebarSelection, $selection)
        .focusedSceneValue(\.showNewAccount, $showingNewAccount)
        .focusedSceneValue(\.showNotifications, $showingNotifications)
        .tutorialOverlay(tutorial)
        .onChange(of: tutorial.currentStepIndex) { _, _ in
            navigateForTutorialStep()
        }
        .onAppear {
            seedIfNeeded()
            ScheduledTransactionProcessor.processOverdue(context: context)
            if shouldStartTutorial {
                shouldStartTutorial = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation { tutorial.start(TutorialLibrary.welcomeTour) }
                    navigateForTutorialStep()
                }
            }
        }
        #else
        TabView {
            NavigationStack {
                AccountsListView()
            }
            .tabItem { Label("Accounts", systemImage: "building.columns") }

            NavigationStack {
                TransactionInboxView()
            }
            .tabItem { Label("Inbox", systemImage: "tray") }

            NavigationStack {
                BudgetListView()
            }
            .tabItem { Label("Budgets", systemImage: "chart.pie") }

            NavigationStack {
                TrendsView()
            }
            .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }

            NavigationStack {
                ScheduledListView()
            }
            .tabItem { Label("Scheduled", systemImage: "clock.arrow.circlepath") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gear") }
        }
        .onAppear(perform: seedIfNeeded)
        #endif
    }

    #if os(macOS)
    @AppStorage("dismissedNotifications") private var dismissedNotifData: Data = Data()

    private var notificationBadgeCount: Int {
        let dismissed = (try? JSONDecoder().decode(Set<String>.self, from: dismissedNotifData)) ?? []
        var count = 0
        let today = Date()
        // Overdue or due within 3 days
        for item in scheduledItems where item.isActive {
            if item.nextDate <= today && !dismissed.contains("overdue-\(item.title)") { count += 1 }
            else if item.nextDate <= Calendar.current.date(byAdding: .day, value: 3, to: today) ?? today
                        && !dismissed.contains("due-soon-\(item.title)") { count += 1 }
        }

        // Budget items over 80%
        for budget in budgets {
            for item in budget.items {
                guard let category = item.category else { continue }
                if item.progress >= 1.0 && !dismissed.contains("budget-exceeded-\(category.name)") { count += 1 }
                else if item.progress >= 0.8 && !dismissed.contains("budget-warning-\(category.name)") { count += 1 }
            }
        }

        // Negative non-credit-card accounts
        for account in accounts where !account.isArchived && account.type != .creditCard {
            if account.currentBalance < 0 && !dismissed.contains("negative-\(account.name)") { count += 1 }
        }

        return count
    }

    private var sidebar: some View {
        List {
            HStack {
                sidebarRow("Overview", icon: "square.grid.2x2", destination: .overview)
                Spacer()
                Button { showingNotifications = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                        if notificationBadgeCount > 0 {
                            Text("\(notificationBadgeCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 14, minHeight: 14)
                                .background(.red, in: Circle())
                                .offset(x: 4, y: -4)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            sidebarRow("Search", icon: "magnifyingglass", destination: .search)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            sidebarRow("Inbox", icon: "tray", destination: .inbox)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            Section {
                if !accountsCollapsed {
                    ForEach(accounts.filter { !$0.isArchived }) { account in
                        sidebarAccountRow(account)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .leading) {
                                Button {
                                    editingAccount = account
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    accountToDelete = account
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { accountsCollapsed.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Accounts")
                                    .font(.headline)
                                Image(systemName: accountsCollapsed ? "chevron.right" : "chevron.down")
                                    .font(.caption.bold())
                            }
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button(action: { showingNewAccount = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(AppTheme.accent(for: scheme))
                        }
                    .buttonStyle(.plain)
                }
                    Text(CurrencyFormatter.shared.format(accounts.filter { !$0.isArchived }.reduce(Decimal.zero) { $0 + $1.currentBalance }))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if !accountsCollapsed && accounts.contains(where: { $0.isArchived }) {
                Section {
                    ForEach(accounts.filter { $0.isArchived }) { account in
                        sidebarAccountRow(account)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .opacity(0.6)
                    }
                } header: {
                    Text("Archived")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if !analyticsCollapsed {
                    sidebarRow("Trends", icon: "chart.line.uptrend.xyaxis", destination: .trends)
                    sidebarRow("Insights", icon: "lightbulb", destination: .insights)
                    sidebarRow("Net Worth", icon: "banknote", destination: .netWorth)
                    sidebarRow("Reports", icon: "doc.text.magnifyingglass", destination: .reports)
                }
            } header: {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { analyticsCollapsed.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text("Analytics")
                            .font(.headline)
                        Image(systemName: analyticsCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section {
                if !scheduledCollapsed {
                    sidebarRow("Overview", icon: "list.bullet", destination: .scheduled)
                    sidebarRow("Subscriptions", icon: "arrow.triangle.2.circlepath", destination: .subscriptions)
                    sidebarRow("Bills", icon: "creditcard", destination: .bills)
                }
            } header: {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { scheduledCollapsed.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text("Scheduled")
                            .font(.headline)
                        Image(systemName: scheduledCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section {
                if !planningCollapsed {
                    sidebarRow("Goals", icon: "target", destination: .goals)
                    sidebarRow("Forecast", icon: "chart.line.flattrend.xyaxis", destination: .forecast)
                }
            } header: {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { planningCollapsed.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text("Planning")
                            .font(.headline)
                        Image(systemName: planningCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section {
                if !toolsCollapsed {
                    sidebarRow("Budgets", icon: "chart.pie", destination: .budgets)
                    sidebarRow("Rules", icon: "wand.and.rays", destination: .rules)
                    sidebarRow("Tags", icon: "tag", destination: .tags)
                    sidebarRow("Import / Export", icon: "square.and.arrow.up.on.square", destination: .importExport)
                }
            } header: {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { toolsCollapsed.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text("Tools")
                            .font(.headline)
                        Image(systemName: toolsCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Spacer()
                .frame(height: 24)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            Section {
                SettingsLink {
                    HStack(spacing: 8) {
                        Image(systemName: "gear")
                            .font(.body)
                            .frame(width: 20)
                        Text("Settings")
                            .font(.body)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(AppTheme.accent(for: scheme).opacity(0.12))
                Text("Mint Leaf")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.quaternary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(AppTheme.sidebarBackground(for: scheme))
        }
        .background(AppTheme.sidebarBackground(for: scheme))
        .toolbar {}
        .sheet(isPresented: $showingNotifications) {
            NotificationCenterView()
        }
        .sheet(isPresented: $showingNewAccount) {
            NewAccountSheet()
        }
        .sheet(item: $editingAccount) { account in
            NewAccountSheet(account: account)
        }
        .alert("Delete Account?", isPresented: .init(
            get: { accountToDelete != nil },
            set: { if !$0 { accountToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { accountToDelete = nil }
            Button("Delete", role: .destructive) {
                if let account = accountToDelete {
                    if case .account(let sel) = selection, sel.id == account.id {
                        selection = .overview
                    }
                    context.delete(account)
                    accountToDelete = nil
                }
            }
        } message: {
            Text("This will permanently delete \"\(accountToDelete?.name ?? "")\" and all its transactions. This cannot be undone.")
        }
    }

    private func sidebarRow(_ title: String, icon: String, destination: SidebarDestination) -> some View {
        let isSelected = selection == destination
        return Button {
            selection = destination
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                    .frame(width: 20)
                Text(title)
                    .font(.body)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? AppTheme.accent(for: scheme).opacity(0.12) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? AppTheme.accent(for: scheme).opacity(0.4) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? AppTheme.accent(for: scheme) : .primary)
    }

    private func sidebarAccountRow(_ account: Account) -> some View {
        let isSelected: Bool = {
            if case .account(let sel) = selection { return sel.id == account.id }
            return false
        }()

        return Button {
            selection = .account(account)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: account.type.icon)
                    .font(.caption)
                    .foregroundStyle(Color(hex: account.colorHex))
                    .frame(width: 22, height: 22)
                    .background(Color(hex: account.colorHex).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.name)
                        .font(.body)
                    Text(CurrencyFormatter.shared.format(account.currentBalance, currency: account.currency))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? AppTheme.accent(for: scheme).opacity(0.12) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? AppTheme.accent(for: scheme).opacity(0.4) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                editingAccount = account
            } label: {
                Label("Edit Account", systemImage: "pencil")
            }
            Button {
                account.isArchived = true
                if case .account(let sel) = selection, sel.id == account.id {
                    selection = .overview
                }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            Divider()
            Button(role: .destructive) {
                accountToDelete = account
            } label: {
                Label("Delete Account", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .overview, .none:
            DashboardView()
        case .search:
            SearchView()
        case .account(let account):
            TransactionsView(account: account)
        case .inbox:
            TransactionInboxView()
        case .trends:
            TrendsView()
        case .insights:
            InsightsView()
        case .netWorth:
            ComingSoonView(title: "Net Worth", icon: "banknote", description: "Track your total net worth across all accounts over time.")
        case .reports:
            ComingSoonView(title: "Reports", icon: "doc.text.magnifyingglass", description: "Generate monthly and yearly spending summaries you can export.")
        case .scheduled:
            ScheduledListView()
        case .subscriptions:
            SubscriptionCalendarView()
        case .bills:
            ScheduledListView(filterMode: .bills)
        case .goals:
            ComingSoonView(title: "Goals", icon: "target", description: "Set savings goals and track your progress towards them.")
        case .forecast:
            ComingSoonView(title: "Forecast", icon: "chart.line.flattrend.xyaxis", description: "See projected balances based on your scheduled transactions.")
        case .budgets:
            BudgetListView()
        case .rules:
            RulesListView()
        case .tags:
            ComingSoonView(title: "Tags", icon: "tag", description: "Create custom tags to organise transactions across categories.")
        case .importExport:
            ImportExportView()
        }
    }
    #endif

    private func seedIfNeeded() {
        if categories.isEmpty {
            DefaultCategories.seed(context: context)
        }
    }

    #if os(macOS)
    private func navigateForTutorialStep() {
        guard let nav = tutorial.currentStep?.navigation else { return }
        let dest: SidebarDestination? = switch nav {
        case "overview": .overview
        case "inbox": .inbox
        case "budgets": .budgets
        case "trends": .trends
        case "insights": .insights
        case "scheduled": .scheduled
        case "rules": .rules
        default: nil
        }
        if let dest { withAnimation { selection = dest } }
    }
    #endif
}
