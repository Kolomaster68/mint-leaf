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
            TutorialStep("sidebar", title: "Sidebar Navigation", message: "The sidebar is your home base. Your accounts are listed at the top with live balances, and tools like Budgets, Trends and Insights are below.", icon: "sidebar.left", navigation: "overview"),
            TutorialStep("overview", title: "Overview Dashboard", message: "The Overview shows your net worth, income vs expenses, active subscriptions, and recent transactions — all at a glance.", icon: "square.grid.2x2", navigation: "overview"),
            TutorialStep("accounts", title: "Accounts", message: "Click any account in the sidebar to see its transactions. You can add checking, savings, credit cards, and cash accounts.", icon: "building.columns"),
            TutorialStep("inbox", title: "Transaction Inbox", message: "Uncategorised transactions land here. Review them, assign categories, and keep your records clean.", icon: "tray", navigation: "inbox"),
            TutorialStep("budgets", title: "Budgets", message: "Create monthly budgets with category limits. Track your spending against each budget in real time.", icon: "chart.pie", navigation: "budgets"),
            TutorialStep("trends", title: "Trends & Analytics", message: "Visualise your spending patterns over time with charts. See where your money goes each month.", icon: "chart.line.uptrend.xyaxis", navigation: "trends"),
            TutorialStep("insights", title: "Smart Insights", message: "Get AI-powered analysis of your finances — anomaly detection, cashflow forecasts, and spending summaries.", icon: "lightbulb", navigation: "insights"),
            TutorialStep("scheduled", title: "Scheduled Transactions", message: "Set up recurring bills and income. Mint Leaf tracks what's coming up and when it's due.", icon: "clock.arrow.circlepath", navigation: "scheduled"),
            TutorialStep("rules", title: "Rules & Automation", message: "Create rules to auto-categorise transactions and set up merchant aliases to clean up messy bank descriptions.", icon: "wand.and.rays", navigation: "rules"),
            TutorialStep("imports", title: "Importing Data", message: "Import transactions from CSV or PDF bank statements. Use File → Import to get started.", icon: "square.and.arrow.down", navigation: "overview"),
            TutorialStep("done", title: "You're All Set!", message: "That's the basics! You can replay this tour anytime from Settings. Explore, experiment, and make Mint Leaf your own.", icon: "checkmark.seal", navigation: "overview"),
        ]
    )

    static let allFlows: [TutorialFlow] = [welcomeTour]
}
