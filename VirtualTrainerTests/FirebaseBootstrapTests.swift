import FirebaseCore
import XCTest
@testable import VirtualTrainer

@MainActor
final class FirebaseBootstrapTests: XCTestCase {
    func testConfigureIfAvailableReturnsMissingConfigWhenTestBundleHasNoPlist() {
        let state = FirebaseBootstrap.configureIfAvailable(
            in: Bundle(for: FirebaseBootstrapTests.self),
            isAppConfigured: { false },
            optionsLoader: { _ in
                XCTFail("Options should not be loaded when the plist is missing.")
                return nil
            },
            configurator: { _ in
                XCTFail("Firebase should not be configured when the plist is missing.")
            }
        )

        XCTAssertEqual(state, .missingConfig)
    }

    func testConfigureIfAvailableReturnsAlreadyConfiguredOnSecondCall() throws {
        let fixture = try makeTemporaryBundleWithFirebasePlist()
        defer { try? FileManager.default.removeItem(at: fixture.bundleURL) }

        var isConfigured = false
        let firstState = FirebaseBootstrap.configureIfAvailable(
            in: fixture.bundle,
            isAppConfigured: { isConfigured },
            optionsLoader: { _ in Self.makeOptions() },
            configurator: { _ in isConfigured = true }
        )
        let secondState = FirebaseBootstrap.configureIfAvailable(
            in: fixture.bundle,
            isAppConfigured: { isConfigured },
            optionsLoader: { _ in
                XCTFail("Options should not be loaded once Firebase is configured.")
                return nil
            },
            configurator: { _ in
                XCTFail("Firebase should not be configured twice.")
            }
        )

        XCTAssertEqual(firstState, .configured)
        XCTAssertEqual(secondState, .alreadyConfigured)
    }

    func testFailedReasonDoesNotContainFakedPlistPath() throws {
        let fixture = try makeTemporaryBundleWithFirebasePlist()
        defer { try? FileManager.default.removeItem(at: fixture.bundleURL) }

        let fakeAPIKey = "AI" + "za" + String(repeating: "A", count: 35)
        let error = NSError(
            domain: "FirebaseBootstrapTests.\(fixture.plistURL.path).\(fakeAPIKey)",
            code: 17,
            userInfo: [
                NSLocalizedDescriptionKey: "Failed from \(fixture.plistURL.path) with \(fakeAPIKey)"
            ]
        )
        let state = FirebaseBootstrap.configureIfAvailable(
            in: fixture.bundle,
            isAppConfigured: { false },
            optionsLoader: { _ in Self.makeOptions() },
            configurator: { _ in throw error }
        )

        let reason = try failedReason(from: state)

        XCTAssertFalse(reason.contains(fixture.plistURL.path))
    }

    func testFailedReasonDoesNotContainSecretLikeGoogleAPIKey() throws {
        let fixture = try makeTemporaryBundleWithFirebasePlist()
        defer { try? FileManager.default.removeItem(at: fixture.bundleURL) }

        let fakeAPIKey = "AI" + "za" + String(repeating: "B", count: 35)
        let error = NSError(domain: "FirebaseBootstrapTests.\(fakeAPIKey)", code: 23)
        let state = FirebaseBootstrap.configureIfAvailable(
            in: fixture.bundle,
            isAppConfigured: { false },
            optionsLoader: { _ in Self.makeOptions() },
            configurator: { _ in throw error }
        )

        let reason = try failedReason(from: state)
        let regex = try NSRegularExpression(pattern: #"AIza[0-9A-Za-z\-_]{35}"#)
        let range = NSRange(reason.startIndex..<reason.endIndex, in: reason)

        XCTAssertNil(regex.firstMatch(in: reason, range: range))
    }
}

private extension FirebaseBootstrapTests {
    struct BundleFixture {
        let bundle: Bundle
        let bundleURL: URL
        let plistURL: URL
    }

    static func makeOptions() -> FirebaseOptions {
        FirebaseOptions(googleAppID: "1:123456789:ios:placeholderapp", gcmSenderID: "123456789")
    }

    func failedReason(from state: FirebaseBootstrapState) throws -> String {
        guard case .failed(let reason) = state else {
            XCTFail("Expected .failed, got \(state)")
            return ""
        }

        return reason
    }

    func makeTemporaryBundleWithFirebasePlist() throws -> BundleFixture {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FirebaseBootstrapTests-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let infoURL = bundleURL.appendingPathComponent("Info.plist")
        let infoContents = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.spotter.FirebaseBootstrapTests</string>
            <key>CFBundlePackageType</key>
            <string>BNDL</string>
        </dict>
        </plist>
        """
        try Data(infoContents.utf8).write(to: infoURL, options: .atomic)

        let plistURL = bundleURL.appendingPathComponent("GoogleService-Info.plist")
        let plistContents = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict/>
        </plist>
        """
        try Data(plistContents.utf8).write(to: plistURL, options: .atomic)

        let bundle = try XCTUnwrap(Bundle(url: bundleURL))
        return BundleFixture(bundle: bundle, bundleURL: bundleURL, plistURL: plistURL)
    }
}
