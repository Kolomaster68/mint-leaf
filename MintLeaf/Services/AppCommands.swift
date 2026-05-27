import SwiftUI

// MARK: - Focused Values

struct SidebarSelectionKey: FocusedValueKey {
    typealias Value = Binding<SidebarDestination?>
}

struct ShowNewAccountKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct ShowNotificationsKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct ShowNewTransactionKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var sidebarSelection: Binding<SidebarDestination?>? {
        get { self[SidebarSelectionKey.self] }
        set { self[SidebarSelectionKey.self] = newValue }
    }

    var showNewAccount: Binding<Bool>? {
        get { self[ShowNewAccountKey.self] }
        set { self[ShowNewAccountKey.self] = newValue }
    }

    var showNotifications: Binding<Bool>? {
        get { self[ShowNotificationsKey.self] }
        set { self[ShowNotificationsKey.self] = newValue }
    }

    var showNewTransaction: Binding<Bool>? {
        get { self[ShowNewTransactionKey.self] }
        set { self[ShowNewTransactionKey.self] = newValue }
    }
}

// MARK: - Shortcut Definitions

struct KeyboardShortcutInfo: Identifiable {
    let id = UUID()
    let label: String
    let key: String
    let modifiers: String
    let section: ShortcutSection

    enum ShortcutSection: String, CaseIterable {
        case general = "General"
        case navigation = "Navigation"
    }
}

enum ShortcutReference {
    static let all: [KeyboardShortcutInfo] = [
        // General
        KeyboardShortcutInfo(label: "New Transaction", key: "T", modifiers: "⌘", section: .general),
        KeyboardShortcutInfo(label: "New Account", key: "N", modifiers: "⇧⌘", section: .general),
        KeyboardShortcutInfo(label: "Search", key: "F", modifiers: "⌘", section: .general),
        KeyboardShortcutInfo(label: "Notifications", key: "B", modifiers: "⌘", section: .general),
        KeyboardShortcutInfo(label: "Export Data", key: "E", modifiers: "⇧⌘", section: .general),
        KeyboardShortcutInfo(label: "Settings", key: ",", modifiers: "⌘", section: .general),

        // Navigation
        KeyboardShortcutInfo(label: "Overview", key: "1", modifiers: "⌘", section: .navigation),
        KeyboardShortcutInfo(label: "Inbox", key: "2", modifiers: "⌘", section: .navigation),
        KeyboardShortcutInfo(label: "Trends", key: "3", modifiers: "⌘", section: .navigation),
        KeyboardShortcutInfo(label: "Budgets", key: "4", modifiers: "⌘", section: .navigation),
        KeyboardShortcutInfo(label: "Scheduled", key: "5", modifiers: "⌘", section: .navigation),
        KeyboardShortcutInfo(label: "Insights", key: "6", modifiers: "⌘", section: .navigation),
        KeyboardShortcutInfo(label: "Net Worth", key: "7", modifiers: "⌘", section: .navigation),
        KeyboardShortcutInfo(label: "Reports", key: "8", modifiers: "⌘", section: .navigation),
        KeyboardShortcutInfo(label: "Goals", key: "9", modifiers: "⌘", section: .navigation),
        KeyboardShortcutInfo(label: "Tags", key: "0", modifiers: "⌘", section: .navigation),
    ]
}

// MARK: - Menu Commands

struct AppCommands: Commands {
    @FocusedValue(\.sidebarSelection) var selection
    @FocusedValue(\.showNewAccount) var showNewAccount
    @FocusedValue(\.showNotifications) var showNotifications
    @FocusedValue(\.showNewTransaction) var showNewTransaction

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Transaction") {
                showNewTransaction?.wrappedValue = true
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("New Account") {
                showNewAccount?.wrappedValue = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Search") {
                selection?.wrappedValue = .search
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Notifications") {
                showNotifications?.wrappedValue = true
            }
            .keyboardShortcut("b", modifiers: .command)

            Button("Export Data") {
                selection?.wrappedValue = .importExport
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }

        CommandGroup(after: .sidebar) {
            Divider()

            Button("Overview") {
                selection?.wrappedValue = .overview
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Inbox") {
                selection?.wrappedValue = .inbox
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Trends") {
                selection?.wrappedValue = .trends
            }
            .keyboardShortcut("3", modifiers: .command)

            Button("Budgets") {
                selection?.wrappedValue = .budgets
            }
            .keyboardShortcut("4", modifiers: .command)

            Button("Scheduled") {
                selection?.wrappedValue = .scheduled
            }
            .keyboardShortcut("5", modifiers: .command)

            Button("Insights") {
                selection?.wrappedValue = .insights
            }
            .keyboardShortcut("6", modifiers: .command)

            Button("Net Worth") {
                selection?.wrappedValue = .netWorth
            }
            .keyboardShortcut("7", modifiers: .command)

            Button("Reports") {
                selection?.wrappedValue = .reports
            }
            .keyboardShortcut("8", modifiers: .command)

            Button("Goals") {
                selection?.wrappedValue = .goals
            }
            .keyboardShortcut("9", modifiers: .command)

            Button("Tags") {
                selection?.wrappedValue = .tags
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}
