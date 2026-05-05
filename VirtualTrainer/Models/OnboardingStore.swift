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
            onboardingCompletedAt: now,
            createdAt: now,
            updatedAt: now
        )

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

    private func save(_ profile: UserProfile) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(profile)
            try data.write(to: fileURL, options: [.atomic])
            self.profile = profile
            persistenceError = nil
        } catch {
            persistenceError = "Could not save profile: \(error.localizedDescription)"
        }
    }

    private static func defaultProfileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Spotter", isDirectory: true)
            .appendingPathComponent("UserProfile.json")
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
