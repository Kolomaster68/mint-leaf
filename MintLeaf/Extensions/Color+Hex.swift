import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        #if os(macOS)
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = nsColor.redComponent
        let g = nsColor.greenComponent
        let b = nsColor.blueComponent
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: nil)
        #endif
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

private struct HighContrastKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var appHighContrast: Bool {
        get { self[HighContrastKey.self] }
        set { self[HighContrastKey.self] = newValue }
    }

    var appReduceMotion: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }

    var appTextScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}
