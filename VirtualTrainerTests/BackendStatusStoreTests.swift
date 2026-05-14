import XCTest
@testable import VirtualTrainer

@MainActor
final class BackendStatusStoreTests: XCTestCase {
    func testFirebaseDesiredModeWithoutPlistFallsBackToLocalWithMessage() async throws {
        let fixture = try makeTemporaryBundle(backendMode: "firebase")
        defer { try? FileManager.default.removeItem(at: fixture.bundleURL) }

        let store = BackendStatusStore(
            bundle: fixture.bundle,
            userDefaults: makeUserDefaults(),
            firebaseBootstrapper: { _ in .missingConfig }
        )

#if DEBUG
        XCTAssertEqual(store.desiredBackendMode, .firebase)
        XCTAssertEqual(store.firebaseBootstrapState, .missingConfig)
        XCTAssertEqual(store.activeBackendMode, .local)
        XCTAssertNotNil(store.userFacingMessage)
#else
        XCTAssertEqual(store.desiredBackendMode, .local)
        XCTAssertEqual(store.firebaseBootstrapState, .notAttempted)
        XCTAssertEqual(store.activeBackendMode, .local)
#endif
    }
}

private extension BackendStatusStoreTests {
    struct BundleFixture {
        let bundle: Bundle
        let bundleURL: URL
    }

    func makeUserDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "BackendStatusStoreTests-\(UUID().uuidString)")!
        defaults.removeObject(forKey: BackendConfiguration.userDefaultsKey)
        return defaults
    }

    func makeTemporaryBundle(backendMode: String) throws -> BundleFixture {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackendStatusStoreTests-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let infoURL = bundleURL.appendingPathComponent("Info.plist")
        let infoContents = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.spotter.BackendStatusStoreTests</string>
            <key>CFBundlePackageType</key>
            <string>BNDL</string>
            <key>SPOTTER_BACKEND_MODE</key>
            <string>\(backendMode)</string>
        </dict>
        </plist>
        """
        try Data(infoContents.utf8).write(to: infoURL, options: .atomic)

        let bundle = try XCTUnwrap(Bundle(url: bundleURL))
        return BundleFixture(bundle: bundle, bundleURL: bundleURL)
    }
}
