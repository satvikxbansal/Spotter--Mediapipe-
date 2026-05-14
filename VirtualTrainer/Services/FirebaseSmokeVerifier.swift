#if DEBUG
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import OSLog

struct FirebaseSmokeRunResult: Equatable {
    enum Status: String {
        case pass
        case fail
        case unavailable
    }

    let status: Status
    let message: String

    var isSuccess: Bool {
        status == .pass
    }

    var inlineMessage: String {
        switch status {
        case .pass:
            return "PASS: \(message)"
        case .fail:
            return "FAIL: \(message)"
        case .unavailable:
            return "UNAVAILABLE: \(message)"
        }
    }
}

enum FirebaseSmokeVerifier {
    static let launchArgument = "--firebase-smoke-test"
    static let environmentKey = "VIRTUALTRAINER_FIREBASE_SMOKE_TEST"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "satvik.VirtualTrainer",
        category: "FirebaseSmoke"
    )
    private static let resultFileName = "FirebaseSmokeResult.json"
    private static let smokeCollection = "debugFirebaseSmoke"
    private static let authTimeoutSeconds: TimeInterval = 20
    private static let firestoreTimeoutSeconds: TimeInterval = 25

    static func runIfRequested(processInfo: ProcessInfo = .processInfo) {
        guard shouldRun(processInfo: processInfo) else { return }

        Task {
            _ = await run()
        }
    }

    private static func shouldRun(processInfo: ProcessInfo) -> Bool {
        processInfo.arguments.contains(launchArgument)
            || processInfo.environment[environmentKey] == "1"
    }

    static func run() async -> FirebaseSmokeRunResult {
        let bootstrapState = FirebaseBootstrap.configureIfAvailable()
        guard bootstrapState == .configured || bootstrapState == .alreadyConfigured else {
            let message = "Firebase setup is \(bootstrapState.displayName)."
            logger.warning("Firebase smoke test requested but Firebase is unavailable: \(message, privacy: .public)")
            return FirebaseSmokeRunResult(status: .unavailable, message: message)
        }

        let startedAt = Date()
        logger.notice("Firebase smoke test requested")

        do {
            guard let app = FirebaseApp.app() else {
                throw FirebaseSmokeError.firebaseAppUnavailable
            }

            let options = app.options
            let user = try await withTimeout(seconds: authTimeoutSeconds, operationName: "anonymous auth") {
                try await signInAnonymouslyIfNeeded()
            }
            guard user.isAnonymous else {
                throw FirebaseSmokeError.signedInUserIsNotAnonymous(uid: user.uid)
            }

            let firestorePath = "\(smokeCollection)/\(user.uid)"
            let nonce = UUID().uuidString
            let database = Firestore.firestore()
            let document = database.collection(smokeCollection).document(user.uid)

            try await withTimeout(seconds: firestoreTimeoutSeconds, operationName: "Firestore smoke write") {
                try await setSmokeDocument(
                    document,
                    uid: user.uid,
                    nonce: nonce,
                    projectID: options.projectID ?? "unknown"
                )
            }

            let snapshot = try await withTimeout(seconds: firestoreTimeoutSeconds, operationName: "Firestore smoke read") {
                try await getDocument(document)
            }
            guard snapshot.exists else {
                throw FirebaseSmokeError.firestoreDocumentMissing(path: firestorePath)
            }

            let data = snapshot.data() ?? [:]
            guard data["nonce"] as? String == nonce else {
                throw FirebaseSmokeError.firestoreRoundTripMismatch(path: firestorePath)
            }

            let result = FirebaseSmokeResult(
                status: "pass",
                message: "Firebase anonymous auth and Firestore write/read smoke test passed.",
                projectID: options.projectID ?? "unknown",
                googleAppID: options.googleAppID,
                bundleID: Bundle.main.bundleIdentifier ?? "unknown",
                uid: user.uid,
                isAnonymous: user.isAnonymous,
                firestorePath: firestorePath,
                nonce: nonce,
                startedAt: startedAt,
                finishedAt: Date()
            )
            writeResult(result)
            logger.notice("Firebase smoke test passed uid=\(user.uid, privacy: .private) path=\(firestorePath, privacy: .public)")
            print("[FirebaseSmoke] PASS")
            return FirebaseSmokeRunResult(
                status: .pass,
                message: "Firebase anonymous auth and Firestore write/read smoke test passed."
            )
        } catch {
            let message = sanitizedDescription(for: error)
            let result = FirebaseSmokeResult(
                status: "fail",
                message: message,
                projectID: FirebaseApp.app()?.options.projectID ?? "unknown",
                googleAppID: FirebaseApp.app()?.options.googleAppID ?? "unknown",
                bundleID: Bundle.main.bundleIdentifier ?? "unknown",
                uid: Auth.auth().currentUser?.uid,
                isAnonymous: Auth.auth().currentUser?.isAnonymous,
                firestorePath: nil,
                nonce: nil,
                startedAt: startedAt,
                finishedAt: Date()
            )
            writeResult(result)
            logger.error("Firebase smoke test failed: \(message, privacy: .public)")
            print("[FirebaseSmoke] FAIL \(message)")
            return FirebaseSmokeRunResult(status: .fail, message: message)
        }
    }

    private static func signInAnonymouslyIfNeeded() async throws -> User {
        if let user = Auth.auth().currentUser {
            return user
        }

        return try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signInAnonymously { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let user = result?.user {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(throwing: FirebaseSmokeError.authReturnedNoUser)
                }
            }
        }
    }

    private static func setSmokeDocument(
        _ document: DocumentReference,
        uid: String,
        nonce: String,
        projectID: String
    ) async throws {
        let payload: [String: Any] = [
            "uid": uid,
            "nonce": nonce,
            "projectID": projectID,
            "bundleID": Bundle.main.bundleIdentifier ?? "unknown",
            "platform": "ios",
            "source": "VirtualTrainer debug Firebase smoke verifier",
            "createdAt": FieldValue.serverTimestamp(),
            "clientVerifiedAt": Timestamp(date: Date())
        ]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.setData(payload, merge: true) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func getDocument(_ document: DocumentReference) async throws -> DocumentSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            document.getDocument { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: FirebaseSmokeError.firestoreReturnedNoSnapshot)
                }
            }
        }
    }

    private static func withTimeout<T>(
        seconds: TimeInterval,
        operationName: String,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let gate = TimeoutContinuationGate<T>()

        return try await withCheckedThrowingContinuation { continuation in
            let operationTask = Task {
                do {
                    let value = try await operation()
                    await gate.resume(continuation, with: .success(value))
                } catch {
                    await gate.resume(continuation, with: .failure(error))
                }
            }

            Task {
                do {
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                } catch {
                    operationTask.cancel()
                    return
                }

                operationTask.cancel()
                await gate.resume(
                    continuation,
                    with: .failure(FirebaseSmokeError.operationTimedOut(name: operationName, seconds: seconds))
                )
            }
        }
    }

    private static func writeResult(_ result: FirebaseSmokeResult) {
        do {
            let directory = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let url = directory.appendingPathComponent(resultFileName)
            let data = try JSONEncoder.firebaseSmokeEncoder.encode(result)
            try data.write(to: url, options: [.atomic])
        } catch {
            logger.error("Failed to write Firebase smoke result: \(String(describing: error), privacy: .public)")
        }
    }

    private static func sanitizedDescription(for error: Error) -> String {
        String(describing: error)
            .replacingOccurrences(
                of: #"key=AIza[0-9A-Za-z_-]+"#,
                with: "key=<redacted>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"AIza[0-9A-Za-z_-]+"#,
                with: "<redacted-google-api-key>",
                options: .regularExpression
            )
    }
}

