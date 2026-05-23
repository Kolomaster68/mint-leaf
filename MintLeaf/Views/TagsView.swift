import SwiftUI
import SwiftData

struct TagsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Tag.sortOrder) private var tags: [Tag]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var showingAddTag = false
    @State private var editingTag: Tag?
    @State private var selectedTag: Tag?

    private var allTransactions: [Transaction] {
        accounts.flatMap { $0.transactions }
    }

    var body: some View {
        VStack(spacing: 0) {
            if tags.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    // Tag list sidebar
                    tagList
                        .frame(width: 240)

                    Divider()

                    // Tag detail
                    if let tag = selectedTag {
                        tagDetail(tag)
                    } else {
                        ContentUnavailableView(
                            "Select a Tag",
                            systemImage: "tag",
                            description: Text("Choose a tag to see its transactions.")
                        )
                    }
                }
            }
        }
        .background(AppTheme.surfaceBackground(for: scheme))
        .navigationTitle("Tags")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { showingAddTag = true } label: {
                    Label("New Tag", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddTag) {
            EditTagSheet()
        }
        .sheet(item: $editingTag) { tag in
            EditTagSheet(tag: tag)
        }
    }

    // MARK: - Tag List

    private var tagList: some View {
        List(selection: $selectedTag) {
            ForEach(tags) { tag in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: tag.colorHex))
                        .frame(width: 10, height: 10)
                    Text(tag.name)
                        .font(.subheadline)
                    Spacer()
                    Text("\(tag.transactions.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
                .tag(tag)
                .contextMenu {
                    Button { editingTag = tag } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) {
                        if selectedTag?.id == tag.id { selectedTag = nil }
                        context.delete(tag)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Tag Detail

    private func tagDetail(_ tag: Tag) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: tag.colorHex))
                    .frame(width: 16, height: 16)
                Text(tag.name)
                    .font(.title3.weight(.semibold))

                Spacer()

                let total = tag.transactions.reduce(Decimal.zero) { $0 + $1.amount }
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(tag.transactions.count) transactions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CurrencyFormatter.shared.format(total))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(total >= 0 ? .green : .red)
                }
            }
            .padding()

            Divider()

            // Transaction list
            List {
                ForEach(tag.transactions.sorted(by: { $0.date > $1.date })) { txn in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(txn.title)
                                .font(.subheadline)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Text(txn.date, style: .date)
                                if let cat = txn.category {
                                    Text("·")
                                    Text(cat.name)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(CurrencyFormatter.shared.format(txn.amount))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(txn.amount < 0 ? .red : .green)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            txn.tags.removeAll { $0.id == tag.id }
                        } label: {
                            Label("Remove Tag", systemImage: "tag.slash")
                        }
                        .tint(.orange)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tag")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Tags Yet")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Tags let you organise transactions across categories.\nFor example: \"Holiday\", \"Tax Deductible\", or \"Business\".")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button { showingAddTag = true } label: {
                Label("Create Tag", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent(for: scheme))
        }
        .padding(40)
    }
}

// MARK: - Edit Tag Sheet

struct EditTagSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let tag: Tag?

    @State private var name = ""
    @State private var colorHex = "D9B138"

    private let colors = ["D9B138", "34C759", "FF3B30", "007AFF", "FF9500",
                          "AF52DE", "FF2D55", "5AC8FA", "64D2FF", "FFD60A",
                          "30D158", "BF5AF2", "AC8E68"]

    init(tag: Tag? = nil) {
        self.tag = tag
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tag Name") {
                    TextField("Name", text: $name)
                }

                Section("Colour") {
                    HStack(spacing: 8) {
                        ForEach(colors, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle().strokeBorder(.white, lineWidth: colorHex == hex ? 2.5 : 0)
                                )
                                .shadow(color: colorHex == hex ? Color(hex: hex).opacity(0.5) : .clear, radius: 4)
                                .onTapGesture { colorHex = hex }
                        }
                    }
                }

                // Preview
                Section("Preview") {
                    HStack(spacing: 8) {
                        Image(systemName: "tag.fill")
                            .foregroundStyle(Color(hex: colorHex))
                        Text(name.isEmpty ? "Tag Name" : name)
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: colorHex).opacity(0.12), in: Capsule())
                }
            }
            .formStyle(.grouped)
            .navigationTitle(tag == nil ? "New Tag" : "Edit Tag")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty)
                }
            }
            .onAppear {
                if let t = tag {
                    name = t.name
                    colorHex = t.colorHex
                }
            }
        }
        .macOSSheet(width: 520, height: 400)
    }

    private func save() {
        if let t = tag {
            t.name = name
            t.colorHex = colorHex
        } else {
            let t = Tag(name: name, colorHex: colorHex)
            context.insert(t)
        }
        dismiss()
    }
}
