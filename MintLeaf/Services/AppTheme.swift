import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AppTheme {
    // MARK: - Accent colours (gold for dark, silver-slate for light)
    static let gold = Color(red: 0.855, green: 0.694, blue: 0.220)
    static let goldLight = Color(red: 0.92, green: 0.80, blue: 0.45)
    static let goldDark = Color(red: 0.65, green: 0.50, blue: 0.12)

    static let silver = Color(red: 0.38, green: 0.42, blue: 0.50)
    static let silverLight = Color(red: 0.50, green: 0.54, blue: 0.62)
    static let silverDark = Color(red: 0.28, green: 0.32, blue: 0.40)

    // MARK: - Dark mode surfaces (warm-tinted for depth)
    static let trueBlack = Color(red: 0.05, green: 0.05, blue: 0.055)
    static let darkSurface = Color(red: 0.09, green: 0.09, blue: 0.095)
    static let darkCard = Color(red: 0.12, green: 0.12, blue: 0.125)
    static let darkCardElevated = Color(red: 0.15, green: 0.15, blue: 0.155)
    static let darkSidebar = Color(red: 0.105, green: 0.105, blue: 0.115)
    static let darkDivider = Color(red: 0.20, green: 0.20, blue: 0.21)

    // MARK: - Light mode surfaces
    static let lightSurface = Color(red: 0.955, green: 0.955, blue: 0.965)
    static let lightCard = Color.white
    static let lightCardElevated = Color(red: 0.99, green: 0.99, blue: 1.0)
    static let lightSidebar = Color(red: 0.915, green: 0.915, blue: 0.928)
    static let lightDivider = Color(red: 0.85, green: 0.85, blue: 0.87)

    // MARK: - Semantic colours
    static let income = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let expense = Color(red: 0.92, green: 0.30, blue: 0.24)
    static let warning = Color(red: 0.95, green: 0.65, blue: 0.15)

    static func accent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? gold : silver
    }

    static func accentGradient(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(colors: [goldLight, gold, goldDark], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            return LinearGradient(colors: [silverLight, silver, silverDark], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    static func cardBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkCard : lightCard
    }

    static func cardElevated(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkCardElevated : lightCardElevated
    }

    static func surfaceBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? trueBlack : lightSurface
    }

    static func sidebarBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkSidebar : lightSidebar
    }

    static func divider(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkDivider : lightDivider
    }
}

struct PremiumCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appHighContrast) private var highContrast

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        scheme == .dark
                            ? AppTheme.accent(for: scheme).opacity(highContrast ? 0.35 : 0.12)
                            : AppTheme.accent(for: scheme).opacity(highContrast ? 0.4 : 0.15),
                        lineWidth: highContrast ? 2 : 1
                    )
            )
            .shadow(
                color: scheme == .light
                    ? Color.black.opacity(0.04)
                    : Color.clear,
                radius: 8, x: 0, y: 2
            )
    }
}

struct PremiumListModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(AppTheme.surfaceBackground(for: scheme))
    }
}

struct HighContrastModifier: ViewModifier {
    @Environment(\.appHighContrast) private var highContrast

    func body(content: Content) -> some View {
        if highContrast {
            content
                .contrast(1.25)
        } else {
            content
        }
    }
}


extension View {
    func premiumCard() -> some View {
        modifier(PremiumCardModifier())
    }

    func premiumList() -> some View {
        modifier(PremiumListModifier())
    }
}

struct OutlineSegmentedPicker<T: Hashable & CaseIterable & Identifiable>: View where T.AllCases: RandomAccessCollection, T: RawRepresentable, T.RawValue == String {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appHighContrast) private var highContrast
    @Binding var selection: T
    let label: String

    private var allItems: [T] { Array(T.allCases) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(allItems.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(AppTheme.accent(for: scheme).opacity(0.2))
                        .frame(width: 1)
                        .padding(.vertical, 6)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selection = item }
                } label: {
                    Text(item.rawValue)
                        .font(.subheadline.weight(selection == item ? .semibold : .regular))
                        .foregroundStyle(selection == item ? AppTheme.accent(for: scheme) : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selection == item ? AppTheme.accent(for: scheme).opacity(0.1) : .clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(selection == item ? AppTheme.accent(for: scheme).opacity(0.4) : .clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppTheme.accent(for: scheme).opacity(highContrast ? 0.4 : 0.12), lineWidth: highContrast ? 2 : 1))
    }
}
