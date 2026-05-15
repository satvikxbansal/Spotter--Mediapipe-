import Combine
import Foundation

nonisolated enum SyncOrchestratorStatus: Equatable {
    case idle
    case syncing
    case deferred
    case failed
    case offline
    case conflict

    var displayName: String {
        switch self {
        case .idle:
            return "Idle"
        case .syncing:
            return "Syncing"
        case .deferred:
            return "Deferred until workout ends"
        case .failed:
            return "Failed"
        case .offline:
            return "Offline"
        case .conflict:
            return "Conflict"
        }
    }
}

@MainActor
final class SyncOrchestrator: ObservableObject {
    @Published private(set) var status: SyncOrchestratorStatus = .idle
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var pendingUploadCount = 0
    @Published private(set) var conflictCount = 0
    @Published private(set) var listenersAttached = false
    @Published private(set) var lastError: String?

    let backendMode: BackendMode

    private var authRepository: (any AuthRepository)?
    private var profileRepository: (any ProfileRepository)?
    private var workoutRepository: (any WorkoutRepository)?
    private var trophyRepository: (any TrophyRepository)?
    private var insightRepository: (any InsightRepository)?
    private var calibrationRepository: (any CalibrationRepository)?
    private var planRepository: (any PlanRepository)?

    private weak var profileStore: OnboardingStore?
    private weak var calibrationStore: CalibrationStore?
    private weak var workoutHistoryStore: WorkoutHistoryStore?
    private weak var trophyStore: TrophyStore?
    private weak var insightStore: InsightStore?
    private var accountIdProvider: (() -> String?)?

    private let conflictsStore: SyncConflictsStore
    private var listenerTasks: [Task<Void, Never>] = []
    private var deferredAction: DeferredSyncAction?
    private var deferredCallbackRegistered = false

    init(
        backendMode: BackendMode = .local,
        conflictsStore: SyncConflictsStore? = nil
    ) {
        self.backendMode = backendMode
        self.conflictsStore = conflictsStore ?? SyncConflictsStore()
        refreshDerivedCounts()
    }

    convenience init(dependencies: AppDependencies) {
        self.init(
            backendMode: dependencies.backendMode,
            authRepository: dependencies.auth,
            profileRepository: dependencies.profile,
            workoutRepository: dependencies.workouts,
            trophyRepository: dependencies.trophies,
            insightRepository: dependencies.insights,
            calibrationRepository: dependencies.calibration,
            planRepository: dependencies.plans
        )
    }

    init(
        backendMode: BackendMode,
        authRepository: (any AuthRepository)? = nil,
        profileRepository: (any ProfileRepository)? = nil,
        workoutRepository: (any WorkoutRepository)? = nil,
        trophyRepository: (any TrophyRepository)? = nil,
        insightRepository: (any InsightRepository)? = nil,
        calibrationRepository: (any CalibrationRepository)? = nil,
        planRepository: (any PlanRepository)? = nil,
        conflictsStore: SyncConflictsStore? = nil
    ) {
        self.backendMode = backendMode
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.workoutRepository = workoutRepository
        self.trophyRepository = trophyRepository
        self.insightRepository = insightRepository
        self.calibrationRepository = calibrationRepository
        self.planRepository = planRepository
        self.conflictsStore = conflictsStore ?? SyncConflictsStore()
        refreshDerivedCounts()
    }

    func configure(
        accountIdProvider: @escaping () -> String?,
        profileStore: OnboardingStore,
        calibrationStore: CalibrationStore,
        workoutHistoryStore: WorkoutHistoryStore,
        trophyStore: TrophyStore,
        insightStore: InsightStore
    ) {
        self.accountIdProvider = accountIdProvider
        self.profileStore = profileStore
        self.calibrationStore = calibrationStore
        self.workoutHistoryStore = workoutHistoryStore
        self.trophyStore = trophyStore
        self.insightStore = insightStore
        refreshDerivedCounts()
    }

