import FirebaseAuth
import FirebaseCore
import Foundation

@MainActor
final class FirebaseAuthRepository: AuthRepository {
    var currentAccountId: String? {
        Auth.auth().currentUser?.uid
    }

    func signInAnonymously() async throws -> String {
        if let user = Auth.auth().currentUser {
            return user.uid
        }

        let result = try await Auth.auth().signInAnonymously()
        return result.user.uid
    }

    func linkAnonymousAccountWithApple(idToken: String, nonce: String) async throws -> String {
        // Scaffolding only. The full account-upgrade flow ships in Phase 16I/19.
        throw RepositoryError.backendUnavailable
    }

    func signOut() async throws {
        try Auth.auth().signOut()
        // Do not delete local data on sign-out.
    }

    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw RepositoryError.accountMissing
        }

        // Server-side fan-out lives in Phase 16I via Cloud Functions.
        try await user.delete()
    }

    func observeAuthChanges() async throws -> AsyncStream<String?> {
        AsyncStream { continuation in
            let handle = Auth.auth().addStateDidChangeListener { _, user in
                continuation.yield(user?.uid)
            }
            continuation.onTermination = { _ in
                Task { @MainActor in
                    Auth.auth().removeStateDidChangeListener(handle)
                }
            }
        }
    }
}
