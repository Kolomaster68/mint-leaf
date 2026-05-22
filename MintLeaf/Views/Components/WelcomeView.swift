import SwiftUI
import SwiftData

struct WelcomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("appAppearance") private var appearance: String = AppAppearance.system.rawValue
    @AppStorage("shouldStartTutorial") private var shouldStartTutorial = false
    @State private var currentPage = 0
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            switch currentPage {
            case 0:
                welcomePage
            case 1:
                featuresPage
            case 2:
                setupPage
            default:
                EmptyView()
            }

            Spacer()

            pageIndicator
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.surfaceBackground(for: scheme))
    }

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 72))
                .foregroundStyle(AppTheme.accentGradient(for: scheme))

            Text("Welcome to Mint Leaf")
                .font(.system(size: 32, weight: .bold, design: .rounded))

            Text("Your personal finance companion.\nTrack spending, set budgets, and stay in control.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button {
                withAnimation { currentPage = 1 }
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: 220)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent(for: scheme))
            .padding(.top, 12)
        }
    }

    private var featuresPage: some View {
        VStack(spacing: 28) {
            Text("What You Can Do")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 16) {
                featureRow(icon: "building.columns", title: "Multiple Accounts", description: "Track checking, savings, credit cards and cash")
                featureRow(icon: "chart.pie", title: "Budgets", description: "Set spending limits by category and track progress")
                featureRow(icon: "chart.line.uptrend.xyaxis", title: "Trends & Insights", description: "Visualise spending patterns and cashflow forecasts")
                featureRow(icon: "clock.arrow.circlepath", title: "Scheduled Transactions", description: "Automate recurring bills and subscriptions")
                featureRow(icon: "magnifyingglass", title: "Powerful Search", description: "Find any transaction instantly by name, category or amount")
                featureRow(icon: "bell.badge", title: "Notifications", description: "Stay on top of due bills, exceeded budgets and overdue items")
                featureRow(icon: "sterlingsign.circle", title: "Multi-Currency", description: "Support for 39 currencies with automatic formatting")
                featureRow(icon: "keyboard", title: "Keyboard Shortcuts", description: "Navigate the app quickly with built-in shortcuts")
            }
            .frame(maxWidth: 420)

            Button {
                withAnimation { currentPage = 2 }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: 220)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent(for: scheme))
            .padding(.top, 8)
        }
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppTheme.accent(for: scheme))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var setupPage: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.accentGradient(for: scheme))

            Text("Set Up Your Preferences")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            VStack(spacing: 16) {
                Text("Appearance")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    ForEach(AppAppearance.allCases) { option in
                        Button {
                            withAnimation { appearance = option.rawValue }
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: appearanceIcon(option))
                                    .font(.title2)
                                Text(option.rawValue)
                                    .font(.caption.weight(.medium))
                            }
                            .frame(width: 90, height: 70)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(appearance == option.rawValue ? AppTheme.accent(for: scheme).opacity(0.12) : .clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(appearance == option.rawValue ? AppTheme.accent(for: scheme).opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(appearance == option.rawValue ? AppTheme.accent(for: scheme) : .secondary)
                    }
                }
            }

            Divider()
                .frame(maxWidth: 300)
                .padding(.vertical, 4)

            Text("How would you like to start?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                Button {
                    hasCompletedOnboarding = true
                } label: {
                    Text("Start Fresh")
                        .font(.headline)
                        .frame(maxWidth: 280)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent(for: scheme))

                Button {
                    isLoading = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        SampleDataGenerator.populate(context: context)
                        try? context.save()
                        isLoading = false
                        shouldStartTutorial = true
                        hasCompletedOnboarding = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 2)
                        }
                        Image(systemName: "hand.wave")
                            .font(.subheadline)
                        Text("Load Sample Data & Take a Tour")
                            .font(.headline)
                    }
                    .frame(maxWidth: 280)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)

                Button {
                    isLoading = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        SampleDataGenerator.populate(context: context)
                        try? context.save()
                        isLoading = false
                        hasCompletedOnboarding = true
                    }
                } label: {
                    Text("Load Sample Data (No Tour)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)

                Text("Sample data includes accounts, transactions,\nbudgets and scheduled items to explore with.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
    }

    private func appearanceIcon(_ option: AppAppearance) -> String {
        switch option {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon.stars"
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { page in
                Circle()
                    .fill(page == currentPage ? AppTheme.accent(for: scheme) : AppTheme.accent(for: scheme).opacity(0.25))
                    .frame(width: 8, height: 8)
            }
        }
    }
}
