import SwiftUI
import SwiftData

enum SidebarDestination: Hashable {
    case overview
    case account(Account)
    case inbox
    case budgets
    case trends
    case insights
    case scheduled
    case rules
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appTextScale) private var textScale
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query private var categories: [Category]
    @State private var selection: SidebarDestination? = .overview
    @State private var showingNewAccount = false
    @State private var editingAccount: Account?
    @State private var accountToDelete: Account?
    @AppStorage("biometricLockEnabled") private var biometricEnabled = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("sidebarAccountsCollapsed") private var accountsCollapsed = false
    @AppStorage("sidebarToolsCollapsed") private var toolsCollapsed = false
    @AppStorage("shouldStartTutorial") private var shouldStartTutorial = false
    @State private var isUnlocked = false
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
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
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
        .tutorialOverlay(tutorial)
        .onChange(of: tutorial.currentStepIndex) { _, _ in
            navigateForTutorialStep()
        }
        .onAppear {
            seedIfNeeded()
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
    private var sidebar: some View {
        List {
            sidebarRow("Overview", icon: "square.grid.2x2", destination: .overview)
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
                if !toolsCollapsed {
                    sidebarRow("Inbox", icon: "tray", destination: .inbox)
                    sidebarRow("Budgets", icon: "chart.pie", destination: .budgets)
                    sidebarRow("Trends", icon: "chart.line.uptrend.xyaxis", destination: .trends)
                    sidebarRow("Insights", icon: "lightbulb", destination: .insights)
                    sidebarRow("Scheduled", icon: "clock.arrow.circlepath", destination: .scheduled)
                    sidebarRow("Rules", icon: "wand.and.rays", destination: .rules)
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
        .background(AppTheme.sidebarBackground(for: scheme))
        .toolbar {}
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
        case .account(let account):
            TransactionsView(account: account)
        case .inbox:
            TransactionInboxView()
        case .budgets:
            BudgetListView()
        case .trends:
            TrendsView()
        case .insights:
            InsightsView()
        case .scheduled:
            ScheduledListView()
        case .rules:
            RulesListView()
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
