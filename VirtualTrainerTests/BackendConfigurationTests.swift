import XCTest
@testable import VirtualTrainer

final class BackendConfigurationTests: XCTestCase {
    func testDesiredModeDefaultsToLocal() {
        let defaults = makeUserDefaults()

        let mode = BackendConfiguration.desiredMode(
            bundle: Bundle(for: BackendConfigurationTests.self),
            userDefaults: defaults
        )

        XCTAssertEqual(mode, .local)
    }

    func testDesiredModeReadsFirebaseFromInfoDictionaryInDebug() throws {
        let fixture = try makeTemporaryBundle(backendMode: "firebase")
        defer { try? FileManager.default.removeItem(at: fixture.bundleURL) }

        let mode = BackendConfiguration.desiredMode(
            bundle: fixture.bundle,
            userDefaults: makeUserDefaults()
        )

#if DEBUG
        XCTAssertEqual(mode, .firebase)
#else
        XCTAssertEqual(mode, .local)
#endif
    }

    func testUserDefaultsOverrideWinsInDebug() throws {
        let fixture = try makeTemporaryBundle(backendMode: "local")
        defer { try? FileManager.default.removeItem(at: fixture.bundleURL) }
        let defaults = makeUserDefaults()
        defaults.set(BackendMode.firebase.rawValue, forKey: BackendConfiguration.userDefaultsKey)

        let mode = BackendConfiguration.desiredMode(
            bundle: fixture.bundle,
            userDefaults: defaults
        )

#if DEBUG
        XCTAssertEqual(mode, .firebase)
#else
        XCTAssertEqual(mode, .local)
#endif
    }
}

private extension BackendConfigurationTests {
    struct BundleFixture {
        let bundle: Bundle
        let bundleURL: URL
    }

    func makeUserDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "BackendConfigurationTests-\(UUID().uuidString)")!
        defaults.removeObject(forKey: BackendConfiguration.userDefaultsKey)
        return defaults
    }

    func makeTemporaryBundle(backendMode: String) throws -> BundleFixture {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackendConfigurationTests-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let infoURL = bundleURL.appendingPathComponent("Info.plist")
        let infoContents = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.spotter.BackendConfigurationTests</string>
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