    func performFullSync() async throws {
        guard backendMode == .firebase else {
            try await runLocalNoopSync()
            return
        }
        try await performFullSync(accountId: requiredCurrentAccountId())
    }

    func performFullSync(accountId: String) async throws {
        guard try await shouldRunRemoteSync(.full(accountId)) else { return }

        do {
            status = .syncing
            lastError = nil
            try await stopListeners()
            try await pullRemotePass(accountId: accountId)
            try await pushPendingPass(accountId: accountId)
            try await startListenersPass(accountId: accountId)
            lastSyncedAt = Date()
            refreshDerivedCounts()
            status = conflictCount > 0 ? .conflict : .idle
        } catch {
            setFailure(error)
            throw error
        }
    }

    func pullRemote(accountId: String) async throws {
        guard try await shouldRunRemoteSync(.pull(accountId)) else { return }

        do {
            status = .syncing
            lastError = nil
            try await pullRemotePass(accountId: accountId)
            lastSyncedAt = Date()
            refreshDerivedCounts()
            status = conflictCount > 0 ? .conflict : .idle
        } catch {
            setFailure(error)
            throw error
        }
    }

    func pushPendingLocal(accountId: String) async throws {
        guard try await shouldRunRemoteSync(.push(accountId)) else { return }

        do {
            status = .syncing
            lastError = nil
            try await pushPendingPass(accountId: accountId)
            lastSyncedAt = Date()
            refreshDerivedCounts()
            status = conflictCount > 0 ? .conflict : .idle
        } catch {
            setFailure(error)
            throw error
        }
    }

    func startListeners(accountId: String) async throws {
        guard try await shouldRunRemoteSync(.startListeners(accountId)) else { return }

        do {
            lastError = nil
            try await startListenersPass(accountId: accountId)
            refreshDerivedCounts()
            status = conflictCount > 0 ? .conflict : .idle
        } catch {
            setFailure(error)
            throw error
        }
    }

    func stopListeners() async throws {
        listenerTasks.forEach { $0.cancel() }
        listenerTasks = []
        listenersAttached = false
        if backendMode == .local {
            status = .idle
        }
    }

    func observeRemote() async throws {
        guard backendMode == .firebase else {
            try await runLocalNoopSync()
            return
        }
        try await startListeners(accountId: requiredCurrentAccountId())
    }

    func enqueueDirtyWrites() async throws {
        guard backendMode == .firebase else {
            try await runLocalNoopSync()
            return
        }
        try await pushPendingLocal(accountId: requiredCurrentAccountId())
    }

    private func shouldRunRemoteSync(_ action: DeferredSyncAction) async throws -> Bool {
        guard backendMode == .firebase else {
            try await runLocalNoopSync()
            return false
        }
        _ = try normalizedAccountId(action.accountId)

        guard action.isHeavy else { return true }
        guard !WorkoutSessionContext.isLive else {
            deferUntilWorkoutEnds(action)
            return false
        }
        return true
    }

    private func pullRemotePass(accountId: String) async throws {
        let uid = try normalizedAccountId(accountId)
        guard let profileRepository,
              let calibrationRepository,
              let workoutRepository,
              let trophyRepository,
              let insightRepository,
              let planRepository else {
            throw RepositoryError.backendUnavailable
        }

        if let profile = try await profileRepository.loadProfile(accountId: uid) {
            _ = await profileStore?.applyRemoteProfile(profile)
        }

        if let calibrationRecord = try await calibrationRepository.loadCalibrationRecord(accountId: uid) {
            _ = await calibrationStore?.applyRemoteCalibration(calibrationRecord)
        }

        _ = try await planRepository.loadActivePlan(accountId: uid)

        let recentWorkouts = try await workoutRepository.loadRecentWorkouts(
            accountId: uid,
            limit: 80,
            since: nil
        )
        let workoutTombstones = try await loadWorkoutTombstonesIfSupported(
            accountId: uid,
            limit: 80,
            since: nil
        )
        _ = await workoutHistoryStore?.applyRemoteWorkouts(recentWorkouts + workoutTombstones)

        let trophyEvents = try await trophyRepository.loadTrophyEvents(accountId: uid, since: nil)
        _ = await trophyStore?.applyRemoteTrophyEvents(trophyEvents)

        let recentInsights = try await insightRepository.loadRecentInsights(accountId: uid, limit: 80)
        _ = await insightStore?.applyRemoteInsights(recentInsights)

        let deliveryRecords = try await insightRepository.loadDeliveryRecords(accountId: uid)
        _ = await insightStore?.applyRemoteDeliveryRecords(deliveryRecords)

        let engagementRecords = try await insightRepository.loadEngagementRecords(accountId: uid)
        _ = await insightStore?.applyRemoteEngagementRecords(engagementRecords)
    }

