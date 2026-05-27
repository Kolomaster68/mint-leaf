import SwiftUI
import SwiftData

struct NotificationCenterView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ScheduledTransaction.nextDate) private var scheduled: [ScheduledTransaction]
    @Query(sort: \Budget.startDate) private var budgets: [Budget]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    private let manager = NotificationManager.shared

    private var notifications: [AppNotification] {
        manager.generateNotifications(scheduled: scheduled, budgets: budgets, accounts: accounts)
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
                            }
                        } header: {
                            Label("Upcoming", systemImage: "clock")
                        }
                    }

                    if !info.isEmpty {
                        Section {
                            ForEach(info) { notif in
                                notificationRow(notif)
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
                ToolbarItemGroup(placement: .automatic) {
                    if !notifications.isEmpty {
                        Button {
                            withAnimation { manager.dismissAll(notifications) }
                        } label: {
                            Label("Dismiss All", systemImage: "bell.slash")
                        }
                    }
                    if manager.hasDismissedOrSnoozed {
                        Button {
                            withAnimation { manager.restoreAll() }
                        } label: {
                            Label("Restore All", systemImage: "arrow.counterclockwise")
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
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation { manager.dismiss(notif) }
            } label: {
                Label("Dismiss", systemImage: "xmark.circle")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                withAnimation { manager.snooze(notif) }
            } label: {
                Label("Snooze 24h", systemImage: "clock.badge.checkmark")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button {
                withAnimation { manager.dismiss(notif) }
            } label: {
                Label("Dismiss", systemImage: "xmark.circle")
            }
            Button {
                withAnimation { manager.snooze(notif, hours: 24) }
            } label: {
                Label("Snooze for 24 hours", systemImage: "clock.badge.checkmark")
            }
            Button {
                withAnimation { manager.snooze(notif, hours: 72) }
            } label: {
                Label("Snooze for 3 days", systemImage: "clock")
            }
            Button {
                withAnimation { manager.snooze(notif, hours: 168) }
            } label: {
                Label("Snooze for 1 week", systemImage: "calendar")
            }
        }
    }
}
