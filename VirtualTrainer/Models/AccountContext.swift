import Foundation
import Combine

@MainActor
final class AccountContext: ObservableObject {
    @Published private(set) var currentAccountId: String?

    nonisolated deinit {}

    var isLocalOnly: Bool {
        currentAccountId == nil
    }

    func setAccount(_ accountId: String?) {
        currentAccountId = AccountOwnership.normalizedAccountId(accountId)
    }

    func clearAccount() {
        currentAccountId = nil
    }
}

nonisolated enum AccountOwnership {
    static func normalizedAccountId(_ accountId: String?) -> String? {
        guard let accountId else { return nil }
        let trimmed = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func isVisible(recordAccountId: String?, currentAccountId: String?) -> Bool {
        let normalizedRecordAccountId = normalizedAccountId(recordAccountId)
        guard let normalizedCurrentAccountId = normalizedAccountId(currentAccountId) else {
            return normalizedRecordAccountId == nil
        }
        return normalizedRecordAccountId == nil ||
            normalizedRecordAccountId == normalizedCurrentAccountId
    }

    static func storageKey(accountId: String?, recordId: String) -> String {
        "\(normalizedAccountId(accountId) ?? "__local__")|\(recordId)"
    }
}
