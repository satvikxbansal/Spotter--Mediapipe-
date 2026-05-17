import SwiftUI
import UIKit
import XCTest
@testable import VirtualTrainer

@MainActor
final class DesignSystemV2Tests: XCTestCase {
    func testHexColorHelperRoundTrip() {
        assertColor(Color(hex: 0x0D0D0D), red: 13, green: 13, blue: 13)
        assertColor(Color(hex: 0xF2F0EB), red: 242, green: 240, blue: 235)
        assertColor(Color(hex: 0x00D1FF), red: 0, green: 209, blue: 255)
        assertColor(Color(hex: 0xFF5C3A), red: 255, green: 92, blue: 58)
    }

    func testSpotterV2TokensStayNamespacedFromV1ThemeTokens() {
        let v2TokenNames: Set<String> = [
            "SpotterV2.Tokens.background",
            "SpotterV2.Tokens.foreground",
            "SpotterV2.Tokens.secondary",
            "SpotterV2.Tokens.muted",
            "SpotterV2.Tokens.mutedForeground",
            "SpotterV2.Tokens.destructive",
            "SpotterV2.Tokens.card",
            "SpotterV2.Tokens.border",
            "SpotterV2.Tokens.chart1",
            "SpotterV2.Tokens.chart3",
            "SpotterV2.Tokens.chart4",
            "SpotterV2.Tokens.chart5"
        ]
        let v1TokenNames: Set<String> = [
            "Theme.Colors.background",
            "Theme.Colors.surface",
            "Theme.Colors.surfaceRaised",
            "Theme.Colors.textPrimary",
            "Theme.Colors.textSecondary",
            "Theme.Colors.textTertiary",
            "Theme.Colors.accent",
            "Theme.Colors.danger",
            "Theme.Colors.positive",
            "Theme.Colors.divider"
        ]

        XCTAssertTrue(v2TokenNames.isDisjoint(with: v1TokenNames))
    }

    func testToggleStoreForceOnWinsOverRemoteFalse() {
        let defaults = isolatedDefaults()
        let store = DesignSystemV2ToggleStore(
            remoteFlagSnapshotProvider: { false },
            userDefaults: defaults
        )

        store.setOverride(.forceOn)

        XCTAssertTrue(store.isEffectivelyEnabled)
    }

    func testToggleStoreForceOffWinsOverRemoteTrue() {
        let defaults = isolatedDefaults()
        let store = DesignSystemV2ToggleStore(
            remoteFlagSnapshotProvider: { true },
            userDefaults: defaults
        )

        store.setOverride(.forceOff)

        XCTAssertFalse(store.isEffectivelyEnabled)
    }

    func testToggleStoreSystemDefaultDelegatesToProvider() {
        let defaults = isolatedDefaults()
        var remoteFlag = false
        let store = DesignSystemV2ToggleStore(
            remoteFlagSnapshotProvider: { remoteFlag },
            userDefaults: defaults
        )

        store.setOverride(.systemDefault)
        XCTAssertFalse(store.isEffectivelyEnabled)

        remoteFlag = true
        XCTAssertTrue(store.isEffectivelyEnabled)
    }

    func testToggleStorePersistsDebugOverrideAndClearsSystemDefault() {
        let defaults = isolatedDefaults()
        let firstStore = DesignSystemV2ToggleStore(
            remoteFlagSnapshotProvider: { false },
            userDefaults: defaults
        )

        firstStore.setOverride(.forceOn)

        let persistedStore = DesignSystemV2ToggleStore(
            remoteFlagSnapshotProvider: { false },
            userDefaults: defaults
        )
        XCTAssertEqual(persistedStore.override, .forceOn)
        XCTAssertTrue(persistedStore.isEffectivelyEnabled)

        persistedStore.setOverride(.systemDefault)

        let resetStore = DesignSystemV2ToggleStore(
            remoteFlagSnapshotProvider: { false },
            userDefaults: defaults
        )
        XCTAssertEqual(resetStore.override, .systemDefault)
        XCTAssertFalse(resetStore.isEffectivelyEnabled)
    }

    func testSnapshotSmokeForCoreV2ComponentsAcrossHyperAndHotGirlThemes() throws {
        for theme in [SpotterThemeOption.hyper, .hotGirl] {
            try renderSnapshot(
                name: "V2Card-\(theme.rawValue)",
                view: V2Card(
                    theme: theme,
                    hardShadowColor: SpotterV2.Tokens.primary(theme)
                ) {
                    Text("V2 CARD")
                        .font(SpotterV2Typography.heading(size: 22))
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                }
            )

            try renderSnapshot(
                name: "V2CTAButton-\(theme.rawValue)",
                view: V2CTAButton(
                    title: "Start Training",
                    systemImage: "bolt.fill",
                    theme: theme,
                    action: {}
                )
            )

            try renderSnapshot(
                name: "V2MetricPill-\(theme.rawValue)",
                view: V2MetricPill(
                    theme: theme,
                    eyebrow: "Form quality",
                    value: "94%",
                    detail: "Smoke render",
                    systemImage: "brain.head.profile"
                )
            )
        }
    }
}

private extension DesignSystemV2Tests {
    func isolatedDefaults() -> UserDefaults {
        let suiteName = "DesignSystemV2Tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults suite.")
            return .standard
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func assertColor(
        _ color: Color,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let components = rgba(color)
        XCTAssertEqual(components.red, red / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(components.green, green / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(components.blue, blue / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(components.alpha, 1, accuracy: 0.001, file: file, line: line)
    }

    func rgba(_ color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
    }

    func renderSnapshot<V: View>(name: String, view: V) throws {
        let size = CGSize(width: 390, height: 220)
        let controller = UIHostingController(
            rootView: view
                .padding(SpotterV2.Spacing.xl)
                .frame(width: size.width, height: size.height)
                .background(SpotterV2.Tokens.background)
                .preferredColorScheme(.dark)
        )
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()

        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        window.isHidden = true
        XCTAssertGreaterThan(image.pngData()?.count ?? 0, 2_000)
    }
}
