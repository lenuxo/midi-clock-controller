import Foundation
import XCTest
@testable import AppLocalization

final class LocalizationTests: XCTestCase {
    func testPreferredLanguageResolution() {
        XCTAssertEqual(AppLanguage.resolve(["zh-Hant-TW", "en"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.resolve(["en-GB", "zh-Hans"]), "en")
        XCTAssertEqual(AppLanguage.resolve(["fr", "en-US"]), "en")
        XCTAssertEqual(AppLanguage.resolve([]), "zh-Hans")
    }

    func testResourceCoverageAndFormatArgumentsMatch() throws {
        func strings(_ language: String) throws -> [String: String] {
            let url = try XCTUnwrap(Bundle.module.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language))
            return try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
        }
        let chinese = try strings("zh-Hans")
        let english = try strings("en")
        XCTAssertGreaterThan(chinese.count, 80)
        XCTAssertEqual(Set(chinese.keys), Set(english.keys))
        let placeholders = try NSRegularExpression(pattern: "%[0-9]+\\$@")
        for (key, value) in chinese {
            let translation = try XCTUnwrap(english[key])
            XCTAssertFalse(translation.isEmpty, key)
            XCTAssertNil(translation.range(of: "\\p{Han}", options: .regularExpression), key)
            func arguments(_ text: String) -> [String] {
                placeholders.matches(in: text, range: NSRange(text.startIndex..., in: text))
                    .map { (text as NSString).substring(with: $0.range) }.sorted()
            }
            XCTAssertEqual(arguments(value), arguments(translation), key)
        }
    }

    func testLocalizedStatusAndDeviceNames() {
        XCTAssertEqual(AppLanguage.text("播放中", language: "en"), "Playing")
        XCTAssertEqual(AppLanguage.text("播放中", language: "zh-Hans"), "播放中")
        let format = AppLanguage.text("%1$@ 独立 BPM", language: "en")
        XCTAssertEqual(String(format: format, "鼓机 100%"), "鼓机 100% independent BPM")
    }
}
