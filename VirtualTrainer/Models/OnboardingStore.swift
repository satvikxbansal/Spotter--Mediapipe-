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
}
