import SwiftUI

/// A calendar-style grid for picking a day of the month (1–31).
/// Days are laid out as a single block of numbers — not a weekday calendar.
struct DayOfMonthPicker: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var selectedDay: Int

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(1...31, id: \.self) { day in
                dayCell(day)
            }
        }
        .padding(.vertical, 4)
    }

    private func dayCell(_ day: Int) -> some View {
        let isSelected = day == selectedDay
        return Button {
            withAnimation(.easeOut(duration: 0.12)) {
                selectedDay = day
            }
        } label: {
            Text("\(day)")
                .font(.subheadline.weight(isSelected ? .bold : .regular).monospacedDigit())
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    Circle()
                        .fill(isSelected ? AppTheme.accent(for: scheme) : Color.secondary.opacity(0.08))
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            day == 29 || day == 30 || day == 31
                                ? Color.secondary.opacity(isSelected ? 0 : 0.18)
                                : Color.clear,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

/// A small caption that explains how end-of-month days behave.
struct DayOfMonthHint: View {
    let day: Int

    var body: some View {
        if day >= 29 {
            Label(
                "In shorter months this falls on the last day.",
                systemImage: "info.circle"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
