import Foundation

// ────────────────────────────────────────────────────────────────────
// MARK: - Onboarding Domain
// ────────────────────────────────────────────────────────────────────

nonisolated enum GenderIdentity: String, Codable, CaseIterable, Identifiable {
    case male
    case female
    case other
    case preferNotToSay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        case .other: "Other"
        case .preferNotToSay: "Prefer not to say"
        }
    }
}

nonisolated enum FitnessGoal: String, Codable, CaseIterable, Identifiable {
    case strength
    case performance
    case longevity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strength: "Strength"
        case .performance: "Performance"
        case .longevity: "Longevity"
        }
    }

    var subtitle: String {
        switch self {
        case .strength: "Build muscle and power"
        case .performance: "Stamina and athleticism"
        case .longevity: "Mobility and long-term health"
        }
    }
}

nonisolated enum FitnessLevel: String, Codable, CaseIterable, Identifiable {
    case beginner
    case intermediate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beginner: "Beginner"
        case .intermediate: "Intermediate"
        }
    }
}

nonisolated enum EquipmentOption: String, Codable, CaseIterable, Identifiable, Hashable {
    case bodyweight
    case dumbbells
    case kettlebell
    case bands
    case mat
    case chair
    case wall
    case bench
    case step

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bodyweight: "Bodyweight"
        case .dumbbells: "Dumbbells"
        case .kettlebell: "Kettlebell"
        case .bands: "Bands"
        case .mat: "Mat"
        case .chair: "Chair"
        case .wall: "Wall"
        case .bench: "Bench"
        case .step: "Step"
        }
    }
}

nonisolated enum CoachPreference: String, Codable, CaseIterable, Identifiable {
    case bennett
    case fletcher

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bennett: "Bennett"
        case .fletcher: "Fletcher"
        }
    }

    var subtitle: String {
        switch self {
        case .bennett: "Supportive and steady"
        case .fletcher: "Direct and intense"
        }
    }

    var coachPersonality: CoachPersonality {
        switch self {
        case .bennett: .good
        case .fletcher: .drill
        }
    }
}

nonisolated enum SpotterThemeOption: String, Codable, CaseIterable, Identifiable {
    case hyper
    case hotGirl
    case warm
    case spicy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hyper: "Hyper"
        case .hotGirl: "Hot Girl"
        case .warm: "Warm"
        case .spicy: "Spicy"
        }
    }
}

nonisolated enum UnitPreference: String, Codable, CaseIterable, Identifiable {
    case metric
    case imperial

    var id: String { rawValue }

    var heightLabel: String {
        switch self {
        case .metric: "cm"
        case .imperial: "in"
        }
    }

    var weightLabel: String {
        switch self {
        case .metric: "kg"
        case .imperial: "lb"
        }
    }
}

nonisolated enum AgeBracket: String, Codable, CaseIterable, Identifiable {
    case teen
    case youngAdult
    case adult
    case midlife
    case senior

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .teen: "Teen"
        case .youngAdult: "Young Adult"
        case .adult: "Adult"
        case .midlife: "Midlife"
        case .senior: "Senior"
        }
    }
}

nonisolated struct UserProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var displayName: String?
    var genderIdentity: GenderIdentity
    var age: Int
    var height: Double
    var heightUnit: UnitPreference
    var weight: Double
    var weightUnit: UnitPreference
    var primaryGoal: FitnessGoal
    var fitnessLevel: FitnessLevel
    var equipment: [EquipmentOption]
    var preferredCoach: CoachPreference
    var selectedTheme: SpotterThemeOption
    var onboardingCompletedAt: Date
    var createdAt: Date
    var updatedAt: Date

    var ageBracket: AgeBracket {
        Self.ageBracket(for: age)
    }

    var firstName: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return "Athlete" }
        return trimmed.components(separatedBy: .whitespacesAndNewlines).first ?? "Athlete"
    }

    static func ageBracket(for age: Int) -> AgeBracket {
        switch age {
        case ..<20:
            .teen
        case 20...34:
            .youngAdult
        case 35...49:
            .adult
        case 50...64:
            .midlife
        default:
            .senior
        }
    }
}

nonisolated struct OnboardingDraft: Equatable {
    var displayName: String = ""
    var genderIdentity: GenderIdentity?
    var age: String = ""
    var height: String = ""
    var heightUnit: UnitPreference = .metric
    var weight: String = ""
    var weightUnit: UnitPreference = .metric
    var primaryGoal: FitnessGoal?
    var fitnessLevel: FitnessLevel?
    var equipment: Set<EquipmentOption> = [.bodyweight]
    var preferredCoach: CoachPreference = .bennett
    var selectedTheme: SpotterThemeOption = .hyper

    var ageValue: Int? {
        Int(age.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var heightValue: Double? {
        Double(height.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var weightValue: Double? {
        Double(weight.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