    private func pushPendingPass(accountId: String) async throws {
        let uid = try normalizedAccountId(accountId)
        guard let profileRepository,
              let calibrationRepository,
              let workoutRepository,
              let trophyRepository,
              let insightRepository else {
            throw RepositoryError.backendUnavailable
        }

        if let profile = profileStore?.pendingProfileForSync() {
            let operationId = profile.syncMetadata.pendingOperationId ?? UUID()
            do {
                let savedProfile = try await profileRepository.saveProfile(
                    profile,
                    operationId: operationId
                )
                if savedProfile.syncMetadata.syncState == .conflict {
                    await surfaceConflict(
                        accountId: uid,
                        entityKind: .profile,
                        recordId: savedProfile.id.uuidString.lowercased(),
                        serverVersion: savedProfile.syncMetadata.serverVersion,
                        localVersion: profile.syncMetadata.serverVersion,
                        message: "Profile has a remote conflict."
                    )
                    _ = await profileStore?.markProfileConflict(
                        serverVersion: savedProfile.syncMetadata.serverVersion,
                        localVersion: profile.syncMetadata.serverVersion
                    )
                } else {
                    _ = await profileStore?.applyRemoteProfile(
                        savedProfile,
                        allowReplacingPending: true
                    )
                }
            } catch {
                try await handleConflictIfNeeded(
                    error,
                    accountId: uid,
                    entityKind: .profile,
                    recordId: profile.id.uuidString.lowercased(),
                    markLocal: { serverVersion, localVersion in
                        await self.profileStore?.markProfileConflict(
                            serverVersion: serverVersion,
                            localVersion: localVersion
                        ) ?? false
                    }
                )
            }
        }

        if let record = calibrationStore?.pendingCalibrationRecordForSync() {
            let operationId = record.syncMetadata.pendingOperationId ?? UUID()
            do {
                let savedRecord = try await calibrationRepository.saveCalibrationRecord(
                    record,
                    operationId: operationId
                )
                _ = await calibrationStore?.applyRemoteCalibration(
                    savedRecord,
                    allowReplacingPending: true
                )
            } catch {
                try await handleConflictIfNeeded(
                    error,
                    accountId: uid,
                    entityKind: .calibration,
                    recordId: record.id.uuidString.lowercased(),
                    markLocal: { serverVersion, localVersion in
                        await self.calibrationStore?.markCalibrationConflict(
                            serverVersion: serverVersion,
                            localVersion: localVersion
                        ) ?? false
                    }
                )
            }
        }

        for summary in workoutHistoryStore?.pendingWorkoutSummariesForSync() ?? [] {
            let operationId = summary.syncMetadata.pendingOperationId ?? UUID()
            do {
                if summary.isDeleted {
                    try await workoutRepository.deleteWorkout(
                        accountId: uid,
                        id: summary.id,
                        operationId: operationId
                    )
                    _ = await workoutHistoryStore?.markSummarySynced(id: summary.id)
                } else {
                    let savedSummary = try await workoutRepository.saveWorkoutSummary(
                        summary,
                        operationId: operationId
                    )
                    _ = await workoutHistoryStore?.applyRemoteWorkoutCache(savedSummary)
                }
            } catch {
                try await handleConflictIfNeeded(
                    error,
                    accountId: uid,
                    entityKind: .workout,
                    recordId: summary.id.uuidString.lowercased(),
                    markLocal: { serverVersion, localVersion in
                        await self.workoutHistoryStore?.markSummaryConflict(
                            id: summary.id,
                            serverVersion: serverVersion,
                            localVersion: localVersion
                        ) ?? false
                    }
                )
            }
        }

        for event in trophyStore?.pendingTrophyEventsForSync() ?? [] where !event.isRetracted {
            let operationId = event.syncMetadata.pendingOperationId ?? event.id
            do {
                let savedEvent = try await trophyRepository.saveTrophyEvent(
                    event,
                    operationId: operationId
                )
                _ = await trophyStore?.applyRemoteTrophyEvents([savedEvent])
            } catch {
                try await handleConflictIfNeeded(
                    error,
                    accountId: uid,
                    entityKind: .trophyEvent,
                    recordId: event.id.uuidString.lowercased(),
                    markLocal: { serverVersion, localVersion in
                        await self.trophyStore?.markTrophyEventConflict(
                            id: event.id,
                            serverVersion: serverVersion,
                            localVersion: localVersion
                        ) ?? false
                    }
                )
            }
        }

        for insight in insightStore?.pendingInsightsForSync() ?? [] {
            let operationId = insight.syncMetadata.pendingOperationId ?? UUID()
            do {
                let savedInsights = try await insightRepository.saveInsights(
                    [insight],
                    operationId: operationId
                )
                _ = await insightStore?.applyRemoteInsights(
                    savedInsights,
                    allowReplacingPending: true
                )
            } catch {
                try await handleConflictIfNeeded(
                    error,
                    accountId: uid,
                    entityKind: .insight,
                    recordId: insight.dedupeKey,
                    markLocal: { serverVersion, localVersion in
                        await self.insightStore?.markInsightConflict(
                            dedupeKey: insight.dedupeKey,
                            serverVersion: serverVersion,
                            localVersion: localVersion
                        ) ?? false
                    }
                )
            }
        }

        for record in insightStore?.pendingDeliveryRecordsForSync() ?? [] {
            let operationId = record.syncMetadata.pendingOperationId ?? UUID()
            do {
                let savedRecord = try await insightRepository.saveDeliveryRecord(
                    record,
                    operationId: operationId
                )
                _ = await insightStore?.applyRemoteDeliveryRecords(
                    [savedRecord],
                    allowReplacingPending: true
                )
            } catch {
                try await handleConflictIfNeeded(
                    error,
                    accountId: uid,
                    entityKind: .insightDelivery,
                    recordId: record.dedupeKey,
                    markLocal: { serverVersion, localVersion in
                        await self.insightStore?.markDeliveryConflict(
                            dedupeKey: record.dedupeKey,
                            serverVersion: serverVersion,
                            localVersion: localVersion
                        ) ?? false
                    }
                )
            }
        }

        for record in insightStore?.pendingEngagementRecordsForSync() ?? [] {
            let operationId = record.syncMetadata.pendingOperationId ?? UUID()
            do {
                let savedRecord = try await insightRepository.saveEngagementRecord(
                    record,
                    operationId: operationId
                )
                _ = await insightStore?.applyRemoteEngagementRecords(
                    [savedRecord],
                    allowReplacingPending: true
                )
            } catch {
                try await handleConflictIfNeeded(
                    error,
                    accountId: uid,
                    entityKind: .insightEngagement,
                    recordId: record.dedupeKey,
                    markLocal: { serverVersion, localVersion in
                        await self.insightStore?.markEngagementConflict(
                            dedupeKey: record.dedupeKey,
                            serverVersion: serverVersion,
                            localVersion: localVersion
                        ) ?? false
                    }
                )
            }
        }
    }

