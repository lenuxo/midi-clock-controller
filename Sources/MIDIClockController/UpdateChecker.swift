import AppLocalization
import AppKit
import Combine
import Foundation
import Sparkle

struct ReleaseVersion: Comparable {
    let components: [UInt64]
    let isPrerelease: Bool

    init?(_ value: String) {
        let version = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let withoutBuild = version.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let parts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3 else { return nil }
        let parsed = numbers.compactMap { number -> UInt64? in
            guard !number.isEmpty, number.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return UInt64(number)
        }
        guard parsed.count == 3 else { return nil }
        components = parsed
        isPrerelease = parts.count == 2
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.components != rhs.components { return lhs.components.lexicographicallyPrecedes(rhs.components) }
        return lhs.isPrerelease && !rhs.isPrerelease
    }
}

struct GitHubRelease: Decodable {
    let tagName: String
    let body: String?
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]?

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name, browserDownloadURL = "browser_download_url"
        }
    }

    var updateFeedURL: URL? {
        assets?.first {
            $0.name == "appcast.xml" && $0.browserDownloadURL.scheme == "https"
                && $0.browserDownloadURL.host == "github.com"
                && $0.browserDownloadURL.path.hasPrefix("/lenuxo/midi-clock-controller/releases/download/")
                && $0.browserDownloadURL.user == nil && $0.browserDownloadURL.password == nil
                && $0.browserDownloadURL.port == nil
        }?.browserDownloadURL
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", htmlURL = "html_url", body, draft, prerelease, assets
    }
}

enum UpdateResult {
    case available(GitHubRelease)
    case current
    case noRelease
}

enum UpdateCheckError: LocalizedError {
    case invalidVersion, invalidResponse, rateLimited, server(Int)

    var errorDescription: String? {
        switch self {
        case .invalidVersion: return L("无法识别版本号，请到 GitHub Release 页面查看版本。")
        case .invalidResponse: return L("GitHub 返回的版本信息无效，请稍后重试。")
        case .rateLimited: return L("GitHub 请求次数已达上限，请稍后重试。")
        case .server(let status): return L("GitHub 暂时无法完成请求（HTTP %1$@），请稍后重试。", String(status))
        }
    }
}

struct ReleaseChecker {
    static let latestURL = URL(string: "https://api.github.com/repos/lenuxo/midi-clock-controller/releases/latest")!
    let load: (URLRequest) async throws -> (Data, URLResponse)

    init(load: @escaping (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }) {
        self.load = load
    }

    func check(currentVersion: String) async throws -> UpdateResult {
        guard let current = ReleaseVersion(currentVersion) else { throw UpdateCheckError.invalidVersion }
        var request = URLRequest(url: Self.latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MIDI-Clock-Controller", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await load(request)
        guard let response = response as? HTTPURLResponse else { throw UpdateCheckError.invalidResponse }
        switch response.statusCode {
        case 200: break
        case 404: return .noRelease
        case 403, 429: throw UpdateCheckError.rateLimited
        default: throw UpdateCheckError.server(response.statusCode)
        }
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
              !release.draft, !release.prerelease,
              let latest = ReleaseVersion(release.tagName), !latest.isPrerelease,
              release.htmlURL.scheme == "https", release.htmlURL.host == "github.com",
              release.htmlURL.user == nil, release.htmlURL.password == nil, release.htmlURL.port == nil,
              release.htmlURL.path.hasPrefix("/lenuxo/midi-clock-controller/releases/tag/"),
              release.htmlURL.lastPathComponent != "tag" else { throw UpdateCheckError.invalidResponse }
        return latest > current ? .available(release) : .current
    }
}

@MainActor
final class UpdateChecker: NSObject, ObservableObject, SPUUpdaterDelegate {
    var beforeInstallation: () -> Void = {}
    private var selectedFeedURL: URL?
    private lazy var installer = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    private var installerStarted = false

    private func startInstaller(feed: URL) throws {
        selectedFeedURL = feed
        if !installerStarted {
            try installer.updater.start()
            installerStarted = true
        }
        isPresenting = true
        installer.checkForUpdates(nil)
    }

    func feedURLString(for updater: SPUUpdater) -> String? { selectedFeedURL?.absoluteString }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        beforeInstallation()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        isPresenting = false
    }

    @Published private(set) var isChecking = false
    @Published private(set) var isPresenting = false

    func check() {
        guard !isChecking, !isPresenting else { return }
        #if DEBUG
        // The isolated preview can exercise a signed local update without
        // joining Link, creating MIDI ports, or touching the real application.
        if Bundle.main.bundleIdentifier == "local.midi-clock-controller.preview",
           let value = ProcessInfo.processInfo.environment["MIDI_CLOCK_UPDATE_FEED"],
           let feed = URL(string: value) {
            do { try startInstaller(feed: feed) }
            catch { NSLog("Update preview: %@", error.localizedDescription) }
            return
        }
        #endif
        isChecking = true
        Task { [self] in
            let alert = NSAlert()
            var releaseURL: URL?
            do {
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                switch try await ReleaseChecker().check(currentVersion: version) {
                case .available(let release):
                    if let feed = release.updateFeedURL {
                        try startInstaller(feed: feed)
                        isChecking = false
                        return
                    }
                    alert.messageText = L("发现新版本 %1$@", release.tagName)
                    alert.informativeText = L("当前版本 %1$@。前往 GitHub 查看此版本并下载安装。", version)
                    alert.accessoryView = releaseNotes(release.body)
                    alert.addButton(withTitle: L("前往下载"))
                    alert.addButton(withTitle: L("稍后"))
                    releaseURL = release.htmlURL
                case .current:
                    alert.messageText = L("已是最新版本")
                    alert.informativeText = L("当前版本 %1$@，暂无更新的正式版本。", version)
                    alert.addButton(withTitle: L("好"))
                case .noRelease:
                    alert.messageText = L("暂无可用版本")
                    alert.informativeText = L("仓库尚未发布可用的正式版本，请稍后再检查。")
                    alert.addButton(withTitle: L("好"))
                }
            } catch {
                alert.alertStyle = .warning
                alert.messageText = L("无法检查更新")
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: L("好"))
            }
            isChecking = false
            guard let window = NSApp.mainWindow else { return }
            isPresenting = true
            alert.beginSheetModal(for: window) { [weak self] response in
                self?.isPresenting = false
                if response == .alertFirstButtonReturn, let releaseURL {
                    NSWorkspace.shared.open(releaseURL)
                }
            }
        }
    }

    private func releaseNotes(_ body: String?) -> NSView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: 200))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let text = NSTextView(frame: scroll.contentView.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.font = .systemFont(ofSize: 12)
        text.textContainerInset = NSSize(width: 8, height: 8)
        text.autoresizingMask = [.width]
        text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true
        let notes = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        text.string = notes.isEmpty ? L("此版本未提供更新说明。") : notes
        text.setAccessibilityLabel(L("更新说明"))
        scroll.documentView = text
        return scroll
    }
}
