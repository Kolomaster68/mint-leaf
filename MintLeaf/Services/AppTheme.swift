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
    static let gold = Color(red: 0.855, green: 0.694, blue: 0.220)
    static let goldLight = Color(red: 0.92, green: 0.80, blue: 0.45)
    static let goldDark = Color(red: 0.65, green: 0.50, blue: 0.12)

    static let silver = Color(red: 0.42, green: 0.44, blue: 0.50)
    static let silverLight = Color(red: 0.55, green: 0.57, blue: 0.63)
    static let silverDark = Color(red: 0.32, green: 0.34, blue: 0.40)

    static let trueBlack = Color(red: 0.06, green: 0.06, blue: 0.06)
    static let darkSurface = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let darkCard = Color(red: 0.13, green: 0.13, blue: 0.13)
    static let darkSidebar = Color(red: 0.08, green: 0.08, blue: 0.08)

    static let lightSurface = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let lightCard = Color.white
    static let lightSidebar = Color(red: 0.94, green: 0.94, blue: 0.95)

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

    static func surfaceBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? trueBlack : lightSurface
    }

    static func sidebarBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkSidebar : lightSidebar
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
                        AppTheme.accent(for: scheme).opacity(highContrast ? 0.4 : 0.15),
                        lineWidth: highContrast ? 2 : 1
                    )
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
