import SwiftUI
import SwiftData

@main
struct MintLeafApp: App {
    let container: ModelContainer

    /// The single in-memory container created under XCTest; tests reuse it (one
    /// container per process — a second one traps SwiftData).
    nonisolated(unsafe) static var testContainer: ModelContainer?
    @AppStorage("appAppearance") private var appearance: String = AppAppearance.system.rawValue
    @AppStorage("textSizeOffset") private var textSizeOffset: Int = 0
    @AppStorage("highContrastMode") private var highContrastMode = false
    @AppStorage("reduceMotion") private var reduceMotion = false
    @AppStorage("showMenuBarExtra") private var showMenuBar = true

    static let isDevMode = ProcessInfo.processInfo.arguments.contains("-useSampleData")

    /// True when the host app is launched by the XCTest runner — skip launch side-effects.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        let schema = Schema([
            Account.self,
            Transaction.self,
            Category.self,
            Budget.self,
            BudgetItem.self,
            ScheduledTransaction.self,
            CategoryRule.self,
            MerchantAlias.self,
            Goal.self,
            Tag.self,
        ])
        // Under XCTest use one in-memory container and share it with the tests.
        if Self.isRunningTests {
            container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
            Self.testContainer = container
            return
        }
        let storeName = Self.isDevMode ? "MintLeaf-dev" : "MintLeaf"
        let config = ModelConfiguration(
            storeName,
            schema: schema,
            cloudKitDatabase: .none
        )
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Migration failed — back up the store before resetting
            let storeURL = config.url
            let backupURL = storeURL.deletingLastPathComponent()
                .appendingPathComponent("MintLeaf-backup-\(Int(Date().timeIntervalSince1970)).store")
            try? FileManager.default.copyItem(at: storeURL, to: backupURL)

            let related = [
                storeURL,
                storeURL.appendingPathExtension("shm"),
                storeURL.appendingPathExtension("wal"),
            ]
            for url in related {
                try? FileManager.default.removeItem(at: url)
            }
            do {
                container = try ModelContainer(for: schema, configurations: [config])
                print("⚠️ SwiftData store was reset due to migration error. Backup saved to \(backupURL.path)")
            } catch {
                fatalError("Failed to configure SwiftData after reset: \(error)")
            }
        }
    }

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appearance) ?? .system
    }

    private var textScale: CGFloat {
        switch textSizeOffset {
        case -2: return 0.85
        case -1: return 0.92
        case 0: return 1.0
        case 1: return 1.1
        case 2: return 1.2
        default: return 1.0
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .preferredColorScheme(selectedAppearance.colorScheme)
                .environment(\.appTextScale, textScale)
                .environment(\.appHighContrast, highContrastMode)
                .environment(\.appReduceMotion, reduceMotion)
                .transaction {
                    if reduceMotion { $0.animation = nil }
                }
                #if os(macOS)
                .onAppear { restoreAppIcon() }
                .overlay(alignment: .topTrailing) {
                    if Self.isDevMode {
                        Text("DEV")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.red, in: Capsule())
                            .padding(8)
                    }
                }
                #endif
        }
        .modelContainer(container)
        .commands { AppCommands() }
        #if os(macOS)
        Settings {
            SettingsView()
                .preferredColorScheme(selectedAppearance.colorScheme)
                .environment(\.appTextScale, textScale)
                .environment(\.appHighContrast, highContrastMode)
        }
        .modelContainer(container)

        MenuBarExtra("MintLeaf", systemImage: "leaf.fill", isInserted: $showMenuBar) {
            MenuBarView()
                .preferredColorScheme(selectedAppearance.colorScheme)
                .modelContainer(container)
        }
        .menuBarExtraStyle(.window)
        #endif
    }

    #if os(macOS)
    private func restoreAppIcon() {
        let style = UserDefaults.standard.string(forKey: "appIconStyle") ?? "system"
        switch style {
        case "light":
            NSApplication.shared.applicationIconImage = renderLeafIcon(isDark: false)
        case "dark":
            NSApplication.shared.applicationIconImage = renderLeafIcon(isDark: true)
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
    #endif
}

#if os(macOS)
// MARK: - Menu bar glance

/// Payday figure, the next few bills and a quick-add, without opening the main window.
/// Respects the app lock: figures stay hidden until Touch ID passes.
struct MenuBarView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow
    @AppStorage("biometricLockEnabled") private var biometricEnabled = false
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \ScheduledTransaction.nextDate) private var scheduled: [ScheduledTransaction]
    @Query(sort: \CategoryRule.sortOrder) private var rules: [CategoryRule]
    @Query private var aliases: [MerchantAlias]

    @State private var unlocked = false
    @State private var title = ""
    @State private var amount = ""
    @State private var isIncome = false
    @State private var accountID: UUID?
    @State private var added: String?

    private var active: [Account] { accounts.filter { !$0.isArchived } }

    var body: some View {
        Group {
            if biometricEnabled && !unlocked {
                LockScreenView(isUnlocked: $unlocked)
                    .frame(height: 300)
            } else {
                content
            }
        }
        .frame(width: 300)
    }

    private var content: some View {
        let p = CashflowForecaster.untilPayday(accounts: accounts, scheduled: scheduled)
        let bills = scheduled.filter { $0.isActive && $0.amount < 0 }.prefix(3)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.payday == nil ? "Left until month end" : "Left until payday")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.accent(for: scheme))
                Text(CurrencyFormatter.shared.format(p.left))
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(p.left < 0 ? AppTheme.expense : .primary)
                if let payday = p.payday {
                    Text("Payday \(payday.formatted(.dateTime.weekday(.wide).day().month()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !bills.isEmpty {
                Divider()
                ForEach(Array(bills)) { bill in
                    HStack {
                        Text(bill.title).lineLimit(1)
                        Spacer()
                        Text(bill.nextDate, format: .dateTime.day().month(.abbreviated))
                            .foregroundStyle(.secondary)
                        Text(CurrencyFormatter.shared.format(abs(bill.convertedAmount)))
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
            }

            Divider()
            Text("Quick add").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Picker("", selection: $isIncome) {
                Text("Spent").tag(false)
                Text("Received").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack {
                TextField("What for?", text: $title)
                TextField("0.00", text: $amount)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
            }
            .textFieldStyle(.roundedBorder)
            .onSubmit(add)
            HStack {
                Picker("", selection: $accountID) {
                    ForEach(active) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden()
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.isEmpty || Decimal(userInput: amount) == nil)
            }
            if let added {
                Text(added).font(.caption).foregroundStyle(AppTheme.accent(for: scheme))
            }

            Divider()
            HStack {
                Button("Open MintLeaf") { openMain() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(14)
        .onAppear { if accountID == nil { accountID = active.first?.id } }
    }

    private func add() {
        guard !title.isEmpty, let value = Decimal(userInput: amount),
              let account = active.first(where: { $0.id == accountID }) else { return }
        let signed = isIncome ? abs(value) : -abs(value)
        let txn = Transaction(amount: signed, title: title, account: account)
        context.insert(txn)
        RulesEngine.applyRules(to: txn, rules: rules, aliases: aliases)
        account.adjustBalance(by: signed)
        context.saveOrLog()
        added = "Added \(title) to \(account.name)"
        title = ""
        amount = ""
    }

    private func openMain() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}
#endif

