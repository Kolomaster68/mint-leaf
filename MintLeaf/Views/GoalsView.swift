import SwiftUI
import SwiftData

struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Goal.sortOrder) private var goals: [Goal]

    @State private var tab: GoalTab = .savings
    @State private var showingAddGoal = false
    @State private var editingGoal: Goal?

    enum GoalTab: String, CaseIterable {
        case savings = "Savings Goals"
        case wishlist = "Wishlist"
    }

    private var savingsGoals: [Goal] {
        goals.filter { !$0.isWishlistItem && !$0.isPurchased }
    }

    private var wishlistItems: [Goal] {
        goals.filter { $0.isWishlistItem && !$0.isPurchased }
    }

    private var completedGoals: [Goal] {
        goals.filter { $0.isComplete || $0.isPurchased }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Tab picker
                Picker("", selection: $tab) {
                    ForEach(GoalTab.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Summary
                if tab == .savings {
                    savingsSummary
                }

                // Items
                let items = tab == .savings ? savingsGoals : wishlistItems
                if items.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { goal in
                            goalCard(goal)
                        }
                    }
                    .padding(.horizontal)
                }

                // Completed section
                if !completedGoals.isEmpty {
                    completedSection
                }
            }
            .padding(20)
        }
        .background(AppTheme.surfaceBackground(for: scheme))
        .navigationTitle("Goals")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { showingAddGoal = true } label: {
                    Label("Add Goal", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddGoal) {
            EditGoalSheet(isWishlistItem: tab == .wishlist)
        }
        .sheet(item: $editingGoal) { goal in
            EditGoalSheet(goal: goal)
        }
    }

    // MARK: - Summary

    private var savingsSummary: some View {
        let totalTarget = savingsGoals.reduce(Decimal.zero) { $0 + $1.targetAmount }
        let totalSaved = savingsGoals.reduce(Decimal.zero) { $0 + $1.savedAmount }
        let overallProgress = totalTarget > 0 ? Double(truncating: (totalSaved / totalTarget) as NSDecimalNumber) : 0

        return HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(CurrencyFormatter.shared.format(totalSaved))
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppTheme.accent(for: scheme))
                Text("of \(CurrencyFormatter.shared.format(totalTarget))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(1, overallProgress))
                    .stroke(AppTheme.accent(for: scheme), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(overallProgress * 100))%")
                    .font(.subheadline.weight(.bold).monospacedDigit())
            }
            .frame(width: 64, height: 64)
        }
        .padding()
        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))
        .padding(.horizontal)
    }

    // MARK: - Goal Card

    private func goalCard(_ goal: Goal) -> some View {
        Button { editingGoal = goal } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: goal.icon)
                        .font(.title2)
                        .foregroundStyle(Color(hex: goal.colorHex))
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let days = goal.daysRemaining {
                            Text("\(days) days remaining")
                                .font(.caption)
                                .foregroundStyle(days < 30 ? .orange : .secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(CurrencyFormatter.shared.format(goal.targetAmount))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(.primary)
                        if goal.isWishlistItem, let url = goal.linkURL, !url.isEmpty {
                            Image(systemName: "link")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }

                // Progress bar
                if !goal.isWishlistItem {
                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.secondary.opacity(0.15))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(hex: goal.colorHex))
                                    .frame(width: geo.size.width * min(1, goal.progress))
                            }
                        }
                        .frame(height: 8)

                        HStack {
                            Text(CurrencyFormatter.shared.format(goal.savedAmount))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Color(hex: goal.colorHex))
                            Spacer()
                            Text("\(Int(goal.progress * 100))%")
                                .font(.caption.weight(.medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !goal.notes.isEmpty {
                    Text(goal.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding()
            .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if goal.isWishlistItem {
                Button {
                    goal.isPurchased = true
                } label: {
                    Label("Mark as Purchased", systemImage: "checkmark.circle")
                }
            } else if goal.isComplete {
                Button {
                    goal.isPurchased = true
                } label: {
                    Label("Mark Complete", systemImage: "checkmark.circle")
                }
            }
            Button { editingGoal = goal } label: {
                Label("Edit", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                context.delete(goal)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Completed

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Completed")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            ForEach(completedGoals) { goal in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(goal.name)
                        .font(.subheadline)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(CurrencyFormatter.shared.format(goal.targetAmount))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
        .padding(.top)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: tab == .savings ? "target" : "heart.circle")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(tab == .savings ? "No savings goals yet" : "Your wishlist is empty")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text(tab == .savings ? "Create a goal to start tracking your savings progress." : "Add items you want to save up for.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button { showingAddGoal = true } label: {
                Label(tab == .savings ? "Add Goal" : "Add to Wishlist", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent(for: scheme))
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Edit Goal Sheet

struct EditGoalSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let goal: Goal?
    let isWishlistItem: Bool

    @State private var name = ""
    @State private var icon = "target"
    @State private var colorHex = "D9B138"
    @State private var targetAmount = ""
    @State private var savedAmount = ""
    @State private var hasTargetDate = false
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var notes = ""
    @State private var linkURL = ""

    private let icons = ["target", "heart.fill", "house.fill", "car.fill", "airplane",
                          "laptopcomputer", "gamecontroller.fill", "gift.fill", "graduationcap.fill",
                          "figure.walk", "leaf.fill", "star.fill", "camera.fill", "headphones",
                          "tshirt.fill", "bag.fill", "bicycle", "globe.europe.africa.fill"]

    private let colors = ["D9B138", "34C759", "FF3B30", "007AFF", "FF9500",
                          "AF52DE", "FF2D55", "5AC8FA", "64D2FF", "FFD60A"]

    init(goal: Goal? = nil, isWishlistItem: Bool = false) {
        self.goal = goal
        self.isWishlistItem = goal?.isWishlistItem ?? isWishlistItem
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Target Amount", text: $targetAmount)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif

                    if !isWishlistItem {
                        TextField("Amount Saved", text: $savedAmount)
                        #if os(iOS)
                            .keyboardType(.decimalPad)
                        #endif
                    }
                }

                Section("Appearance") {
                    // Icon picker
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 9), spacing: 8) {
                        ForEach(icons, id: \.self) { ic in
                            Button {
                                icon = ic
                            } label: {
                                Image(systemName: ic)
                                    .font(.body)
                                    .frame(width: 32, height: 32)
                                    .background(icon == ic ? Color(hex: colorHex).opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(icon == ic ? Color(hex: colorHex) : Color.clear, lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Color picker
                    HStack(spacing: 6) {
                        ForEach(colors, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle().strokeBorder(.white, lineWidth: colorHex == hex ? 2 : 0)
                                )
                                .onTapGesture { colorHex = hex }
                        }
                    }
                }

                Section("Target Date") {
                    Toggle("Set target date", isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker("Target", selection: $targetDate, displayedComponents: .date)
                    }
                }

                if isWishlistItem {
                    Section("Link") {
                        TextField("URL (optional)", text: $linkURL)
                    }
                }

                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...5)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(goal == nil ? (isWishlistItem ? "Add to Wishlist" : "New Goal") : "Edit Goal")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty || targetAmount.isEmpty)
                }
            }
            .onAppear {
                if let g = goal {
                    name = g.name
                    icon = g.icon
                    colorHex = g.colorHex
                    targetAmount = "\(g.targetAmount)"
                    savedAmount = "\(g.savedAmount)"
                    hasTargetDate = g.targetDate != nil
                    targetDate = g.targetDate ?? targetDate
                    notes = g.notes
                    linkURL = g.linkURL ?? ""
                }
            }
        }
        .macOSSheet(width: 520, height: 620)
    }

    private func save() {
        let target = Decimal(string: targetAmount) ?? 0
        let saved = Decimal(string: savedAmount) ?? 0

        if let g = goal {
            g.name = name
            g.icon = icon
            g.colorHex = colorHex
            g.targetAmount = target
            g.savedAmount = saved
            g.targetDate = hasTargetDate ? targetDate : nil
            g.notes = notes
            g.linkURL = isWishlistItem ? (linkURL.isEmpty ? nil : linkURL) : nil
        } else {
            let g = Goal(
                name: name,
                icon: icon,
                colorHex: colorHex,
                targetAmount: target,
                savedAmount: saved,
                targetDate: hasTargetDate ? targetDate : nil,
                notes: notes,
                isWishlistItem: isWishlistItem,
                linkURL: isWishlistItem ? (linkURL.isEmpty ? nil : linkURL) : nil
            )
            context.insert(g)
        }
        dismiss()
    }
}
