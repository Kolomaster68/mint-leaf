import SwiftUI

struct TutorialStep: Identifiable {
    let id: String
    let title: String
    let message: String
    let icon: String
    let navigation: String?

    init(_ id: String, title: String, message: String, icon: String, navigation: String? = nil) {
        self.id = id
        self.title = title
        self.message = message
        self.icon = icon
        self.navigation = navigation
    }
}

struct TutorialFlow: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let steps: [TutorialStep]
}

@MainActor @Observable
final class TutorialEngine {
    static let shared = TutorialEngine()

    var activeFlow: TutorialFlow?
    var currentStepIndex: Int = 0
    var isActive: Bool { activeFlow != nil }

    var currentStep: TutorialStep? {
        guard let flow = activeFlow, currentStepIndex < flow.steps.count else { return nil }
        return flow.steps[currentStepIndex]
    }

    var progress: (current: Int, total: Int) {
        guard let flow = activeFlow else { return (0, 0) }
        return (currentStepIndex + 1, flow.steps.count)
    }

    func start(_ flow: TutorialFlow) {
        activeFlow = flow
        currentStepIndex = 0
    }

    func next() {
        guard let flow = activeFlow else { return }
        if currentStepIndex < flow.steps.count - 1 {
            currentStepIndex += 1
        } else {
            complete()
        }
    }

    func back() {
        if currentStepIndex > 0 {
            currentStepIndex -= 1
        }
    }

    func skip() {
        guard let flow = activeFlow else { return }
        markCompleted(flow.id)
        activeFlow = nil
        currentStepIndex = 0
    }

    func complete() {
        guard let flow = activeFlow else { return }
        markCompleted(flow.id)
        activeFlow = nil
        currentStepIndex = 0
    }

    func isCompleted(_ flowID: String) -> Bool {
        UserDefaults.standard.bool(forKey: "tutorial_\(flowID)_completed")
    }

    func resetAll() {
        for flow in TutorialLibrary.allFlows {
            UserDefaults.standard.removeObject(forKey: "tutorial_\(flow.id)_completed")
        }
    }

    private func markCompleted(_ flowID: String) {
        UserDefaults.standard.set(true, forKey: "tutorial_\(flowID)_completed")
    }
}

enum TutorialLibrary {
    static let welcomeTour = TutorialFlow(
        id: "welcome_tour",
        title: "Welcome Tour",
        description: "A guided walkthrough of Mint Leaf's main features",
        icon: "hand.wave",
        steps: [
            TutorialStep("welcome", title: "Welcome to Mint Leaf!", message: "Let's take a quick tour of the app. We've loaded sample data so you can explore safely — nothing here is real.", icon: "sparkles", navigation: "overview"),
            TutorialStep("sidebar", title: "Sidebar Navigation", message: "The sidebar is your home base. It's organised into groups — Accounts with net worth, Analytics, Scheduled items, Planning, and Tools. Collapse or expand sections to customise your view.", icon: "sidebar.left", navigation: "overview"),
            TutorialStep("overview", title: "Overview Dashboard", message: "The Overview shows your net worth, income vs expenses, active subscriptions, upcoming bills, and recent transactions — all at a glance.", icon: "square.grid.2x2", navigation: "overview"),
            TutorialStep("search", title: "Search", message: "Find any transaction instantly. Search by name, category, account, notes, or even amount. Filter by income or expenses to narrow results.", icon: "magnifyingglass", navigation: "search"),
            TutorialStep("notifications", title: "Notification Centre", message: "Tap the bell icon next to Overview to see alerts — overdue bills, exceeded budgets, upcoming payments, and more. Stay on top of your finances.", icon: "bell.badge", navigation: "overview"),
            TutorialStep("accounts", title: "Accounts", message: "Click any account in the sidebar to see its transactions. You can add checking, savings, credit cards, and cash accounts. Your total net worth is shown in the sidebar.", icon: "building.columns"),
            TutorialStep("inbox", title: "Transaction Inbox", message: "Uncategorised transactions land here. Review them, assign categories, and keep your records clean.", icon: "tray", navigation: "inbox"),
            TutorialStep("budgets", title: "Budgets", message: "Create monthly budgets with category limits. Track your spending against each budget in real time.", icon: "chart.pie", navigation: "budgets"),
            TutorialStep("trends", title: "Trends & Analytics", message: "Visualise your spending patterns over time with charts. See income vs expenses, net values, and where your money goes each month.", icon: "chart.line.uptrend.xyaxis", navigation: "trends"),
            TutorialStep("insights", title: "Smart Insights", message: "Get AI-powered analysis of your finances — anomaly detection, cashflow forecasts, and spending summaries.", icon: "lightbulb", navigation: "insights"),
            TutorialStep("scheduled", title: "Scheduled Transactions", message: "Set up recurring bills, subscriptions, and income. View them on a calendar, track what's due, and pause or resume anytime.", icon: "clock.arrow.circlepath", navigation: "scheduled"),
            TutorialStep("rules", title: "Rules & Automation", message: "Create rules to auto-categorise transactions and set up merchant aliases to clean up messy bank descriptions.", icon: "wand.and.rays", navigation: "rules"),
            TutorialStep("currency", title: "Multi-Currency", message: "Mint Leaf supports 39 currencies. Set your default currency in Settings and all accounts and transactions will update automatically.", icon: "sterlingsign.circle"),
            TutorialStep("shortcuts", title: "Keyboard Shortcuts", message: "Navigate quickly with shortcuts — ⌘1–5 for sections, ⌘F for search, ⌘B for notifications, and ⇧⌘N for a new account.", icon: "keyboard"),
            TutorialStep("imports", title: "Importing Data", message: "Import transactions from CSV or PDF bank statements. Head to Tools → Import / Export to get started.", icon: "square.and.arrow.down", navigation: "overview"),
            TutorialStep("done", title: "You're All Set!", message: "That's the basics! You can replay this tour anytime from Settings. Explore, experiment, and make Mint Leaf your own.", icon: "checkmark.seal", navigation: "overview"),
        ]
    )

    static let allFlows: [TutorialFlow] = [welcomeTour]
}
