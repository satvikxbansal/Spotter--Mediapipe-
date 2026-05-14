import Foundation

@MainActor
protocol AccountClaimingStore: AnyObject {
    func setCurrentAccountId(_ accountId: String?)
    func claimLocalDataForAccount(id accountId: String, operationId: UUID?) async -> Bool
}

extension OnboardingStore: AccountClaimingStore {}
extension WorkoutHistoryStore: AccountClaimingStore {}
extension TrophyStore: AccountClaimingStore {}
extension InsightStore: AccountClaimingStore {}
extension CalibrationStore: AccountClaimingStore {}
extension ThemeStore: AccountClaimingStore {}

@MainActor
struct AccountAwareStores {
    private let stores: [any AccountClaimingStore]

    init(
        onboardingStore: OnboardingStore,
        workoutHistoryStore: WorkoutHistoryStore,
        trophyStore: TrophyStore,
        insightStore: InsightStore,
        calibrationStore: CalibrationStore,
        themeStore: ThemeStore
    ) {
        self.init(stores: [
            onboardingStore,
            workoutHistoryStore,
            trophyStore,
            insightStore,
            calibrationStore,
            themeStore
        ])
    }

    init(stores: [any AccountClaimingStore]) {
        self.stores = stores
    }

    func setCurrentAccountId(_ accountId: String?) {
        stores.forEach {
            $0.setCurrentAccountId(accountId)
        }
    }

    @discardableResult
    func claimAll(forAccountId accountId: String, operationId: UUID) async -> Bool {
        guard let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId) else {
            return false
        }

        // The operationId is the parent claim operation. Each store gets a child
        // id because the existing local journal treats operation IDs globally.
        _ = operationId
        setCurrentAccountId(normalizedAccountId)

        var didClaimAll = true
        for store in stores {
            let didClaim = await store.claimLocalDataForAccount(
                id: normalizedAccountId,
                operationId: UUID()
            )
            didClaimAll = didClaimAll && didClaim
        }
        return didClaimAll
    }
}

@MainActor
final class AccountClaimCoordinator {
    let accountContext: AccountContext
    let stores: AccountAwareStores
    let writeJournal: LocalWriteJournal

    init(
        accountContext: AccountContext,
        stores: AccountAwareStores,
        writeJournal: LocalWriteJournal
    ) {
        self.accountContext = accountContext
        self.stores = stores
        self.writeJournal = writeJournal
    }

    func handleAuthChange(_ newUid: String?) async {
        await handleAuthChange(newUid, operationId: UUID())
    }

    func handleAuthChange(_ newUid: String?, operationId: UUID) async {
        accountContext.setAccount(newUid)
        stores.setCurrentAccountId(newUid)
        guard let newUid = AccountOwnership.normalizedAccountId(newUid) else { return }

        _ = await claimLocalData(forAccountId: newUid, operationId: operationId)
    }

    @discardableResult
    func claimLocalDataForCurrentAccount(operationId: UUID = UUID()) async -> Bool {
        guard let accountId = accountContext.currentAccountId else { return false }
        return await claimLocalData(forAccountId: accountId, operationId: operationId)
    }

    @discardableResult
    func claimLocalData(forAccountId accountId: String, operationId: UUID) async -> Bool {
        guard let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId) else {
            return false
        }
        guard !(await writeJournal.contains(operationId: operationId)) else {
            return true
        }

        let didClaimAll = await stores.claimAll(
            forAccountId: normalizedAccountId,
            operationId: operationId
        )
        guard didClaimAll else { return false }

        return await writeJournal.record(
            operationId: operationId,
            entityKind: .profile
        )
    }
}
