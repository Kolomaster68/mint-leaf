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
    @AppStorage("sidebarVisible") private var showSidebar = true
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
        // A plain split, not NavigationSplitView: AppKit paints its sidebar column
        // with its own material, which no SwiftUI background can sit on top of.
        // Owning the layout is the only way to get one flat surface.
        HStack(spacing: 0) {
            if showSidebar {
                GeometryReader { geo in
                    sidebar
                        .scaleEffect(textScale, anchor: .topLeading)
                        .frame(width: geo.size.width / textScale, height: geo.size.height / textScale, alignment: .topLeading)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                }
                .frame(width: 240 * textScale)
                .transition(.move(edge: .leading))
                Divider()
            }
            NavigationStack {
                GeometryReader { geo in
                    detail
                        .modifier(HighContrastModifier())
                        .scaleEffect(textScale, anchor: .topLeading)
                        .frame(width: geo.size.width / textScale, height: geo.size.height / textScale, alignment: .topLeading)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(AppTheme.surfaceBackground(for: scheme).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showSidebar.toggle() }
                } label: {
                    Image(systemName: "sidebar.leading")
                }
                .help("Hide or show the sidebar")
                .keyboardShortcut("\\", modifiers: .command)
            }
        }
        .focusedSceneValue(\.sidebarSelection, $selection)
        .focusedSceneValue(\.showNewAccount, $showingNewAccount)
        .focusedSceneValue(\.showNotifications, $showingNotifications)
        .focusedSceneValue(\.showNewTransaction, $showingNewTransaction)
        .tutorialOverlay(tutorial)
        .onChange(of: tutorial.currentStepIndex) { _, _ in
            navigateForTutorialStep()
        }
        .onAppear {
            guard !MintLeafApp.isRunningTests else { return }
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
        // 630P1-Test-Scheduled-Transactions
        .onAppear {
            guard !MintLeafApp.isRunningTests else { return }
            Task { await ExchangeRateService.shared.refresh() }
            seedIfNeeded()
            ScheduledTransactionProcessor.processOverdue(context: context)
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
        List(selection: $selection) {
            HStack {
                sidebarLabel("Overview", icon: "square.grid.2x2", destination: .overview)
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
            .tag(SidebarDestination.overview)
            .id(SidebarDestination.overview)
            .listRowSeparator(.hidden)

            sidebarRow("Search", icon: "magnifyingglass", destination: .search)
                .listRowSeparator(.hidden)

            sidebarRow("Inbox", icon: "tray", destination: .inbox)
                .listRowSeparator(.hidden)

            Section(isExpanded: expanded($accountsCollapsed)) {
                    ForEach(accounts.filter { !$0.isArchived }) { account in
                        sidebarAccountRow(account)
                            .listRowSeparator(.hidden)
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
            } header: {
                VStack(alignment: .leading, spacing: 4) {
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
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)
                }
            }

            if !accountsCollapsed && accounts.contains(where: { $0.isArchived }) {
                Section {
                    ForEach(accounts.filter { $0.isArchived }) { account in
                        sidebarAccountRow(account)
                            .listRowSeparator(.hidden)
                            .opacity(0.6)
                    }
                } header: {
                    Text("Archived")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Analytics", isExpanded: expanded($analyticsCollapsed)) {
                    sidebarRow("Trends", icon: "chart.line.uptrend.xyaxis", destination: .trends)
                    sidebarRow("Insights", icon: "lightbulb", destination: .insights)
                    sidebarRow("Net Worth", icon: "banknote", destination: .netWorth)
                    sidebarRow("Reports", icon: "doc.text.magnifyingglass", destination: .reports)
            }
            .listRowSeparator(.hidden)

            Section("Scheduled", isExpanded: expanded($scheduledCollapsed)) {
                    sidebarRow("Overview", icon: "list.bullet", destination: .scheduled)
                    sidebarRow("Subscriptions", icon: "arrow.triangle.2.circlepath", destination: .subscriptions)
                    sidebarRow("Bills", icon: "creditcard", destination: .bills)
            }
            .listRowSeparator(.hidden)

            Section("Planning", isExpanded: expanded($planningCollapsed)) {
                    sidebarRow("Goals", icon: "target", destination: .goals)
                    sidebarRow("Forecast", icon: "chart.line.flattrend.xyaxis", destination: .forecast)
            }
            .listRowSeparator(.hidden)

            Section("Tools", isExpanded: expanded($toolsCollapsed)) {
                    sidebarRow("Budgets", icon: "chart.pie", destination: .budgets)
                    sidebarRow("Rules", icon: "wand.and.rays", destination: .rules)
                    sidebarRow("Tags", icon: "tag", destination: .tags)
                    sidebarRow("Import / Export", icon: "square.and.arrow.up.on.square", destination: .importExport)
                    sidebarRow("Data Health", icon: "checkmark.shield", destination: .dataHealth)
            }
            .listRowSeparator(.hidden)

            Spacer()
                .frame(height: 24)
                .listRowSeparator(.hidden)

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

        }
        // Standard system sidebar — no hand-painted background, so it inherits
        // whatever chrome the OS ships (flat in Golden Gate, vibrant before it).
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
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
            }
        }
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

    /// Inverts a stored "collapsed" flag into the "expanded" binding native sections want.
    private func expanded(_ collapsed: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { !collapsed.wrappedValue }, set: { collapsed.wrappedValue = !$0 })
    }

    /// The label only — used where the row itself must carry the tag (e.g. Overview,
    /// which shares its row with the notifications bell).
    private func sidebarLabel(_ title: String, icon: String, destination: SidebarDestination) -> some View {
        let isSelected = selection == destination
        return Label {
            Text(title)
        } icon: {
            if isSelected {
                Image(systemName: icon)
            } else {
                Image(systemName: icon)
                    .foregroundStyle(AppTheme.accent(for: scheme))
            }
        }
    }

    /// A plain tagged label — the system draws the selection edge-to-edge.
    private func sidebarRow(_ title: String, icon: String, destination: SidebarDestination) -> some View {
        let isTutorial = isTutorialHighlighted(destination)
        let isSelected = selection == destination
        return Label {
            Text(title)
        } icon: {
            // Selected rows inherit the system's label colour so text and icon
            // stay legible against the selection fill.
            if isSelected {
                Image(systemName: icon)
            } else {
                Image(systemName: icon)
                    .foregroundStyle(AppTheme.accent(for: scheme))
            }
        }
        .tag(destination)
        .id(destination)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isTutorial ? AppTheme.accent(for: scheme) : .clear, lineWidth: 2.5)
        )
        .animation(.easeInOut(duration: 0.3), value: isTutorial)
    }

    private func sidebarAccountRow(_ account: Account) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(account.name)
                Text(CurrencyFormatter.shared.format(account.currentBalance, currency: account.currency))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
        } icon: {
            if selection == .account(account) {
                Image(systemName: account.type.icon)
            } else {
                Image(systemName: account.type.icon)
                    .foregroundStyle(Color(hex: account.colorHex))
            }
        }
        .tag(SidebarDestination.account(account))
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
