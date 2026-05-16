import FirebaseAppCheck
import FirebaseCore
import Foundation

nonisolated enum FirebaseBootstrapState: Equatable {
    case notAttempted
    case configured
    case missingConfig
    case alreadyConfigured
    case failed(reason: String)
}

nonisolated enum FirebaseBootstrap {
    @discardableResult
    static func configureIfAvailable() -> FirebaseBootstrapState {
        configureIfAvailable(in: .main)
    }

    @discardableResult
    static func configureIfAvailable(
        in bundle: Bundle,
        isAppConfigured: () -> Bool = { FirebaseApp.app() != nil },
        optionsLoader: (String) -> FirebaseOptions? = { FirebaseOptions(contentsOfFile: $0) },
        configurator: (FirebaseOptions) throws -> Void = { FirebaseApp.configure(options: $0) }
    ) -> FirebaseBootstrapState {
        if isAppConfigured() {
            return .alreadyConfigured
        }

        guard let plistURL = bundle.url(forResource: "GoogleService-Info", withExtension: "plist") else {
            return .missingConfig
        }

        guard let options = optionsLoader(plistURL.path) else {
            return .failed(reason: "Firebase client config is present but could not be parsed.")
        }

        do {
#if DEBUG
            AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
#else
            AppCheck.setAppCheckProviderFactory(ReleaseAppCheckProviderFactory())
#endif
            try configurator(options)
        } catch {
            return .failed(reason: sanitizedFailureReason(for: error, plistPath: plistURL.path))
        }

        guard isAppConfigured() else {
            return .failed(reason: "Firebase configuration completed but no Firebase app became available.")
        }

        return .configured
    }

    private static func sanitizedFailureReason(for error: Error, plistPath: String) -> String {
        let nsError = error as NSError
        let domain = sanitized(nsError.domain, plistPath: plistPath)
        return "Firebase configuration failed (domain: \(domain), code: \(nsError.code))."
    }

    private static func sanitized(_ value: String, plistPath: String) -> String {
        var sanitizedValue = value

        if !plistPath.isEmpty {
            sanitizedValue = sanitizedValue.replacingOccurrences(of: plistPath, with: "<redacted-plist-path>")
        }

        let replacements: [(String, String)] = [
            (#"AIza[0-9A-Za-z\-_]{35}"#, "<redacted-google-api-key>"),
            (#"\b\d{1,3}:\d{6,}:ios:[0-9A-Za-z._-]{8,}\b"#, "<redacted-google-app-id>"),
            (#"(?i)(project[_ -]?id\s*[:=]\s*)[A-Za-z0-9-]{6,}"#, "$1<redacted-project-id>"),
            (#"(?i)(google[_ -]?app[_ -]?id\s*[:=]\s*)[0-9A-Za-z:._-]{8,}"#, "$1<redacted-google-app-id>")
        ]

        for (pattern, replacement) in replacements {
            sanitizedValue = sanitizedValue.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }

        return sanitizedValue
    }
}

private final class ReleaseAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        if #available(iOS 14.5, *) {
            return AppAttestProvider(app: app)
        }
        return DeviceCheckProvider(app: app)
    }
}
