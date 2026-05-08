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

    init(coachPersonality: CoachPersonality) {
        switch coachPersonality {
        case .good:
            self = .bennett
        case .drill:
            self = .fletcher
        }
    }

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

nonisolated enum PhysicalLimitation: String, Codable, CaseIterable, Identifiable, Hashable {
    case kneeSensitive
    case shoulderSensitive
    case wristSensitive
    case lowerBackSensitive
    case balanceSensitive
    case highImpactSensitive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kneeSensitive: "Knee sensitive"
        case .shoulderSensitive: "Shoulder sensitive"
        case .wristSensitive: "Wrist sensitive"
        case .lowerBackSensitive: "Lower back sensitive"
        case .balanceSensitive: "Balance sensitive"
        case .highImpactSensitive: "Avoid high impact"
        }
    }
}

nonisolated enum ReminderPreference: String, Codable, CaseIterable, Identifiable {
    case none
    case morning
    case evening
    case customLater

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "None"
        case .morning: "Morning"
        case .evening: "Evening"
        case .customLater: "Custom later"
        }
    }
}

nonisolated enum AvatarStyle: String, Codable, CaseIterable, Identifiable {
    case `default` = "default"
    case strength
    case performance
    case longevity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: "Default"
        case .strength: "Strength"
        case .performance: "Performance"
        case .longevity: "Longevity"
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
    static let currentOnboardingSchemaVersion = 2
    static let currentProfileSchemaVersion = 2
    static let defaultWorkoutDaysPerWeek = 3

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
    var limitations: Set<PhysicalLimitation>
    var preferredSessionLength: PlanSessionLength
    var workoutDaysPerWeek: Int?
    var reminderPreference: ReminderPreference
    var timezoneIdentifier: String
    var avatarStyle: AvatarStyle?
    var onboardingSchemaVersion: Int
    var profileSchemaVersion: Int
    var onboardingCompletedAt: Date
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

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

    init(
        id: UUID,
        displayName: String?,
        genderIdentity: GenderIdentity,
        age: Int,
        height: Double,
        heightUnit: UnitPreference,
        weight: Double,
        weightUnit: UnitPreference,
        primaryGoal: FitnessGoal,
        fitnessLevel: FitnessLevel,
        equipment: [EquipmentOption],
        preferredCoach: CoachPreference,
        selectedTheme: SpotterThemeOption,
        limitations: Set<PhysicalLimitation> = [],
        preferredSessionLength: PlanSessionLength = .twentyFive,
        workoutDaysPerWeek: Int? = UserProfile.defaultWorkoutDaysPerWeek,
        reminderPreference: ReminderPreference = .none,
        timezoneIdentifier: String = TimeZone.current.identifier,
        avatarStyle: AvatarStyle? = .default,
        onboardingSchemaVersion: Int = UserProfile.currentOnboardingSchemaVersion,
        profileSchemaVersion: Int = UserProfile.currentProfileSchemaVersion,
        onboardingCompletedAt: Date,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.genderIdentity = genderIdentity
        self.age = age
        self.height = height
        self.heightUnit = heightUnit
        self.weight = weight
        self.weightUnit = weightUnit
        self.primaryGoal = primaryGoal
        self.fitnessLevel = fitnessLevel
        self.equipment = equipment
        self.preferredCoach = preferredCoach
        self.selectedTheme = selectedTheme
        self.limitations = limitations
        self.preferredSessionLength = preferredSessionLength
        self.workoutDaysPerWeek = workoutDaysPerWeek
        self.reminderPreference = reminderPreference
        self.timezoneIdentifier = timezoneIdentifier
        self.avatarStyle = avatarStyle
        self.onboardingSchemaVersion = onboardingSchemaVersion
        self.profileSchemaVersion = profileSchemaVersion
        self.onboardingCompletedAt = onboardingCompletedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    func markedDeleted(at date: Date) -> UserProfile {
        var copy = self
        copy.deletedAt = date
        copy.updatedAt = date
        return copy
    }

    func restored() -> UserProfile {
        var copy = self
        copy.deletedAt = nil
        return copy
    }
}

nonisolated extension UserProfile {
    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case genderIdentity
        case age
        case height
        case heightUnit
        case weight
        case weightUnit
        case primaryGoal
        case fitnessLevel
        case equipment
        case preferredCoach
        case selectedTheme
        case limitations
        case preferredSessionLength
        case workoutDaysPerWeek
        case reminderPreference
        case timezoneIdentifier
        case avatarStyle
        case onboardingSchemaVersion
        case profileSchemaVersion
        case onboardingCompletedAt
        case createdAt
        case updatedAt
        case deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            displayName: try container.decodeIfPresent(String.self, forKey: .displayName),
            genderIdentity: try container.decode(GenderIdentity.self, forKey: .genderIdentity),
            age: try container.decode(Int.self, forKey: .age),
            height: try container.decode(Double.self, forKey: .height),
            heightUnit: try container.decode(UnitPreference.self, forKey: .heightUnit),
            weight: try container.decode(Double.self, forKey: .weight),
            weightUnit: try container.decode(UnitPreference.self, forKey: .weightUnit),
            primaryGoal: try container.decode(FitnessGoal.self, forKey: .primaryGoal),
            fitnessLevel: try container.decode(FitnessLevel.self, forKey: .fitnessLevel),
            equipment: try container.decode([EquipmentOption].self, forKey: .equipment),
            preferredCoach: try container.decode(CoachPreference.self, forKey: .preferredCoach),
            selectedTheme: try container.decode(SpotterThemeOption.self, forKey: .selectedTheme),
            limitations: try container.decodeIfPresent(Set<PhysicalLimitation>.self, forKey: .limitations) ?? [],
            preferredSessionLength: try container.decodeIfPresent(PlanSessionLength.self, forKey: .preferredSessionLength) ?? .twentyFive,
            workoutDaysPerWeek: try container.decodeIfPresent(Int.self, forKey: .workoutDaysPerWeek) ?? Self.defaultWorkoutDaysPerWeek,
            reminderPreference: try container.decodeIfPresent(ReminderPreference.self, forKey: .reminderPreference) ?? .none,
            timezoneIdentifier: try container.decodeIfPresent(String.self, forKey: .timezoneIdentifier) ?? TimeZone.current.identifier,
            avatarStyle: try container.decodeIfPresent(AvatarStyle.self, forKey: .avatarStyle) ?? .default,
            onboardingSchemaVersion: try container.decodeIfPresent(Int.self, forKey: .onboardingSchemaVersion) ?? Self.currentOnboardingSchemaVersion,
            profileSchemaVersion: try container.decodeIfPresent(Int.self, forKey: .profileSchemaVersion) ?? Self.currentProfileSchemaVersion,
            onboardingCompletedAt: try container.decode(Date.self, forKey: .onboardingCompletedAt),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encode(genderIdentity, forKey: .genderIdentity)
        try container.encode(age, forKey: .age)
        try container.encode(height, forKey: .height)
        try container.encode(heightUnit, forKey: .heightUnit)
        try container.encode(weight, forKey: .weight)
        try container.encode(weightUnit, forKey: .weightUnit)
        try container.encode(primaryGoal, forKey: .primaryGoal)
        try container.encode(fitnessLevel, forKey: .fitnessLevel)
        try container.encode(equipment, forKey: .equipment)
        try container.encode(preferredCoach, forKey: .preferredCoach)
        try container.encode(selectedTheme, forKey: .selectedTheme)
        try container.encode(limitations.sorted { $0.rawValue < $1.rawValue }, forKey: .limitations)
        try container.encode(preferredSessionLength, forKey: .preferredSessionLength)
        try container.encodeIfPresent(workoutDaysPerWeek, forKey: .workoutDaysPerWeek)
        try container.encode(reminderPreference, forKey: .reminderPreference)
        try container.encode(timezoneIdentifier, forKey: .timezoneIdentifier)
        try container.encodeIfPresent(avatarStyle, forKey: .avatarStyle)
        try container.encode(onboardingSchemaVersion, forKey: .onboardingSchemaVersion)
        try container.encode(profileSchemaVersion, forKey: .profileSchemaVersion)
        try container.encode(onboardingCompletedAt, forKey: .onboardingCompletedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
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
    var limitations: Set<PhysicalLimitation> = []
    var preferredSessionLength: PlanSessionLength = .twentyFive
    var workoutDaysPerWeek: Int? = UserProfile.defaultWorkoutDaysPerWeek
    var reminderPreference: ReminderPreference = .none
    var timezoneIdentifier: String = TimeZone.current.identifier
    var avatarStyle: AvatarStyle? = .default

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
