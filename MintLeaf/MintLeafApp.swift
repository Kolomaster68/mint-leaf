import SwiftUI
import SwiftData

@main
struct MintLeafApp: App {
    let container: ModelContainer
    @AppStorage("appAppearance") private var appearance: String = AppAppearance.system.rawValue
    @AppStorage("textSizeOffset") private var textSizeOffset: Int = 0
    @AppStorage("highContrastMode") private var highContrastMode = false
    @AppStorage("reduceMotion") private var reduceMotion = false

    static let isDevMode = ProcessInfo.processInfo.arguments.contains("-useSampleData")

    init() {
        let schema = Schema([
            Account.self,
            Transaction.self,
            Category.self,
            Budget.self,
            BudgetItem.self,
            ScheduledTransaction.self,
            CategoryRule.self,
            MerchantAlias.self,
            Goal.self,
            Tag.self,
        ])
        let storeName = Self.isDevMode ? "MintLeaf-dev" : "MintLeaf"
        let config = ModelConfiguration(
            storeName,
            schema: schema,
            cloudKitDatabase: .none
        )
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Migration failed — back up the store before resetting
            let storeURL = config.url
            let backupURL = storeURL.deletingLastPathComponent()
                .appendingPathComponent("MintLeaf-backup-\(Int(Date().timeIntervalSince1970)).store")
            try? FileManager.default.copyItem(at: storeURL, to: backupURL)

            let related = [
                storeURL,
                storeURL.appendingPathExtension("shm"),
                storeURL.appendingPathExtension("wal"),
            ]
            for url in related {
                try? FileManager.default.removeItem(at: url)
            }
            do {
                container = try ModelContainer(for: schema, configurations: [config])
                print("⚠️ SwiftData store was reset due to migration error. Backup saved to \(backupURL.path)")
            } catch {
                fatalError("Failed to configure SwiftData after reset: \(error)")
            }
        }
    }

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appearance) ?? .system
    }

    private var textScale: CGFloat {
        switch textSizeOffset {
        case -2: return 0.85
        case -1: return 0.92
        case 0: return 1.0
        case 1: return 1.1
        case 2: return 1.2
        default: return 1.0
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(selectedAppearance.colorScheme)
                .environment(\.appTextScale, textScale)
                .environment(\.appHighContrast, highContrastMode)
                .environment(\.appReduceMotion, reduceMotion)
                .transaction {
                    if reduceMotion { $0.animation = nil }
                }
                #if os(macOS)
                .onAppear { restoreAppIcon() }
                .overlay(alignment: .topTrailing) {
                    if Self.isDevMode {
                        Text("DEV")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.red, in: Capsule())
                            .padding(8)
                    }
                }
                #endif
        }
        .modelContainer(container)
        .commands { AppCommands() }
        #if os(macOS)
        Settings {
            SettingsView()
                .preferredColorScheme(selectedAppearance.colorScheme)
                .environment(\.appTextScale, textScale)
                .environment(\.appHighContrast, highContrastMode)
        }
        .modelContainer(container)
        #endif
    }

    #if os(macOS)
    private func restoreAppIcon() {
        let style = UserDefaults.standard.string(forKey: "appIconStyle") ?? "system"
        switch style {
        case "light":
            NSApplication.shared.applicationIconImage = renderLeafIcon(isDark: false)
        case "dark":
            NSApplication.shared.applicationIconImage = renderLeafIcon(isDark: true)
        case "custom":
            if let data = UserDefaults.standard.data(forKey: "customIconData"),
               let img = NSImage(data: data) {
                NSApplication.shared.applicationIconImage = img
            }
        default:
            break
        }
    }

    private func renderLeafIcon(isDark: Bool) -> NSImage? {
        let size: CGFloat = 512
        let view = ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(isDark
                    ? Color(red: 0.06, green: 0.06, blue: 0.06)
                    : Color(red: 0.96, green: 0.96, blue: 0.97))
            Image(systemName: "leaf.fill")
                .font(.system(size: size * 0.52, weight: .regular))
                .foregroundStyle(
                    isDark
                        ? AppTheme.accentGradient(for: .dark)
                        : AppTheme.accentGradient(for: .light)
                )
        }
        .frame(width: size, height: size)

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: size, height: size)
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let img = NSImage(size: NSSize(width: size, height: size))
        img.addRepresentation(rep)
        return img
    }
    #endif
}
