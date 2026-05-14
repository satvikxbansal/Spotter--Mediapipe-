import FirebaseCore
import Foundation

enum FirebaseBootstrap {
    @discardableResult
    static func configureIfNeeded() -> Bool {
        if FirebaseApp.app() != nil {
            return true
        }

        guard let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: plistPath) else {
            assertionFailure("GoogleService-Info.plist is missing or invalid; Firebase was not configured.")
            return false
        }

        FirebaseApp.configure(options: options)
        return FirebaseApp.app() != nil
    }
}