    private func startListenersPass(accountId: String) async throws {
        let uid = try normalizedAccountId(accountId)
        guard let profileRepository,
              let workoutRepository,
              let trophyRepository,
              let insightRepository else {
            throw RepositoryError.backendUnavailable
        }

        try await stopListeners()

        let profileStream = try await profileRepository.observeProfile(accountId: uid)
        listenerTasks.append(Task { [weak self] in
            for await profile in profileStream {
                guard let profile else { continue }
                await self?.applyListenerProfile(profile)
            }
        })

        let workoutStream = try await workoutRepository.observeRecentWorkouts(accountId: uid, limit: 80)
        listenerTasks.append(Task { [weak self] in
            for await workouts in workoutStream {
                await self?.applyListenerWorkouts(workouts, accountId: uid)
            }
        })

        let trophyStream = try await trophyRepository.observeTrophyEvents(accountId: uid)
        listenerTasks.append(Task { [weak self] in
            for await events in trophyStream {
                await self?.applyListenerTrophyEvents(events)
            }
        })

        let insightStream = try await insightRepository.observeRecentInsights(accountId: uid, limit: 80)
        listenerTasks.append(Task { [weak self] in
            for await insights in insightStream {
                await self?.applyListenerInsights(insights)
            }
        })

        listenersAttached = true
    }

