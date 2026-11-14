import Foundation
import XCTest
@testable import MIDIClockController

final class UpdateCheckerTests: XCTestCase {
    private func payload(tag: String = "v0.1.10", notes: String? = "Fix timing\n\n- More details", url: String = "https://github.com/lenuxo/midi-clock-controller/releases/tag/v0.1.10", draft: Bool = false, prerelease: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "tag_name": tag, "body": notes as Any? ?? NSNull(), "html_url": url,
            "draft": draft, "prerelease": prerelease
        ])
    }

    private func checker(data: Data = Data(), status: Int = 200) -> ReleaseChecker {
        ReleaseChecker { request in
            XCTAssertEqual(request.url, ReleaseChecker.latestURL)
            XCTAssertEqual(request.timeoutInterval, 15)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (data, HTTPURLResponse(url: ReleaseChecker.latestURL, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    func testNewReleasePreservesNotesAndExactPage() async throws {
        let result = try await checker(data: payload()).check(currentVersion: "0.1.8")
        guard case .available(let release) = result else { return XCTFail("Expected update") }
        XCTAssertEqual(release.tagName, "v0.1.10")
        XCTAssertEqual(release.body, "Fix timing\n\n- More details")
        XCTAssertEqual(release.htmlURL.path, "/lenuxo/midi-clock-controller/releases/tag/v0.1.10")
    }

    func testNumericVersionsNeverOfferDowngrades() async throws {
        for current in ["0.1.10", "0.2.0", "1.0.0", "0.1.10+9"] {
            let result = try await checker(data: payload()).check(currentVersion: current)
            guard case .current = result else { return XCTFail("Unexpected update for \(current)") }
        }
        let result = try await checker(data: payload()).check(currentVersion: "0.1.10-beta.1")
        guard case .available = result else { return XCTFail("Stable release should replace beta") }
    }

    func testMissingNotesAndNoPublishedRelease() async throws {
        let result = try await checker(data: payload(notes: nil)).check(currentVersion: "0.1.8")
        guard case .available(let release) = result else { return XCTFail("Expected update") }
        XCTAssertNil(release.body)
        let missing = try await checker(status: 404).check(currentVersion: "0.1.8")
        guard case .noRelease = missing else { return XCTFail("Expected no release") }
    }

    func testRejectsUntrustedPagesAndNonStableReleases() async throws {
        let invalid = try [
            payload(url: "https://example.com/download"),
            payload(url: "https://github.com/another/repo/releases/tag/v1.0.0"),
            payload(url: "http://github.com/lenuxo/midi-clock-controller/releases/tag/v1.0.0"),
            payload(draft: true), payload(prerelease: true), payload(tag: "v1.0.0-beta"),
            payload(tag: "not-a-version")
        ] + [Data("bad JSON".utf8)]
        for data in invalid {
            do {
                _ = try await checker(data: data).check(currentVersion: "0.1.8")
                XCTFail("Expected invalid response")
            } catch UpdateCheckError.invalidResponse { }
        }
    }

    func testRateLimitsAndServerErrorsAreReported() async throws {
        for status in [403, 429, 500] {
            do {
                _ = try await checker(status: status).check(currentVersion: "0.1.8")
                XCTFail("Expected HTTP failure")
            } catch let error as UpdateCheckError {
                switch (status, error) {
                case (403, .rateLimited), (429, .rateLimited), (500, .server(500)): break
                default: XCTFail("Unexpected error \(error)")
                }
            }
        }
    }

    func testInstallerRequiresTheRepositoriesAppcastAsset() throws {
        func release(_ url: String, name: String = "appcast.xml") throws -> GitHubRelease {
            var json = try JSONSerialization.jsonObject(with: payload()) as! [String: Any]
            json["assets"] = [["name": name, "browser_download_url": url]]
            return try JSONDecoder().decode(GitHubRelease.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let url = "https://github.com/lenuxo/midi-clock-controller/releases/download/v0.1.10/appcast.xml"
        XCTAssertEqual(try release(url).updateFeedURL?.absoluteString, url)
        XCTAssertNil(try release("http://example.com/appcast.xml").updateFeedURL)
        XCTAssertNil(try release("https://github.com/other/repo/releases/download/v1/appcast.xml").updateFeedURL)
        XCTAssertNil(try release(url, name: "source.zip").updateFeedURL)
        XCTAssertNil(try JSONDecoder().decode(GitHubRelease.self, from: payload()).updateFeedURL)
    }

    func testNetworkFailureAndUnknownLocalVersion() async throws {
        let offline = ReleaseChecker { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await offline.check(currentVersion: "0.1.8")
            XCTFail("Expected offline error")
        } catch let error as URLError { XCTAssertEqual(error.code, .notConnectedToInternet) }
        do {
            _ = try await checker().check(currentVersion: "")
            XCTFail("Expected invalid installed version")
        } catch UpdateCheckError.invalidVersion { }
    }
}
