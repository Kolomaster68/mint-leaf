import SwiftUI
import SwiftData

struct NewBudgetSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var editing: Budget?

    @State private var name = ""
    @State private var period: BudgetPeriod = .monthly
    @State private var startDate = Date()

    private var isEditing: Bool { editing != nil }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Budget Name", text: $name)
                Picker("Period", selection: $period) {
                    ForEach(BudgetPeriod.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
            }
            .navigationTitle(isEditing ? "Edit Budget" : "New Budget")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        if let editing {
                            editing.name = name
                            editing.period = period
                            editing.startDate = startDate
                        } else {
                            let budget = Budget(name: name, period: period, startDate: startDate)
                            context.insert(budget)
                        }
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                if let editing {
                    name = editing.name
                    period = editing.period
                    startDate = editing.startDate
                }
            }
        }
        .macOSSheet(width: 500, height: 300)
    }
}
