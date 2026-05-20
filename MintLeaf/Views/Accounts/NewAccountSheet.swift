import SwiftUI
import SwiftData

struct NewAccountSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    var account: Account?

    @State private var name = ""
    @State private var type: AccountType = .checking
    @State private var currency = "USD"
    @State private var initialBalance = ""
    @State private var colorHex = "#4CAF50"
    @State private var customColor = Color(hex: "#4CAF50")
    @State private var useCustomColor = false

    private let presetColors = [
        "#4CAF50", "#2196F3", "#FF9800", "#E91E63",
        "#9C27B0", "#00BCD4", "#795548", "#607D8B",
        "#F44336", "#3F51B5", "#009688", "#FFC107",
    ]

    private var isEditing: Bool { account != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account Details") {
                    TextField("Account Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    TextField("Currency", text: $currency)
                    if !isEditing {
                        TextField("Balance", text: $initialBalance)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(presetColors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if !useCustomColor && color == colorHex {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.white)
                                            .font(.caption2.bold())
                                    }
                                }
                                .onTapGesture {
                                    colorHex = color
                                    useCustomColor = false
                                }
                        }
                    }
                    .padding(.vertical, 4)

                    Divider()

                    HStack(spacing: 12) {
                        ColorPicker("Custom Color", selection: $customColor, supportsOpacity: false)
                            .onChange(of: customColor) { _, newColor in
                                colorHex = newColor.toHex()
                                useCustomColor = true
                            }

                        if useCustomColor {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: colorHex))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.white)
                                        .font(.caption2.bold())
                                }
                        }
                    }
                }

                Section {
                    HStack(spacing: 12) {
                        Image(systemName: type.icon)
                            .font(.caption)
                            .foregroundStyle(Color(hex: colorHex))
                            .frame(width: 28, height: 28)
                            .background(Color(hex: colorHex).opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(name.isEmpty ? "Account Preview" : name)
                            .font(.body)
                            .foregroundStyle(name.isEmpty ? .secondary : .primary)
                    }
                } header: {
                    Text("Preview")
                }
            }
            .navigationTitle(isEditing ? "Edit Account" : "New Account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .disabled(name.isEmpty)
                }
            }
            .onAppear {
                if let account {
                    name = account.name
                    type = account.type
                    currency = account.currency
                    colorHex = account.colorHex
                    customColor = Color(hex: account.colorHex)
                    useCustomColor = !presetColors.contains(account.colorHex)
                }
            }
        }
        .macOSSheet(width: 520, height: 560)
    }

    private func save() {
        if let account {
            account.name = name
            account.type = type
            account.currency = currency
            account.colorHex = colorHex
            account.icon = type.icon
        } else {
            let balance = Decimal(string: initialBalance) ?? 0
            let newAccount = Account(
                name: name,
                type: type,
                currency: currency,
                initialBalance: balance,
                icon: type.icon,
                colorHex: colorHex,
                sortOrder: accounts.count
            )
            context.insert(newAccount)
        }
        dismiss()
    }
}
