import SwiftUI
import SwiftData

struct NewAccountSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    var account: Account?

    @State private var name = ""
    @State private var type: AccountType = .checking
    @State private var currency = UserDefaults.standard.string(forKey: "defaultCurrency") ?? "USD"
    @State private var initialBalance = ""
    @State private var colorHex = "#4CAF50"
    @State private var customColor = Color(hex: "#4CAF50")
    @State private var useCustomColor = false
    @State private var trackBillingCycle = false
    @State private var statementDay = 1
    @State private var paymentDueOffset = 21
    @State private var paymentDueDay = 1
    @State private var paymentMode: PaymentMode = .daysAfter
    @State private var paymentSourceID: UUID?
    @State private var overdraftLimit = ""
    @State private var overdraftEAR = ""
    @State private var unarrangedFee = ""
    @State private var purchaseAPR = ""

    enum PaymentMode: String, CaseIterable {
        case daysAfter = "Days after statement"
        case fixedDay = "Day of month"
    }

    private let presetColors = [
        "#4CAF50", "#2196F3", "#FF9800", "#E91E63",
        "#9C27B0", "#00BCD4", "#795548", "#607D8B",
        "#F44336", "#3F51B5", "#009688", "#FFC107",
    ]

    private var isEditing: Bool { account != nil }

    private var otherAccounts: [Account] {
        accounts.filter { $0.id != account?.id && $0.type != .creditCard && !$0.isArchived }
    }

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
                    Picker("Currency", selection: $currency) {
                        ForEach(SupportedCurrencies.all, id: \.code) { c in
                            Text("\(c.flag) \(c.code)").tag(c.code)
                        }
                    }
                    HStack {
                        Text(isEditing ? "Starting Balance" : "Balance")
                        Spacer()
                        TextField("", text: $initialBalance, prompt: Text("0.00").foregroundStyle(.tertiary))
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                }

                if type == .creditCard {
                    Section {
                        Toggle("Track statement cycle", isOn: $trackBillingCycle.animation())
                    } header: {
                        Text("Billing Cycle")
                    } footer: {
                        if trackBillingCycle {
                            Text("The app totals what you spend each cycle into a statement balance and reminds you before the payment is due.")
                        }
                    }

                    if trackBillingCycle {
                        Section {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Statement is cut on the")
                                    .font(.subheadline)
                                Text("\(statementDay)\(ordinalSuffix(statementDay)) of each month")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.accent(for: scheme))
                            }
                            DayOfMonthPicker(selectedDay: $statementDay)
                            DayOfMonthHint(day: statementDay)
                        } header: {
                            Text("Statement Day")
                        }

                        Section {
                            Picker("", selection: $paymentMode.animation()) {
                                ForEach(PaymentMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            switch paymentMode {
                            case .daysAfter:
                                Stepper(value: $paymentDueOffset, in: 1...60) {
                                    HStack {
                                        Text("Due")
                                        Spacer()
                                        Text("\(paymentDueOffset) days after statement")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            case .fixedDay:
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Payment is due on the")
                                        .font(.subheadline)
                                    Text("\(paymentDueDay)\(ordinalSuffix(paymentDueDay)) of each month")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.accent(for: scheme))
                                }
                                DayOfMonthPicker(selectedDay: $paymentDueDay)
                                DayOfMonthHint(day: paymentDueDay)
                            }
                        } header: {
                            Text("Payment Due")
                        }

                        Section {
                            Picker("Pay from", selection: $paymentSourceID) {
                                Text("Not set").tag(nil as UUID?)
                                ForEach(otherAccounts) { acc in
                                    Text(acc.name).tag(Optional(acc.id))
                                }
                            }
                        } header: {
                            Text("Funding Account")
                        } footer: {
                            Text("The account this card is paid from. We'll warn you if its projected balance won't cover the payment when it's due.")
                        }
                    }
                }

                if type == .checking || type == .savings {
                    Section {
                        HStack {
                            Text("Arranged limit")
                            Spacer()
                            TextField("", text: $overdraftLimit, prompt: Text("0.00").foregroundStyle(.tertiary))
                                .multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                        }
                        HStack {
                            Text("Interest rate (EAR)")
                            Spacer()
                            TextField("", text: $overdraftEAR, prompt: Text("0.0").foregroundStyle(.tertiary))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            Text("%").foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Unarranged fee")
                            Spacer()
                            TextField("", text: $unarrangedFee, prompt: Text("0.00").foregroundStyle(.tertiary))
                                .multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                        }
                    } header: {
                        Text("Overdraft")
                    } footer: {
                        Text("Used to show overdraft usage and estimate fees before they hit. The unarranged fee is charged if you go past the arranged limit. Leave blank if you have no overdraft.")
                    }
                }

                if type == .creditCard {
                    Section {
                        HStack {
                            Text("Purchase rate (APR)")
                            Spacer()
                            TextField("", text: $purchaseAPR, prompt: Text("0.0").foregroundStyle(.tertiary))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            Text("%").foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Interest")
                    } footer: {
                        Text("Used to estimate interest if you don't pay the statement balance in full. Estimates only — no charges are created.")
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
                    initialBalance = "\(account.initialBalance)"
                    colorHex = account.colorHex
                    customColor = Color(hex: account.colorHex)
                    useCustomColor = !presetColors.contains(account.colorHex)
                    if let day = account.statementDay {
                        trackBillingCycle = true
                        statementDay = day
                        if let fixedDay = account.paymentDueDay {
                            paymentMode = .fixedDay
                            paymentDueDay = fixedDay
                        } else {
                            paymentMode = .daysAfter
                            paymentDueOffset = account.paymentDueOffsetDays ?? 21
                        }
                    }
                    paymentSourceID = account.paymentSourceAccountID
                    if let limit = account.overdraftLimit {
                        overdraftLimit = "\(limit)"
                    }
                    if let ear = account.overdraftEAR {
                        overdraftEAR = "\(ear)"
                    }
                    if let fee = account.unarrangedOverdraftFee {
                        unarrangedFee = "\(fee)"
                    }
                    if let apr = account.purchaseAPR {
                        purchaseAPR = "\(apr)"
                    }
                }
            }
        }
        .formStyle(.grouped)
        .macOSSheet(width: 520, height: type == .creditCard && trackBillingCycle ? 760 : 560)
    }

    private func save() {
        let cycleActive = type == .creditCard && trackBillingCycle
        let useFixedDay = cycleActive && paymentMode == .fixedDay
        let isCurrentLike = type == .checking || type == .savings
        let overdraftValue: Decimal? = isCurrentLike
            ? (overdraftLimit.isEmpty ? nil : Decimal(string: overdraftLimit))
            : nil
        let earValue: Decimal? = isCurrentLike && !overdraftEAR.isEmpty ? Decimal(string: overdraftEAR) : nil
        let unarrangedValue: Decimal? = isCurrentLike && !unarrangedFee.isEmpty ? Decimal(string: unarrangedFee) : nil
        let aprValue: Decimal? = type == .creditCard && !purchaseAPR.isEmpty ? Decimal(string: purchaseAPR) : nil
        if let account {
            account.name = name
            account.type = type
            account.currency = currency
            account.initialBalance = Decimal(string: initialBalance) ?? account.initialBalance
            account.colorHex = colorHex
            account.icon = type.icon
            account.statementDay = cycleActive ? statementDay : nil
            account.paymentDueOffsetDays = (cycleActive && !useFixedDay) ? paymentDueOffset : nil
            account.paymentDueDay = useFixedDay ? paymentDueDay : nil
            account.paymentSourceAccountID = cycleActive ? paymentSourceID : nil
            account.overdraftLimit = overdraftValue
            account.overdraftEAR = earValue
            account.unarrangedOverdraftFee = unarrangedValue
            account.purchaseAPR = aprValue
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
            newAccount.statementDay = cycleActive ? statementDay : nil
            newAccount.paymentDueOffsetDays = (cycleActive && !useFixedDay) ? paymentDueOffset : nil
            newAccount.paymentDueDay = useFixedDay ? paymentDueDay : nil
            newAccount.paymentSourceAccountID = cycleActive ? paymentSourceID : nil
            newAccount.overdraftLimit = overdraftValue
            newAccount.overdraftEAR = earValue
            newAccount.unarrangedOverdraftFee = unarrangedValue
            newAccount.purchaseAPR = aprValue
            context.insert(newAccount)
        }
        dismiss()
    }

    private func ordinalSuffix(_ n: Int) -> String {
        switch n % 100 {
        case 11, 12, 13: return "th"
        default:
            switch n % 10 {
            case 1: return "st"
            case 2: return "nd"
            case 3: return "rd"
            default: return "th"
            }
        }
    }
}
