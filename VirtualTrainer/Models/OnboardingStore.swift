import Foundation
import Combine

@MainActor
final class OnboardingStore: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome
        case identity
        case stats
        case goalEquipment
        case coachTheme
        case completion
    }

    @Published private(set) var profile: UserProfile?
    @Published var draft = OnboardingDraft()
    @Published var persistenceError: String?

    private let fileURL: URL
    private let writeJournal: LocalWriteJournal
    private let decoder = JSONDecoder()
    private let persistenceActor: PersistenceActor
    private var currentAccountId: String?
    private var storedProfile: UserProfile?
    private var persistedStoredProfile: UserProfile?
    private var persistenceGeneration = 0
    private var backendMode: BackendMode = .local
    private var profileRepository: (any ProfileRepository)?
    private var profileObservationTask: Task<Void, Never>?
    private var autoObserveRemote = true

    var hasCompletedOnboarding: Bool {
        profile != nil
    }

    init(
        fileURL: URL? = nil,
        accountId: String? = nil,
        writeJournal: LocalWriteJournal? = nil,
        persistenceActor: PersistenceActor = .shared
    ) {
        let resolvedFileURL = fileURL ?? Self.defaultProfileURL()
        self.fileURL = resolvedFileURL
        self.writeJournal = writeJournal ?? LocalWriteJournal(
            fileURL: LocalWriteJournal.defaultJournalURL(alongside: resolvedFileURL),
            persistenceActor: persistenceActor
        )
        self.persistenceActor = persistenceActor
        self.currentAccountId = AccountOwnership.normalizedAccountId(accountId)
        decoder.dateDecodingStrategy = .iso8601
        loadProfile()
    }

    nonisolated deinit {}

    func configureRemoteSync(
        backendMode: BackendMode,
        profileRepository: (any ProfileRepository)?,
        autoObserve: Bool = true
    ) {
        self.backendMode = backendMode
        self.profileRepository = backendMode == .firebase ? profileRepository : nil
        self.autoObserveRemote = autoObserve
        restartProfileObservationIfNeeded()
    }

    func setCurrentAccountId(_ accountId: String?) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        guard currentAccountId != normalizedAccountId else { return }
        currentAccountId = normalizedAccountId
        applyStoredProfile()
        restartProfileObservationIfNeeded()
    }

    var pendingUploadCount: Int {
        storedProfile?.syncMetadata.syncState == .pendingUpload ? 1 : 0
    }

    func pendingProfileForSync() -> UserProfile? {
        storedProfile?.syncMetadata.syncState == .pendingUpload ? storedProfile : nil
    }

    func canContinue(from step: Step) -> Bool {
        switch step {
        case .welcome:
            true
        case .identity:
            draft.genderIdentity != nil
        case .stats:
            isValidAge && isValidHeight && isValidWeight
        case .goalEquipment:
            draft.primaryGoal != nil && draft.fitnessLevel != nil && !draft.equipment.isEmpty
        case .coachTheme:
            true
        case .completion:
            canCompleteProfile
        }
    }

    var ageValidationMessage: String? {
        let value = draft.age.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard draft.ageValue != nil else { return "Age must be a whole number." }
        guard isValidAge else { return "Age must be between 13 and 100." }
        return nil
    }

    var heightValidationMessage: String? {
        let value = draft.height.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard draft.heightValue != nil else {
            return "Height must be a number in \(draft.heightUnit.heightLabel)."
        }
        guard isValidHeight else {
            switch draft.heightUnit {
            case .metric:
                return "Height must be between 120 and 230 cm."
            case .imperial:
                return "Height must be between 48 and 90 in."
            }
        }
        return nil
    }

    var weightValidationMessage: String? {
        let value = draft.weight.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard draft.weightValue != nil else {
            return "Weight must be a number in \(draft.weightUnit.weightLabel)."
        }
        guard isValidWeight else {
            switch draft.weightUnit {
            case .metric:
                return "Weight must be between 30 and 250 kg."
            case .imperial:
                return "Weight must be between 66 and 550 lb."
            }
        }
        return nil
    }

    func updateHeightUnit(_ unit: UnitPreference) {
        guard draft.heightUnit != unit else { return }

        var updatedDraft = draft
        updatedDraft.height = Self.convert(
            draft.height,
            from: draft.heightUnit,
            to: unit,
            metricToImperial: { $0 / 2.54 },
            imperialToMetric: { $0 * 2.54 }
        )
        updatedDraft.heightUnit = unit
        draft = updatedDraft
    }

    func updateWeightUnit(_ unit: UnitPreference) {
        guard draft.weightUnit != unit else { return }

        var updatedDraft = draft
        updatedDraft.weight = Self.convert(
            draft.weight,
            from: draft.weightUnit,
            to: unit,
            metricToImperial: { $0 * 2.2046226218 },
            imperialToMetric: { $0 / 2.2046226218 }
        )
        updatedDraft.weightUnit = unit
        draft = updatedDraft
    }

    func toggleEquipment(_ option: EquipmentOption) {
        if draft.equipment.contains(option) {
            draft.equipment.remove(option)
        } else {
            draft.equipment.insert(option)
        }
    }

    func toggleLimitation(_ limitation: PhysicalLimitation) {
        if draft.limitations.contains(limitation) {
            draft.limitations.remove(limitation)
        } else {
            draft.limitations.insert(limitation)
        }
    }

    @discardableResult
    func completeOnboarding(operationId: UUID? = nil) async -> Bool {
        guard canCompleteProfile,
              let genderIdentity = draft.genderIdentity,
              let age = draft.ageValue,
              let height = draft.heightValue,
              let weight = draft.weightValue,
              let primaryGoal = draft.primaryGoal,
              let fitnessLevel = draft.fitnessLevel
        else {
            persistenceError = "Finish the required onboarding fields first."
            return false
        }

        let now = Date()
        let trimmedName = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = UserProfile(
            id: UUID(),
            displayName: trimmedName.isEmpty ? nil : trimmedName,
            genderIdentity: genderIdentity,
            age: age,
            height: height,
            heightUnit: draft.heightUnit,
            weight: weight,
            weightUnit: draft.weightUnit,
            primaryGoal: primaryGoal,
            fitnessLevel: fitnessLevel,
            equipment: draft.equipment.sorted { $0.rawValue < $1.rawValue },
            preferredCoach: draft.preferredCoach,
            selectedTheme: draft.selectedTheme,
            limitations: draft.limitations,
            preferredSessionLength: draft.preferredSessionLength,
            workoutDaysPerWeek: Self.normalizedWorkoutDaysPerWeek(draft.workoutDaysPerWeek),
            reminderPreference: draft.reminderPreference,
            timezoneIdentifier: Self.normalizedTimezoneIdentifier(draft.timezoneIdentifier),
            avatarStyle: draft.avatarStyle,
            onboardingCompletedAt: now,
            createdAt: now,
            updatedAt: now
        )

        return await save(profile, operationId: operationId)
    }

    func updateTrainingPreferences(
        limitations: Set<PhysicalLimitation>,
        preferredSessionLength: PlanSessionLength,
        workoutDaysPerWeek: Int?,
        reminderPreference: ReminderPreference,
        timezoneIdentifier: String,
        avatarStyle: AvatarStyle?,
        operationId: UUID? = nil
    ) async -> Bool {
        guard var profile else {
            persistenceError = "No profile exists yet."
            return false
        }

        profile.limitations = limitations
        profile.preferredSessionLength = preferredSessionLength
        profile.workoutDaysPerWeek = Self.normalizedWorkoutDaysPerWeek(workoutDaysPerWeek)
        profile.reminderPreference = reminderPreference
        profile.timezoneIdentifier = Self.normalizedTimezoneIdentifier(timezoneIdentifier)
        profile.avatarStyle = avatarStyle
        profile.profileSchemaVersion = UserProfile.currentProfileSchemaVersion
        profile.updatedAt = Date()
        return await save(profile, operationId: operationId)
    }

    func resetOnboarding() async {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try await persistenceActor.remove(fileURL)
            }
            profile = nil
            storedProfile = nil
            persistedStoredProfile = nil
            draft = OnboardingDraft()
            persistenceError = nil
        } catch {
            persistenceError = "Could not reset onboarding: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func claimLocalDataForAccount(id accountId: String, operationId: UUID? = nil) async -> Bool {
        let writeOperationId = operationId ?? UUID()
        guard let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId) else {
            persistenceError = "Account id is required before local profile data can be claimed."
            return false
        }
        guard var storedProfile else { return true }
        guard storedProfile.accountId == nil else { return true }

        let now = Date()
        storedProfile.accountId = normalizedAccountId
        storedProfile.updatedAt = now
        storedProfile.syncMetadata.markLocalMutation(
            accountId: normalizedAccountId,
            operationId: writeOperationId,
            now: now
        )
        let previousStoredProfile = self.storedProfile
        let previousVisibleProfile = self.profile
        let generation = applyLocalMutation(storedProfile)
        if await writeJournal.contains(operationId: writeOperationId) {
            rollbackLocalMutationIfNeeded(
                generation: generation,
                storedProfile: previousStoredProfile,
                visibleProfile: previousVisibleProfile
            )
            return true
        }
        guard await persist(storedProfile, generation: generation) != nil else { return false }
        guard await saveProfileRemotelyIfNeeded(storedProfile, operationId: writeOperationId) else {
            return false
        }
        await recordWriteOperation(writeOperationId, createdAt: now)
        return true
    }

    @discardableResult
    func updatePrimaryGoal(_ goal: FitnessGoal, operationId: UUID? = nil) async -> Bool {
        guard var profile else {
            persistenceError = "No profile exists yet."
            return false
        }

        guard profile.primaryGoal != goal else { return true }

        profile.primaryGoal = goal
        profile.profileSchemaVersion = UserProfile.currentProfileSchemaVersion
        profile.updatedAt = Date()
        return await save(profile, operationId: operationId)
    }

    @discardableResult
    func updatePreferredCoach(_ coach: CoachPreference, operationId: UUID? = nil) async -> Bool {
        guard var profile else {
            persistenceError = "No profile exists yet."
            return false
        }

        guard profile.preferredCoach != coach else { return true }

        profile.preferredCoach = coach
        profile.profileSchemaVersion = UserProfile.currentProfileSchemaVersion
        profile.updatedAt = Date()
        return await save(profile, operationId: operationId)
    }

    @discardableResult
    func updateSelectedTheme(_ theme: SpotterThemeOption, operationId: UUID? = nil) async -> Bool {
        guard var profile else {
            persistenceError = "No profile exists yet."
            return false
        }

        guard profile.selectedTheme != theme else { return true }

        profile.selectedTheme = theme
        profile.profileSchemaVersion = UserProfile.currentProfileSchemaVersion
        profile.updatedAt = Date()
        return await save(profile, operationId: operationId)
    }

    @discardableResult
    func updatePreferredSessionLength(_ sessionLength: PlanSessionLength, operationId: UUID? = nil) async -> Bool {
        guard var profile else {
            persistenceError = "No profile exists yet."
            return false
        }

        guard profile.preferredSessionLength != sessionLength else { return true }

        profile.preferredSessionLength = sessionLength
        profile.profileSchemaVersion = UserProfile.currentProfileSchemaVersion
        profile.updatedAt = Date()
        return await save(profile, operationId: operationId)
    }

    @discardableResult
    func saveProfile(_ profile: UserProfile, operationId: UUID? = nil) async -> Bool {
        await save(profile, operationId: operationId)
    }

    func reload() {
        loadProfile()
    }

    private var canCompleteProfile: Bool {
        canContinue(from: .identity)
            && canContinue(from: .stats)
            && canContinue(from: .goalEquipment)
            && canContinue(from: .coachTheme)
    }

    private var isValidAge: Bool {
        guard let age = draft.ageValue else { return false }
        return (13...100).contains(age)
    }

    private var isValidHeight: Bool {
        guard let height = draft.heightValue else { return false }
        switch draft.heightUnit {
        case .metric:
            return (120...230).contains(height)
        case .imperial:
            return (48...90).contains(height)
        }
    }

    private var isValidWeight: Bool {
        guard let weight = draft.weightValue else { return false }
        switch draft.weightUnit {
        case .metric:
            return (30...250).contains(weight)
        case .imperial:
            return (66...550).contains(weight)
        }
    }

    private func loadProfile() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            storedProfile = nil
            persistedStoredProfile = nil
            profile = nil
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            storedProfile = try decoder.decode(UserProfile.self, from: data)
            persistedStoredProfile = storedProfile
            applyStoredProfile()
        } catch {
            persistenceError = "Could not load profile: \(error.localizedDescription)"
            storedProfile = nil
            persistedStoredProfile = nil
            profile = nil
        }
    }

    @discardableResult
    private func save(
        _ profile: UserProfile,
        operationId: UUID? = nil,
        markLocalMutation: Bool = true,
        saveRemote: Bool = true,
        recordJournal: Bool = true
    ) async -> Bool {
        let writeOperationId = operationId ?? UUID()

        var accountStampedProfile = profile
        if let currentAccountId {
            accountStampedProfile.accountId = currentAccountId
        }
        if markLocalMutation {
            accountStampedProfile.syncMetadata.markLocalMutation(
                accountId: accountStampedProfile.accountId,
                operationId: writeOperationId,
                now: accountStampedProfile.updatedAt
            )
        }
        let previousStoredProfile = storedProfile
        let previousVisibleProfile = self.profile
        let generation = applyLocalMutation(accountStampedProfile)
        if recordJournal, await writeJournal.contains(operationId: writeOperationId) {
            rollbackLocalMutationIfNeeded(
                generation: generation,
                storedProfile: previousStoredProfile,
                visibleProfile: previousVisibleProfile
            )
            return true
        }
        guard await persist(accountStampedProfile, generation: generation) != nil else { return false }
        if saveRemote {
            guard await saveProfileRemotelyIfNeeded(
                accountStampedProfile,
                operationId: writeOperationId
            ) else {
                return false
            }
        }
        if recordJournal {
            await recordWriteOperation(writeOperationId, createdAt: accountStampedProfile.updatedAt)
        }
        return true
    }

    private func restartProfileObservationIfNeeded() {
        profileObservationTask?.cancel()
        profileObservationTask = nil

        guard backendMode == .firebase,
              autoObserveRemote,
              let profileRepository,
              let currentAccountId else {
            return
        }

        profileObservationTask = Task { [weak self, profileRepository, currentAccountId] in
            do {
                if let loadedProfile = try await profileRepository.loadProfile(accountId: currentAccountId) {
                    _ = await self?.applyRemoteProfileCache(loadedProfile)
                }

                let stream = try await profileRepository.observeProfile(accountId: currentAccountId)
                for await remoteProfile in stream {
                    guard let remoteProfile else { continue }
                    _ = await self?.applyRemoteProfileCache(remoteProfile)
                }
            } catch {
                await self?.setRemoteProfileError(error)
            }
        }
    }

    @discardableResult
    private func saveProfileRemotelyIfNeeded(
        _ profile: UserProfile,
        operationId: UUID
    ) async -> Bool {
        guard backendMode == .firebase,
              let profileRepository,
              AccountOwnership.normalizedAccountId(profile.accountId) != nil else {
            return true
        }

        do {
            let savedProfile = try await profileRepository.saveProfile(
                profile,
                operationId: operationId
            )
            return await applyRemoteProfileCache(savedProfile, allowReplacingPending: true)
        } catch {
            persistenceError = "Could not sync profile: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func applyRemoteProfile(
        _ remoteProfile: UserProfile,
        allowReplacingPending: Bool = false
    ) async -> Bool {
        var syncedProfile = remoteProfile
        syncedProfile.syncMetadata = remoteProfile.syncMetadata.markedSynced(
            serverVersion: remoteProfile.syncMetadata.serverVersion
        )
        if let storedProfile {
            if storedProfile.syncMetadata == syncedProfile.syncMetadata {
                return true
            }
            if !allowReplacingPending,
               storedProfile.syncMetadata.syncState == .pendingUpload ||
                storedProfile.syncMetadata.syncState == .conflict {
                return true
            }
        }
        return await save(
            syncedProfile,
            operationId: UUID(),
            markLocalMutation: false,
            saveRemote: false,
            recordJournal: false
        )
    }

    @discardableResult
    private func applyRemoteProfileCache(
        _ remoteProfile: UserProfile,
        allowReplacingPending: Bool = false
    ) async -> Bool {
        await applyRemoteProfile(remoteProfile, allowReplacingPending: allowReplacingPending)
    }

    @discardableResult
    func markProfileConflict(serverVersion: String?, localVersion: String?) async -> Bool {
        guard var storedProfile else { return false }
        storedProfile.syncMetadata = storedProfile.syncMetadata.markedConflict(
            serverVersion: serverVersion,
            localVersion: localVersion
        )
        let generation = applyLocalMutation(storedProfile)
        return await persist(storedProfile, generation: generation) != nil
    }

    private func setRemoteProfileError(_ error: Error) {
        persistenceError = "Could not observe profile sync: \(error.localizedDescription)"
    }

    private func recordWriteOperation(_ operationId: UUID, createdAt: Date) async {
        _ = await writeJournal.record(
            operationId: operationId,
            entityKind: .profile,
            createdAt: createdAt
        )
    }

    @discardableResult
    private func persist(_ profile: UserProfile, generation: Int) async -> PersistenceWriteOutcome? {
        do {
            let data = try await persistenceActor.encode(
                profile,
                outputFormatting: [.prettyPrinted, .sortedKeys]
            )
            let outcome = try await persistenceActor.writeLatest(data, to: fileURL, options: [.atomic])
            if outcome == .written {
                persistedStoredProfile = profile
            }
            persistenceError = nil
            return outcome
        } catch {
            rollbackLatestMutationIfNeeded(generation: generation)
            persistenceError = "Could not save profile: \(error.localizedDescription)"
            return nil
        }
    }

    private func applyLocalMutation(_ profile: UserProfile) -> Int {
        persistenceGeneration += 1
        storedProfile = profile
        applyStoredProfile()
        return persistenceGeneration
    }

    private func rollbackLatestMutationIfNeeded(generation: Int) {
        guard generation == persistenceGeneration else { return }
        storedProfile = persistedStoredProfile
        applyStoredProfile()
    }

    private func rollbackLocalMutationIfNeeded(
        generation: Int,
        storedProfile previousStoredProfile: UserProfile?,
        visibleProfile previousVisibleProfile: UserProfile?
    ) {
        guard generation == persistenceGeneration else { return }
        storedProfile = previousStoredProfile
        profile = previousVisibleProfile
    }

    private func applyStoredProfile() {
        guard let storedProfile,
              AccountOwnership.isVisible(
                recordAccountId: storedProfile.accountId,
                currentAccountId: currentAccountId
              )
        else {
            profile = nil
            return
        }

        profile = storedProfile
    }

    private static func defaultProfileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Spotter", isDirectory: true)
            .appendingPathComponent("UserProfile.json")
    }

    private static func normalizedWorkoutDaysPerWeek(_ value: Int?) -> Int? {
        guard let value else { return UserProfile.defaultWorkoutDaysPerWeek }
        return min(max(value, 1), 7)
    }

    private static func normalizedTimezoneIdentifier(_ identifier: String) -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let timezone = TimeZone(identifier: trimmed)
        else {
            return TimeZone.current.identifier
        }
        return timezone.identifier
    }

    private static func convert(
        _ value: String,
        from oldUnit: UnitPreference,
        to newUnit: UnitPreference,
        metricToImperial: (Double) -> Double,
        imperialToMetric: (Double) -> Double
    ) -> String {
        guard oldUnit != newUnit else { return value }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedValue = Double(trimmed) else { return value }

        let convertedValue: Double
        switch (oldUnit, newUnit) {
        case (.metric, .imperial):
            convertedValue = metricToImperial(parsedValue)
        case (.imperial, .metric):
            convertedValue = imperialToMetric(parsedValue)
        default:
            convertedValue = parsedValue
        }

        return formatMeasurement(convertedValue)
    }

    private static func formatMeasurement(_ value: Double) -> String {
        let roundedValue = (value * 10).rounded() / 10
        if roundedValue.rounded() == roundedValue {
            return String(Int(roundedValue))
        }
        return String(format: "%.1f", roundedValue)
    }
}