    private func applyListenerProfile(_ profile: UserProfile) async {
        _ = await profileStore?.applyRemoteProfile(profile)
        markListenerEmissionApplied()
    }

    private func applyListenerWorkouts(_ workouts: [WorkoutSessionSummary], accountId: String) async {
        do {
            let tombstones = try await loadWorkoutTombstonesIfSupported(
                accountId: accountId,
                limit: 80,
                since: nil
            )
            _ = await workoutHistoryStore?.applyRemoteWorkouts(workouts + tombstones)
        } catch {
            setFailure(error)
            return
        }
        markListenerEmissionApplied()
    }

    private func applyListenerTrophyEvents(_ events: [TrophyUnlockEvent]) async {
        _ = await trophyStore?.applyRemoteTrophyEvents(events)
        markListenerEmissionApplied()
    }

    private func applyListenerInsights(_ insights: [AIInsight]) async {
        _ = await insightStore?.applyRemoteInsights(insights)
        markListenerEmissionApplied()
    }

    private func markListenerEmissionApplied() {
        lastSyncedAt = Date()
        refreshDerivedCounts()
    }

    private func loadWorkoutTombstonesIfSupported(
        accountId: String,
        limit: Int,
        since: Date?
    ) async throws -> [WorkoutSessionSummary] {
        guard let tombstoneRepository = workoutRepository as? WorkoutTombstoneRepository else {
            return []
        }
        return try await tombstoneRepository.loadRecentWorkoutTombstones(
            accountId: accountId,
            limit: limit,
            since: since
        )
    }

    private func handleConflictIfNeeded(
        _ error: Error,
        accountId: String,
        entityKind: WriteEntityKind,
        recordId: String,
        markLocal: (String?, String?) async -> Bool
    ) async throws {
        guard let repositoryError = error as? RepositoryError,
              case let .conflict(serverVersion, localVersion) = repositoryError else {
            throw error
        }

        _ = await markLocal(serverVersion, localVersion)
        await surfaceConflict(
            accountId: accountId,
            entityKind: entityKind,
            recordId: recordId,
            serverVersion: serverVersion,
            localVersion: localVersion,
            message: "\(entityKind.rawValue) has a remote conflict."
        )
    }

    private func surfaceConflict(
        accountId: String,
        entityKind: WriteEntityKind,
        recordId: String,
        serverVersion: String?,
        localVersion: String?,
        message: String
    ) async {
        _ = await conflictsStore.record(
            SyncConflictEvent(
                accountId: accountId,
                entityKind: entityKind,
                recordId: recordId,
                serverVersion: serverVersion,
                localVersion: localVersion,
                message: message
            )
        )
        refreshDerivedCounts()
        status = .conflict
    }

