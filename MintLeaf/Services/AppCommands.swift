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
}

// MARK: - Menu Commands

struct AppCommands: Commands {
    @FocusedValue(\.sidebarSelection) var selection
    @FocusedValue(\.showNewAccount) var showNewAccount
    @FocusedValue(\.showNotifications) var showNotifications

    var body: some Commands {
        CommandGroup(after: .newItem) {
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
        }
    }
}
