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
    case dataHealth
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
    @State private var showingReorderAccounts = false
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
    @State private var showingNewTransaction = false
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
        .focusedSceneValue(\.showNewTransaction, $showingNewTransaction)
        .tutorialOverlay(tutorial)
        .onChange(of: tutorial.currentStepIndex) { _, _ in
            navigateForTutorialStep()
        }
        .onAppear {
            #if DEBUG
            DebugChecks.run()
            #endif
            Task { await ExchangeRateService.shared.refresh() }
            seedIfNeeded()
            if !MintLeafApp.isDevMode {
                BackupManager.performAutomaticBackup(context: context)
            }
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
        .onAppear {
            seedIfNeeded()
            Task { await ExchangeRateService.shared.refresh() }
        }
        #endif
    }

    #if os(macOS)
    private var notificationBadgeCount: Int {
        NotificationManager.shared.badgeCount(
            scheduled: scheduledItems,
            budgets: budgets,
            accounts: accounts
        )
    }

    private var sidebar: some View {
        ScrollViewReader { proxy in
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
                                .offset(x: 2, y: -2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
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
                        if accounts.filter({ !$0.isArchived }).count > 1 {
                            Button(action: { showingReorderAccounts = true }) {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Reorder accounts")
                        }
                        Button(action: { showingNewAccount = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(AppTheme.accent(for: scheme))
                        }
                    .buttonStyle(.plain)
                    .padding(.trailing, 10)
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
                    sidebarRow("Data Health", icon: "checkmark.shield", destination: .dataHealth)
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
        // Sidebar is a distinctly lighter panel than the true-black content,
        // so it reads as its own region (tonal contrast, no window transparency).
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                    .overlay(AppTheme.divider(for: scheme).opacity(0.5))
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent(for: scheme).opacity(0.5))
                    Text("Mint Leaf")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(AppTheme.sidebarBackground(for: scheme))
            }
        }
        .background(AppTheme.sidebarBackground(for: scheme))
        .toolbar {}
        .onChange(of: tutorial.currentStepIndex) { _, _ in
            scrollToTutorialStep(proxy: proxy)
        }
        }
        .sheet(isPresented: $showingNotifications) {
            NotificationCenterView()
        }
        .sheet(isPresented: $showingNewAccount) {
            NewAccountSheet()
        }
        .sheet(isPresented: $showingNewTransaction) {
            if let currentAccount = currentAccountForNewTransaction {
                EditTransactionSheet(account: currentAccount)
            } else if let firstAccount = accounts.first(where: { !$0.isArchived }) {
                EditTransactionSheet(account: firstAccount)
            }
        }
        .sheet(item: $editingAccount) { account in
            NewAccountSheet(account: account)
        }
        .sheet(isPresented: $showingReorderAccounts) {
            AccountReorderSheet()
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

    private func isTutorialHighlighted(_ destination: SidebarDestination) -> Bool {
        guard tutorial.isActive, let nav = tutorial.currentStep?.navigation else { return false }
        let tutorialDest: SidebarDestination? = switch nav {
        case "overview": .overview
        case "search": .search
        case "inbox": .inbox
        case "budgets": .budgets
        case "trends": .trends
        case "insights": .insights
        case "networth": .netWorth
        case "reports": .reports
        case "goals": .goals
        case "forecast": .forecast
        case "tags": .tags
        case "scheduled": .scheduled
        case "rules": .rules
        default: nil
        }
        return tutorialDest == destination
    }

    private func sidebarRow(_ title: String, icon: String, destination: SidebarDestination) -> some View {
        let isSelected = selection == destination
        let isTutorial = isTutorialHighlighted(destination)
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
                    .fill(isSelected ? AppTheme.accent(for: scheme).opacity(isTutorial ? 0.25 : 0.12) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isTutorial ? AppTheme.accent(for: scheme)
                        : isSelected ? AppTheme.accent(for: scheme).opacity(0.4)
                        : .clear,
                        lineWidth: isTutorial ? 2.5 : 1
                    )
            )
            .shadow(color: isTutorial ? AppTheme.accent(for: scheme).opacity(0.4) : .clear, radius: 6, x: 0, y: 0)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? AppTheme.accent(for: scheme) : .primary)
        .id(destination)
        .animation(.easeInOut(duration: 0.3), value: isTutorial)
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
            DashboardView(onReviewDataHealth: { selection = .dataHealth })
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
            NetWorthView()
        case .reports:
            ReportsView()
        case .scheduled:
            ScheduledListView()
        case .subscriptions:
            SubscriptionCalendarView()
        case .bills:
            ScheduledListView(filterMode: .bills)
        case .goals:
            GoalsView()
        case .forecast:
            ForecastView()
        case .budgets:
            BudgetListView()
        case .rules:
            RulesListView()
        case .tags:
            TagsView()
        case .importExport:
            ImportExportView()
        case .dataHealth:
            DataIntegrityView()
        }
    }
    #endif

    private func seedIfNeeded() {
        if categories.isEmpty {
            DefaultCategories.seed(context: context)
        }
        deduplicateTags()
        recalculateBalancesIfNeeded()
    }

    private func recalculateBalancesIfNeeded() {
        let key = "balancesCacheMigrated"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        for account in accounts {
            account.recalculateBalance()
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    private func deduplicateTags() {
        var descriptor = FetchDescriptor<Tag>()
        descriptor.sortBy = [SortDescriptor(\Tag.sortOrder)]
        let allTags = (try? context.fetch(descriptor)) ?? []
        var kept: [String: Tag] = [:]
        for tag in allTags {
            if let existing = kept[tag.name] {
                // Merge transactions from duplicate into the kept tag
                for txn in tag.transactions where !existing.transactions.contains(where: { $0.id == txn.id }) {
                    existing.transactions.append(txn)
                }
                context.delete(tag)
            } else {
                kept[tag.name] = tag
            }
        }
    }

    #if os(macOS)
    private func tutorialDestination(for nav: String) -> SidebarDestination? {
        switch nav {
        case "overview": .overview
        case "search": .search
        case "inbox": .inbox
        case "budgets": .budgets
        case "trends": .trends
        case "insights": .insights
        case "networth": .netWorth
        case "reports": .reports
        case "goals": .goals
        case "forecast": .forecast
        case "tags": .tags
        case "scheduled": .scheduled
        case "rules": .rules
        default: nil
        }
    }

    private func navigateForTutorialStep() {
        guard let nav = tutorial.currentStep?.navigation else { return }
        guard let dest = tutorialDestination(for: nav) else { return }

        // Expand collapsed sections so the target row is visible
        expandSectionForTutorial(dest)

        withAnimation { selection = dest }
    }

    private func expandSectionForTutorial(_ dest: SidebarDestination) {
        switch dest {
        case .trends, .insights, .netWorth, .reports:
            if analyticsCollapsed { withAnimation { analyticsCollapsed = false } }
        case .scheduled, .subscriptions, .bills:
            if scheduledCollapsed { withAnimation { scheduledCollapsed = false } }
        case .goals, .forecast:
            if planningCollapsed { withAnimation { planningCollapsed = false } }
        case .budgets, .rules, .tags, .importExport:
            if toolsCollapsed { withAnimation { toolsCollapsed = false } }
        default:
            break
        }
    }

    private var currentAccountForNewTransaction: Account? {
        if case .account(let acct) = selection { return acct }
        return nil
    }

    private func scrollToTutorialStep(proxy: ScrollViewProxy) {
        guard tutorial.isActive, let nav = tutorial.currentStep?.navigation else { return }
        guard let dest = tutorialDestination(for: nav) else { return }

        expandSectionForTutorial(dest)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(dest, anchor: .center)
            }
        }
    }
    #endif
}
