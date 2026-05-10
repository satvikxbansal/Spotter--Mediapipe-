import Foundation

nonisolated enum PIIFieldCategory: String, Codable, CaseIterable {
    case directIdentifier
    case profileAttribute
    case healthAdjacent
    case trainingPreference
    case appPreference
    case accountMetadata
    case derivedTrainingSummary
    case systemMetadata
}

nonisolated struct PIIFieldDescriptor: Codable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let category: PIIFieldCategory
    let description: String
    let storedIn: String
    let relatedCodableKeys: [String]

    init(
        id: String,
        displayName: String,
        category: PIIFieldCategory,
        description: String,
        storedIn: String,
        relatedCodableKeys: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.description = description
        self.storedIn = storedIn
        self.relatedCodableKeys = relatedCodableKeys.isEmpty ? [id] : relatedCodableKeys
    }
}

nonisolated enum PIIRegistry {
    static let schemaVersion = 1

    static let currentProfileFieldIDs: [String] = [
        "id",
        "accountId",
        "displayName",
        "genderIdentity",
        "age",
        "height",
        "heightUnit",
        "weight",
        "weightUnit",
        "primaryGoal",
        "fitnessLevel",
        "equipment",
        "preferredCoach",
        "selectedTheme",
        "limitations",
        "preferredSessionLength",
        "workoutDaysPerWeek",
        "reminderPreference",
        "timezoneIdentifier",
        "avatarStyle",
        "onboardingSchemaVersion",
        "profileSchemaVersion",
        "onboardingCompletedAt",
        "createdAt",
        "updatedAt",
        "deletedAt",
        "syncMetadata"
    ]

    static let entries: [PIIFieldDescriptor] = [
        PIIFieldDescriptor(
            id: "id",
            displayName: "Local profile ID",
            category: .accountMetadata,
            description: "A random local identifier for the profile record.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "accountId",
            displayName: "Account ID",
            category: .directIdentifier,
            description: "The future signed-in account identifier used to connect local records to an account.",
            storedIn: "profile.json and sync-ready local records"
        ),
        PIIFieldDescriptor(
            id: "displayName",
            displayName: "Display name",
            category: .directIdentifier,
            description: "The name the user chose for greetings, profile display, and share cards.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "genderIdentity",
            displayName: "Gender identity",
            category: .profileAttribute,
            description: "The gender identity option selected during onboarding.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "age",
            displayName: "Age",
            category: .healthAdjacent,
            description: "The user's age, used for safer local workout planning and age-bracket logic.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "height",
            displayName: "Height",
            category: .healthAdjacent,
            description: "The user's height measurement from onboarding.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "heightUnit",
            displayName: "Height unit",
            category: .healthAdjacent,
            description: "Whether the height value is stored in metric or imperial units.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "weight",
            displayName: "Weight",
            category: .healthAdjacent,
            description: "The user's weight measurement from onboarding.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "weightUnit",
            displayName: "Weight unit",
            category: .healthAdjacent,
            description: "Whether the weight value is stored in metric or imperial units.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "primaryGoal",
            displayName: "Primary goal",
            category: .trainingPreference,
            description: "The user's training goal, such as strength, performance, or longevity.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "fitnessLevel",
            displayName: "Fitness level",
            category: .healthAdjacent,
            description: "The user's self-selected fitness level for local plan generation.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "equipment",
            displayName: "Available equipment",
            category: .trainingPreference,
            description: "The equipment options the user said they can train with.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "preferredCoach",
            displayName: "Preferred coach",
            category: .appPreference,
            description: "The coach personality the user prefers for guidance and local voice lines.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "selectedTheme",
            displayName: "Selected theme",
            category: .appPreference,
            description: "The visual theme the user selected for the app.",
            storedIn: "profile.json and theme.json"
        ),
        PIIFieldDescriptor(
            id: "limitations",
            displayName: "Physical limitations",
            category: .healthAdjacent,
            description: "Health-adjacent sensitivity choices such as knee, shoulder, wrist, lower-back, balance, or high-impact limitations.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "preferredSessionLength",
            displayName: "Preferred session length",
            category: .trainingPreference,
            description: "The user's preferred Daily Plan duration.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "workoutDaysPerWeek",
            displayName: "Workout days per week",
            category: .trainingPreference,
            description: "The user's target number of training days per week.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "reminderPreference",
            displayName: "Reminder preference",
            category: .appPreference,
            description: "The user's preferred reminder timing, including no reminder.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "timezoneIdentifier",
            displayName: "Timezone",
            category: .profileAttribute,
            description: "The user's timezone identifier used for local streaks, weekly recaps, and time-of-day logic.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "avatarStyle",
            displayName: "Avatar style",
            category: .appPreference,
            description: "The user's selected avatar style preference.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "onboardingSchemaVersion",
            displayName: "Onboarding schema version",
            category: .systemMetadata,
            description: "The local schema version used to read older onboarding JSON safely.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "profileSchemaVersion",
            displayName: "Profile schema version",
            category: .systemMetadata,
            description: "The local schema version used to read older profile JSON safely.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "onboardingCompletedAt",
            displayName: "Onboarding completion date",
            category: .accountMetadata,
            description: "The date and time when local onboarding was completed.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "createdAt",
            displayName: "Profile creation date",
            category: .accountMetadata,
            description: "The date and time when the local profile was created.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "updatedAt",
            displayName: "Profile update date",
            category: .accountMetadata,
            description: "The date and time when the local profile was last updated.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "deletedAt",
            displayName: "Profile deletion marker",
            category: .accountMetadata,
            description: "A future-sync deletion timestamp when a profile is tombstoned instead of immediately removed.",
            storedIn: "profile.json"
        ),
        PIIFieldDescriptor(
            id: "syncMetadata",
            displayName: "Sync metadata",
            category: .systemMetadata,
            description: "Local-only or future-sync status, timestamps, conflict markers, and operation IDs for the record.",
            storedIn: "profile.json and sync-ready local records"
        ),
        PIIFieldDescriptor(
            id: "derivedEffortSummaries",
            displayName: "Derived effort summaries",
            category: .derivedTrainingSummary,
            description: "Workout effort text and structured effort values derived from saved session evidence, not raw face images or raw biometric streams.",
            storedIn: "workouts.json",
            relatedCodableKeys: ["effortSummary", "structuredEffortSummary", "peakEffort"]
        )
    ]

    static var allFieldIDs: Set<String> {
        Set(entries.map(\.id))
    }

    static func entry(for fieldID: String) -> PIIFieldDescriptor? {
        entries.first { $0.id == fieldID || $0.relatedCodableKeys.contains(fieldID) }
    }
}
