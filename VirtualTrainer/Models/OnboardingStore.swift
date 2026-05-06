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
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var hasCompletedOnboarding: Bool {
        profile != nil
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultProfileURL()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        loadProfile()
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

    func completeOnboarding() {
        guard canCompleteProfile,
              let genderIdentity = draft.genderIdentity,
              let age = draft.ageValue,
              let height = draft.heightValue,
              let weight = draft.weightValue,
              let primaryGoal = draft.primaryGoal,
              let fitnessLevel = draft.fitnessLevel
        else {
            persistenceError = "Finish the required onboarding fields first."
            return
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

        save(profile)
    }

    func updateTrainingPreferences(
        limitations: Set<PhysicalLimitation>,
        preferredSessionLength: PlanSessionLength,
        workoutDaysPerWeek: Int?,
        reminderPreference: ReminderPreference,
        timezoneIdentifier: String,
        avatarStyle: AvatarStyle?
    ) {
        guard var profile else {
            persistenceError = "No profile exists yet."
            return
        }

        profile.limitations = limitations
        profile.preferredSessionLength = preferredSessionLength
        profile.workoutDaysPerWeek = Self.normalizedWorkoutDaysPerWeek(workoutDaysPerWeek)
        profile.reminderPreference = reminderPreference
        profile.timezoneIdentifier = Self.normalizedTimezoneIdentifier(timezoneIdentifier)
        profile.avatarStyle = avatarStyle
        profile.profileSchemaVersion = UserProfile.currentProfileSchemaVersion
        profile.updatedAt = Date()
        save(profile)
    }

    func resetOnboarding() {
        profile = nil
        draft = OnboardingDraft()
        persistenceError = nil
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            persistenceError = "Could not reset onboarding: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func updatePrimaryGoal(_ goal: FitnessGoal) -> Bool {
        guard var profile else {
            persistenceError = "No profile exists yet."
            return false
        }

        guard profile.primaryGoal != goal else { return true }

        profile.primaryGoal = goal
        profile.profileSchemaVersion = UserProfile.currentProfileSchemaVersion
        profile.updatedAt = Date()
        return save(profile)
    }

    @discardableResult
    func updatePreferredCoach(_ coach: CoachPreference) -> Bool {
        guard var profile else {
            persistenceError = "No profile exists yet."
            return false
        }

        guard profile.preferredCoach != coach else { return true }

        profile.preferredCoach = coach
        profile.profileSchemaVersion = UserProfile.currentProfileSchemaVersion
        profile.updatedAt = Date()
        return save(profile)
    }

    @discardableResult
    func updateSelectedTheme(_ theme: SpotterThemeOption) -> Bool {
        guard var profile else {
            persistenceError = "No profile exists yet."
            return false
        }

        guard profile.selectedTheme != theme else { return true }

        profile.selectedTheme = theme
        profile.profileSchemaVersion = UserProfile.currentProfileSchemaVersion
        profile.updatedAt = Date()
        return save(profile)
    }

    @discardableResult
    func updatePreferredSessionLength(_ sessionLength: PlanSessionLength) -> Bool {
        guard var profile else {
            persistenceError = "No profile exists yet."
            return false
        }

        guard profile.preferredSessionLength != sessionLength else { return true }

        profile.preferredSessionLength = sessionLength
        profile.profileSchemaVersion = UserProfile.currentProfileSchemaVersion
        profile.updatedAt = Date()
        return save(profile)
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
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            profile = try decoder.decode(UserProfile.self, from: data)
        } catch {
            persistenceError = "Could not load profile: \(error.localizedDescription)"
            profile = nil
        }
    }

    @discardableResult
    private func save(_ profile: UserProfile) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(profile)
            try data.write(to: fileURL, options: [.atomic])
            self.profile = profile
            persistenceError = nil
            return true
        } catch {
            persistenceError = "Could not save profile: \(error.localizedDescription)"
            return false
        }
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
