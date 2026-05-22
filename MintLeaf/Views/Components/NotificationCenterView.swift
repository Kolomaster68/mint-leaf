import SwiftUI
import SwiftData

struct AppNotification: Identifiable {
    let id = UUID()
    let stableKey: String  // Stable identifier for dismiss persistence
    let icon: String
    let iconColor: Color
    let title: String
    let message: String
    let date: Date?
    let priority: Priority

    enum Priority: Int, Comparable {
        case low = 0
        case medium = 1
        case high = 2

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}

struct NotificationCenterView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ScheduledTransaction.nextDate) private var scheduled: [ScheduledTransaction]
    @Query(sort: \Budget.startDate) private var budgets: [Budget]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @AppStorage("dismissedNotifications") private var dismissedData: Data = Data()

    private var dismissedKeys: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: dismissedData)) ?? []
    }

    private func dismissNotification(_ notif: AppNotification) {
        var keys = dismissedKeys
        keys.insert(notif.stableKey)
        dismissedData = (try? JSONEncoder().encode(keys)) ?? Data()
    }

    private func restoreAll() {
        dismissedData = Data()
    }

    private static func relativeDateString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func shortDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private var notifications: [AppNotification] {
        var items: [AppNotification] = []
        let calendar = Calendar.current
        let today = Date()
        let sevenDays = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let threeDays = calendar.date(byAdding: .day, value: 3, to: today) ?? today
        let dismissed = dismissedKeys

        // Bills and subscriptions due soon
        for item in scheduled where item.isActive {
            if item.nextDate <= today {
                items.append(AppNotification(
                    stableKey: "overdue-\(item.title)",
                    icon: "exclamationmark.circle.fill",
                    iconColor: .red,
                    title: "\(item.title) is overdue",
                    message: "Was due \(Self.relativeDateString(item.nextDate)) ago — \(CurrencyFormatter.shared.format(abs(item.amount)))",
                    date: item.nextDate,
                    priority: .high
                ))
            } else if item.nextDate <= threeDays {
                items.append(AppNotification(
                    stableKey: "due-soon-\(item.title)",
                    icon: item.isSubscription ? "arrow.triangle.2.circlepath" : "calendar.badge.clock",
                    iconColor: .orange,
                    title: "\(item.title) due soon",
                    message: "Due \(Self.relativeDateString(item.nextDate)) — \(CurrencyFormatter.shared.format(abs(item.amount)))",
                    date: item.nextDate,
                    priority: .high
                ))
            } else if item.nextDate <= sevenDays {
                items.append(AppNotification(
                    stableKey: "coming-up-\(item.title)",
                    icon: item.isSubscription ? "arrow.triangle.2.circlepath" : "calendar",
                    iconColor: .blue,
                    title: "\(item.title) coming up",
                    message: "Due \(Self.shortDateString(item.nextDate)) — \(CurrencyFormatter.shared.format(abs(item.amount)))",
                    date: item.nextDate,
                    priority: .medium
                ))
            }
        }

        // Budget warnings
        for budget in budgets {
            for item in budget.items {
                guard let category = item.category else { continue }
                let progress = item.progress
                if progress >= 1.0 {
                    items.append(AppNotification(
                        stableKey: "budget-exceeded-\(category.name)",
                        icon: "exclamationmark.triangle.fill",
                        iconColor: .red,
                        title: "\(category.name) budget exceeded",
                        message: "Spent \(CurrencyFormatter.shared.format(item.spent)) of \(CurrencyFormatter.shared.format(item.amount)) budget",
                        date: nil,
                        priority: .high
                    ))
                } else if progress >= 0.8 {
                    items.append(AppNotification(
                        stableKey: "budget-warning-\(category.name)",
                        icon: "chart.pie.fill",
                        iconColor: .orange,
                        title: "\(category.name) budget at \(Int(progress * 100))%",
                        message: "\(CurrencyFormatter.shared.format(item.remaining)) remaining of \(CurrencyFormatter.shared.format(item.amount))",
                        date: nil,
                        priority: .medium
                    ))
                }
            }
        }

        // Low balance warnings
        for account in accounts where !account.isArchived {
            if account.currentBalance < 0 && account.type != .creditCard {
                items.append(AppNotification(
                    stableKey: "negative-\(account.name)",
                    icon: "exclamationmark.triangle.fill",
                    iconColor: .red,
                    title: "\(account.name) is negative",
                    message: "Balance: \(CurrencyFormatter.shared.format(account.currentBalance, currency: account.currency))",
                    date: nil,
                    priority: .high
                ))
            } else if account.currentBalance < 100 && account.currentBalance >= 0
                        && account.type != .creditCard && account.type != .loan {
                items.append(AppNotification(
                    stableKey: "low-balance-\(account.name)",
                    icon: "exclamationmark.circle",
                    iconColor: .orange,
                    title: "\(account.name) balance is low",
                    message: "Balance: \(CurrencyFormatter.shared.format(account.currentBalance, currency: account.currency))",
                    date: nil,
                    priority: .medium
                ))
            }
        }

        // Credit card high balance
        for account in accounts where account.type == .creditCard && !account.isArchived {
            if abs(account.currentBalance) > 1000 {
                items.append(AppNotification(
                    stableKey: "cc-high-\(account.name)",
                    icon: "creditcard.fill",
                    iconColor: .orange,
                    title: "\(account.name) balance is high",
                    message: "Outstanding: \(CurrencyFormatter.shared.format(abs(account.currentBalance), currency: account.currency))",
                    date: nil,
                    priority: .medium
                ))
            }
        }

        // Paused subscriptions reminder
        let pausedCount = scheduled.filter { $0.isSubscription && !$0.isActive }.count
        if pausedCount > 0 {
            items.append(AppNotification(
                stableKey: "paused-subs",
                icon: "pause.circle",
                iconColor: .secondary,
                title: "\(pausedCount) paused subscription\(pausedCount == 1 ? "" : "s")",
                message: "Review your paused subscriptions to see if you still need them.",
                date: nil,
                priority: .low
            ))
        }

        return items
            .filter { !dismissed.contains($0.stableKey) }
            .sorted { $0.priority > $1.priority }
    }

    var notificationCount: Int {
        notifications.filter { $0.priority >= .medium }.count
    }

    var body: some View {
        NavigationStack {
            List {
                if notifications.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                Image(systemName: "bell.slash")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.tertiary)
                                Text("All Clear")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                Text("No alerts or upcoming items right now.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 24)
                            Spacer()
                        }
                    }
                } else {
                    let urgent = notifications.filter { $0.priority == .high }
                    let upcoming = notifications.filter { $0.priority == .medium }
                    let info = notifications.filter { $0.priority == .low }

                    if !urgent.isEmpty {
                        Section {
                            ForEach(urgent) { notif in
                                notificationRow(notif)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            withAnimation { dismissNotification(notif) }
                                        } label: {
                                            Label("Dismiss", systemImage: "xmark.circle")
                                        }
                                    }
                            }
                        } header: {
                            Label("Urgent", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }

                    if !upcoming.isEmpty {
                        Section {
                            ForEach(upcoming) { notif in
                                notificationRow(notif)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            withAnimation { dismissNotification(notif) }
                                        } label: {
                                            Label("Dismiss", systemImage: "xmark.circle")
                                        }
                                    }
                            }
                        } header: {
                            Label("Upcoming", systemImage: "clock")
                        }
                    }

                    if !info.isEmpty {
                        Section {
                            ForEach(info) { notif in
                                notificationRow(notif)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            withAnimation { dismissNotification(notif) }
                                        } label: {
                                            Label("Dismiss", systemImage: "xmark.circle")
                                        }
                                    }
                            }
                        } header: {
                            Label("Info", systemImage: "info.circle")
                        }
                    }
                }
            }
            .premiumList()
            .navigationTitle("Notifications")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !dismissedKeys.isEmpty {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            withAnimation { restoreAll() }
                        } label: {
                            Label("Restore Dismissed", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
            }
        }
        .macOSSheet(width: 480, height: 520)
    }

    private func notificationRow(_ notif: AppNotification) -> some View {
        HStack(spacing: 12) {
            Image(systemName: notif.icon)
                .font(.title3)
                .foregroundStyle(notif.iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(notif.title)
                    .font(.subheadline.weight(.medium))
                Text(notif.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
