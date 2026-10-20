import Foundation

public enum AppLanguage {
    // Freeze the language for this launch so native menus and application text stay consistent.
    public static let current = resolve(
        UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
    )

    public static func resolve(_ preferred: [String]) -> String {
        for language in preferred {
            if language.hasPrefix("zh") { return "zh-Hans" }
            if language.hasPrefix("en") { return "en" }
        }
        return "zh-Hans"
    }

    public static func text(_ key: String, language: String) -> String {
        guard let path = Bundle.module.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

/// Shared by UI and CoreMIDI diagnostics; independent of SwiftUI and clock scheduling.
public func L(_ key: String, _ arguments: String...) -> String {
    let format = AppLanguage.text(key, language: AppLanguage.current)
    guard !arguments.isEmpty else { return format }
    return String(format: format, locale: Locale(identifier: AppLanguage.current), arguments: arguments)
}