    private func deferUntilWorkoutEnds(_ action: DeferredSyncAction) {
        deferredAction = action
        status = .deferred
        lastError = nil

        guard !deferredCallbackRegistered else { return }
        deferredCallbackRegistered = true
        WorkoutSessionContext.onWorkoutEnded { [weak self] in
            Task { @MainActor in
                await self?.runDeferredAction()
            }
        }
    }

    private func runDeferredAction() async {
        guard let action = deferredAction else {
            deferredCallbackRegistered = false
            return
        }
        deferredAction = nil
        deferredCallbackRegistered = false

        do {
            switch action {
            case .pull(let accountId):
                try await pullRemote(accountId: accountId)
            case .push(let accountId):
                try await pushPendingLocal(accountId: accountId)
            case .full(let accountId):
                try await performFullSync(accountId: accountId)
            case .startListeners(let accountId):
                try await startListeners(accountId: accountId)
            }
        } catch {
            setFailure(error)
        }
    }

    private func runLocalNoopSync() async throws {
        status = .syncing
        await Task.yield()
        lastSyncedAt = Date()
        lastError = nil
        status = .idle
        refreshDerivedCounts()
    }

    private func requiredCurrentAccountId() throws -> String {
        try normalizedAccountId(accountIdProvider?() ?? authRepository?.currentAccountId)
    }

    private func normalizedAccountId(_ accountId: String?) throws -> String {
        guard let accountId = AccountOwnership.normalizedAccountId(accountId) else {
            throw RepositoryError.accountMissing
        }
        return accountId
    }

    private func setFailure(_ error: Error) {
        status = .failed
        lastError = sanitizedMessage(for: error)
        refreshDerivedCounts()
    }

    private func refreshDerivedCounts() {
        let profilePendingCount = profileStore?.pendingUploadCount ?? 0
        let calibrationPendingCount = calibrationStore?.pendingUploadCount ?? 0
        let workoutPendingCount = workoutHistoryStore?.pendingUploadCount ?? 0
        let trophyPendingCount = trophyStore?.pendingUploadCount ?? 0
        let insightPendingCount = insightStore?.pendingUploadCount ?? 0
        pendingUploadCount = profilePendingCount +
            calibrationPendingCount +
            workoutPendingCount +
            trophyPendingCount +
            insightPendingCount
        conflictCount = conflictsStore.count
    }

    private func sanitizedMessage(for error: Error) -> String {
        let rawMessage: String
        if let repositoryError = error as? RepositoryError {
            switch repositoryError {
            case .notFound:
                rawMessage = "Remote record was not found."
            case .conflict:
                rawMessage = "Remote conflict detected."
            case .unauthorized:
                rawMessage = "Remote account is unauthorized."
            case .network(let message):
                rawMessage = message
            case .invalidPayload(let message):
                rawMessage = message
            case .accountMissing:
                rawMessage = "No account is available for sync."
            case .backendUnavailable:
                rawMessage = "Backend is unavailable."
            }
        } else {
            rawMessage = error.localizedDescription
        }

        return rawMessage
            .replacingOccurrences(
                of: #"AIza[0-9A-Za-z\-_]{35}"#,
                with: "[redacted]",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)(token|secret|api[_-]?key|authorization)\s*[:=]\s*['"]?[A-Za-z0-9_./+=:\-]{12,}"#,
                with: "$1=[redacted]",
                options: .regularExpression
            )
    }
}

private enum DeferredSyncAction {
    case pull(String)
    case push(String)
    case full(String)
    case startListeners(String)

    var accountId: String {
        switch self {
        case .pull(let accountId),
             .push(let accountId),
             .full(let accountId),
             .startListeners(let accountId):
            return accountId
        }
    }

    var isHeavy: Bool {
        switch self {
        case .pull, .push, .full:
            return true
        case .startListeners:
            return false
        }
    }
}
