import Foundation

struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let htmlUrl: String
    let body: String?
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlUrl = "html_url"
        case body
        case assets
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

@MainActor @Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let repo = "Kolomaster68/mint-leaf"
    private let currentVersion: String

    var latestRelease: GitHubRelease?
    var updateAvailable = false
    var isChecking = false
    var lastChecked: Date?
    var error: String?

    init() {
        currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var currentVersionDisplay: String { currentVersion }

    var dmgAsset: GitHubAsset? {
        latestRelease?.assets.first { $0.name.hasSuffix(".dmg") }
    }

    var latestVersion: String {
        latestRelease?.tagName.replacingOccurrences(of: "v", with: "") ?? currentVersion
    }

    func checkForUpdates() async {
        isChecking = true
        error = nil

        defer { isChecking = false }

        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            error = "Invalid URL"
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                error = "Could not reach GitHub"
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            latestRelease = release
            lastChecked = Date()

            let latest = release.tagName.replacingOccurrences(of: "v", with: "")
            updateAvailable = isVersion(latest, newerThan: currentVersion)
        } catch {
            self.error = "Failed to check for updates"
        }
    }

    private func isVersion(_ a: String, newerThan b: String) -> Bool {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(aParts.count, bParts.count) {
            let aVal = i < aParts.count ? aParts[i] : 0
            let bVal = i < bParts.count ? bParts[i] : 0
            if aVal > bVal { return true }
            if aVal < bVal { return false }
        }
        return false
    }
}