private actor TimeoutContinuationGate<T> {
    private var didResume = false

    func resume(
        _ continuation: CheckedContinuation<T, Error>,
        with result: Result<T, Error>
    ) {
        guard !didResume else { return }
        didResume = true

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private struct FirebaseSmokeResult: Codable {
    let status: String
    let message: String
    let projectID: String
    let googleAppID: String
    let bundleID: String
    let uid: String?
    let isAnonymous: Bool?
    let firestorePath: String?
    let nonce: String?
    let startedAt: Date
    let finishedAt: Date
}

private enum FirebaseSmokeError: Error, CustomStringConvertible {
    case firebaseAppUnavailable
    case authReturnedNoUser
    case signedInUserIsNotAnonymous(uid: String)
    case firestoreReturnedNoSnapshot
    case firestoreDocumentMissing(path: String)
    case firestoreRoundTripMismatch(path: String)
    case operationTimedOut(name: String, seconds: TimeInterval)

    var description: String {
        switch self {
        case .firebaseAppUnavailable:
            return "FirebaseApp is unavailable after configuration."
        case .authReturnedNoUser:
            return "Anonymous Auth completed without returning a user."
        case .signedInUserIsNotAnonymous(let uid):
            return "Current Firebase user is not anonymous. uid=\(uid)"
        case .firestoreReturnedNoSnapshot:
            return "Firestore getDocument completed without a snapshot."
        case .firestoreDocumentMissing(let path):
            return "Firestore smoke document does not exist at \(path)."
        case .firestoreRoundTripMismatch(let path):
            return "Firestore smoke document nonce did not round-trip at \(path)."
        case .operationTimedOut(let name, let seconds):
            return "\(name) did not complete within \(Int(seconds)) seconds."
        }
    }
}

private extension JSONEncoder {
    static var firebaseSmokeEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
#endif
