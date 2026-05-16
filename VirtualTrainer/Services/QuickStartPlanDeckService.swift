import Foundation

nonisolated enum DeterministicHash {
    static func hash64(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }

    static func uuid(from value: String) -> UUID {
        var bytes: [UInt8] = []
        for salt in 0..<2 {
            var hash = hash64("\(value)|\(salt)")
            for _ in 0..<8 {
                bytes.append(UInt8(truncatingIfNeeded: hash))
                hash >>= 8
            }
        }

        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            )
        )
    }
}

nonisolated enum QuickStartPlanIntensity: String, Codable, CaseIterable, Hashable {
    case beginner
    case intermediate

    var displayName: String {
        switch self {
        case .beginner:
            return "Beginner"
        case .intermediate:
            return "Intermediate"
        }
    }
}

nonisolated struct QuickStartPlanVariant: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let intensityLabel: QuickStartPlanIntensity
    let plan: WorkoutPlanV2
    let reason: String
    let deckIndex: Int

    func reindexed(_ index: Int) -> QuickStartPlanVariant {
        QuickStartPlanVariant(
            id: id,
            title: title,
            subtitle: subtitle,
            intensityLabel: intensityLabel,
            plan: plan,
            reason: reason,
            deckIndex: index
        )
    }
}

nonisolated struct QuickStartDeck: Identifiable, Codable, Equatable {
    let id: String
    let generatedForDay: Date
    let generationVersion: String
    let variants: [QuickStartPlanVariant]

    var isEmpty: Bool {
        variants.isEmpty
    }

    func variant(at index: Int) -> QuickStartPlanVariant? {
        guard !variants.isEmpty else { return nil }
        return variants[normalizedIndex(index)]
    }

    func normalizedIndex(_ index: Int) -> Int {
        guard !variants.isEmpty else { return 0 }
        let remainder = index % variants.count
        return remainder >= 0 ? remainder : remainder + variants.count
    }

    func index(after index: Int) -> Int {
        guard !variants.isEmpty else { return 0 }
        return (normalizedIndex(index) + 1) % variants.count
    }

    static func single(
        plan: WorkoutPlanV2,
        generatedForDay: Date,
        generationVersion: String
    ) -> QuickStartDeck {
        let variant = QuickStartPlanVariant(
            id: plan.id.uuidString,
            title: plan.title,
            subtitle: plan.subtitle,
            intensityLabel: plan.difficulty == .beginner ? .beginner : .intermediate,
            plan: plan,
            reason: plan.planReason,
            deckIndex: 0
        )

        return QuickStartDeck(
            id: "single-\(plan.id.uuidString)",
            generatedForDay: generatedForDay,
            generationVersion: generationVersion,
            variants: [variant]
        )
    }
}

nonisolated final class QuickStartPlanDeckService {
    static let generationVersion = "quick-start-deck-v1"

    private let generator: PlanGenerator
    private let calendar: Calendar

    init(
        generator: PlanGenerator = PlanGenerator(),
        calendar: Calendar = .current
    ) {
        self.generator = generator
        self.calendar = calendar
    }

    func generateDeck(
        profile: UserProfile,
        recentWorkoutHistory: [RecentWorkoutHistoryItem] = [],
        now: Date = Date(),
        generationVersion: String = QuickStartPlanDeckService.generationVersion
    ) -> QuickStartDeck {
        let dayStart = calendar.startOfDay(for: now)
        let dayKey = dayKey(for: dayStart)
        let versionedDayKey = generationVersion == Self.generationVersion
            ? dayKey
            : "\(generationVersion)|\(dayKey)"
        let dailySeed = seed(profile: profile, dayKey: versionedDayKey)
        let orderedSpecs = dailyOrderedSpecs(
            profile: profile,
            dayStart: dayStart
        )
        let draftVariants = orderedSpecs.compactMap { spec in
            makeVariant(
                spec: spec,
                deckIndex: 0,
                profile: profile,
                recentWorkoutHistory: recentWorkoutHistory,
                generatedAt: dayStart,
                dailySeed: dailySeed
            )
        }
        let variants = draftVariants.prefix(5).enumerated().map { index, variant in
            variant.reindexed(index)
        }

        if variants.isEmpty {
            let fallback = generator.generate(
                input: PlanGenerationInput(
                    profile: profile,
                    sessionLength: .seven,
                    recentWorkoutHistory: recentWorkoutHistory,
                    variantSeed: dailySeed
                ),
                planId: DeterministicHash.uuid(from: "\(dailySeed)|fallback"),
                generatedAt: dayStart
            )
            return QuickStartDeck.single(
                plan: fallback,
                generatedForDay: dayStart,
                generationVersion: generationVersion
            )
        }

        return QuickStartDeck(
            id: DeterministicHash.uuid(from: "\(dailySeed)|deck").uuidString,
            generatedForDay: dayStart,
            generationVersion: generationVersion,
            variants: variants
        )
    }

    func generateSmartStart(
        profile: UserProfile,
        variantSeed: String,
        recentWorkoutHistory: [RecentWorkoutHistoryItem] = [],
        now: Date = Date()
    ) -> WorkoutPlanV2 {
        let dayStart = calendar.startOfDay(for: now)
        let dayKey = dayKey(for: dayStart)
        let dailySeed = "\(seed(profile: profile, dayKey: dayKey))|\(variantSeed)"
        let specIndex = Int(DeterministicHash.hash64(variantSeed) % UInt64(Self.defaultSpecs.count))
        let spec = Self.defaultSpecs[specIndex]

        return makeVariant(
            spec: spec,
            deckIndex: 0,
            profile: profile,
            recentWorkoutHistory: recentWorkoutHistory,
            generatedAt: dayStart,
            dailySeed: dailySeed
        )?.plan ?? generator.generate(
            input: PlanGenerationInput(
                profile: profile,
                sessionLength: .seven,
                recentWorkoutHistory: recentWorkoutHistory,
                variantSeed: dailySeed
            ),
            planId: DeterministicHash.uuid(from: "\(dailySeed)|fallback"),
            generatedAt: dayStart
        )
    }
}

nonisolated private extension QuickStartPlanDeckService {
    struct VariantSpec {
        let focus: QuickStartFocus
        let intensity: QuickStartPlanIntensity
    }

    enum QuickStartFocus: String, CaseIterable {
        case core
        case lowerBody
        case upperBody
        case mobilityReset
        case athleticCircuit

        var displayName: String {
            switch self {
            case .core:
                return "Core Spark"
            case .lowerBody:
                return "Lower Body Drive"
            case .upperBody:
                return "Upper Body Primer"
            case .mobilityReset:
                return "Mobility Reset"
            case .athleticCircuit:
                return "Athletic Circuit"
            }
        }

        var subtitle: String {
            switch self {
            case .core:
                return "Core control"
            case .lowerBody:
                return "Legs and hips"
            case .upperBody:
                return "Push and posture"
            case .mobilityReset:
                return "Range and balance"
            case .athleticCircuit:
                return "Pace and power"
            }
        }

        var focusBodyRegions: Set<BodyRegion> {
            switch self {
            case .core:
                return [.core]
            case .lowerBody:
                return [.lower]
            case .upperBody:
                return [.upper]
            case .mobilityReset:
                return [.mobility]
            case .athleticCircuit:
                return [.fullBody, .core]
            }
        }

        var focusMovementPatterns: Set<MovementPattern> {
            switch self {
            case .core:
                return [.coreAntiExtension, .coreFlexion, .coreRotation]
            case .lowerBody:
                return [.squat, .hinge, .lunge, .balance]
            case .upperBody:
                return [.push, .pull, .mobility]
            case .mobilityReset:
                return [.mobility, .balance, .yogaHold]
            case .athleticCircuit:
                return [.cardio, .lunge, .coreAntiExtension, .coreFlexion]
            }
        }

        func planningGoal(anchor: FitnessGoal) -> FitnessGoal {
            switch self {
            case .mobilityReset:
                return .longevity
            case .athleticCircuit:
                return .performance
            case .core, .lowerBody, .upperBody:
                return anchor
            }
        }

        func reasonLead(anchor: FitnessGoal) -> String {
            switch self {
            case .core:
                return "Core-focused quick start anchored to \(anchor.displayName.lowercased())."
            case .lowerBody:
                return "Lower-body quick start anchored to \(anchor.displayName.lowercased())."
            case .upperBody:
                return "Upper-body quick start anchored to \(anchor.displayName.lowercased())."
            case .mobilityReset:
                return "Mobility-reset quick start anchored to \(anchor.displayName.lowercased())."
            case .athleticCircuit:
                return "Athletic-circuit quick start anchored to \(anchor.displayName.lowercased())."
            }
        }
    }

    static var defaultSpecs: [VariantSpec] {
        [
            VariantSpec(focus: .core, intensity: .beginner),
            VariantSpec(focus: .mobilityReset, intensity: .beginner),
            VariantSpec(focus: .lowerBody, intensity: .intermediate),
            VariantSpec(focus: .upperBody, intensity: .intermediate),
            VariantSpec(focus: .athleticCircuit, intensity: .intermediate)
        ]
    }

    func makeVariant(
        spec: VariantSpec,
        deckIndex: Int,
        profile: UserProfile,
        recentWorkoutHistory: [RecentWorkoutHistoryItem],
        generatedAt: Date,
        dailySeed: String
    ) -> QuickStartPlanVariant? {
        let variantSeed = "\(dailySeed)|\(spec.focus.rawValue)|\(spec.intensity.rawValue)"
        let usesChallengeLite = shouldUseChallengeLite(for: profile, intendedIntensity: spec.intensity)
        let fitnessLevel = usesChallengeLite ? FitnessLevel.beginner : fitnessLevel(for: spec.intensity)
        let input = PlanGenerationInput(
            profile: profile,
            goal: spec.focus.planningGoal(anchor: profile.primaryGoal),
            fitnessLevel: fitnessLevel,
            sessionLength: .seven,
            recentWorkoutHistory: recentWorkoutHistory,
            focusBodyRegions: spec.focus.focusBodyRegions,
            focusMovementPatterns: spec.focus.focusMovementPatterns,
            variantSeed: variantSeed
        )
        let planId = DeterministicHash.uuid(from: "\(variantSeed)|plan")
        let generatedPlan = generator.generate(
            input: input,
            planId: planId,
            generatedAt: generatedAt
        )

        guard !generatedPlan.blocks.flatMap(\.exercises).isEmpty else {
            return nil
        }

        let titlePrefix = profile.primaryGoal.displayName
        let title = usesChallengeLite
            ? "\(titlePrefix) Challenge Lite \(spec.focus.displayName)"
            : "\(titlePrefix) \(spec.focus.displayName)"
        let subtitle = usesChallengeLite
            ? "\(spec.intensity.displayName) - Challenge Lite - 7 min"
            : "\(spec.intensity.displayName) - 7 min - \(spec.focus.subtitle)"
        let reason = reason(
            for: spec,
            profile: profile,
            generatedPlan: generatedPlan,
            usesChallengeLite: usesChallengeLite,
            actualFitnessLevel: fitnessLevel
        )
        let plan = WorkoutPlanV2(
            id: generatedPlan.id,
            title: title,
            subtitle: subtitle,
            goal: generatedPlan.goal,
            estimatedMinutes: generatedPlan.estimatedMinutes,
            difficulty: generatedPlan.difficulty,
            coach: generatedPlan.coach,
            blocks: generatedPlan.blocks,
            generatedAt: generatedPlan.generatedAt,
            planReason: reason,
            source: generatedPlan.source
        )

        return QuickStartPlanVariant(
            id: DeterministicHash.uuid(from: "\(variantSeed)|variant").uuidString,
            title: title,
            subtitle: subtitle,
            intensityLabel: spec.intensity,
            plan: plan,
            reason: reason,
            deckIndex: deckIndex
        )
    }

    func reason(
        for spec: VariantSpec,
        profile: UserProfile,
        generatedPlan: WorkoutPlanV2,
        usesChallengeLite: Bool,
        actualFitnessLevel: FitnessLevel
    ) -> String {
        let intensityNote: String
        if usesChallengeLite {
            intensityNote = "Challenge Lite keeps the intermediate option beginner-safe for this profile."
        } else {
            intensityNote = "Generated with \(actualFitnessLevel.displayName.lowercased()) intensity rules."
        }

        return "\(spec.focus.reasonLead(anchor: profile.primaryGoal)) \(intensityNote) \(generatedPlan.planReason)"
    }

    func fitnessLevel(for intensity: QuickStartPlanIntensity) -> FitnessLevel {
        switch intensity {
        case .beginner:
            return .beginner
        case .intermediate:
            return .intermediate
        }
    }

    func shouldUseChallengeLite(
        for profile: UserProfile,
        intendedIntensity: QuickStartPlanIntensity
    ) -> Bool {
        guard intendedIntensity == .intermediate else { return false }
        return profile.fitnessLevel == .beginner
            || profile.age < 18
            || profile.ageBracket == .senior
    }

    func dailyOrderedSpecs(
        profile: UserProfile,
        dayStart: Date
    ) -> [VariantSpec] {
        let baseSeed = "\(profile.id.uuidString)|\(profile.primaryGoal.rawValue)|\(Self.generationVersion)"
        let shuffled = Self.defaultSpecs.sorted { lhs, rhs in
            let left = DeterministicHash.hash64("\(baseSeed)|\(lhs.focus.rawValue)|\(lhs.intensity.rawValue)")
            let right = DeterministicHash.hash64("\(baseSeed)|\(rhs.focus.rawValue)|\(rhs.intensity.rawValue)")
            if left == right {
                return lhs.focus.rawValue < rhs.focus.rawValue
            }
            return left < right
        }

        guard !shuffled.isEmpty else { return [] }
        let offset = dayOrdinal(for: dayStart) % shuffled.count
        return Array(shuffled[offset...]) + Array(shuffled[..<offset])
    }

    func seed(profile: UserProfile, dayKey: String) -> String {
        [
            profile.id.uuidString,
            dayKey,
            profile.primaryGoal.rawValue,
            Self.generationVersion
        ].joined(separator: "|")
    }

    func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    func dayOrdinal(for date: Date) -> Int {
        if let ordinal = calendar.ordinality(of: .day, in: .era, for: date) {
            return ordinal
        }

        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return ((components.year ?? 0) * 372) + ((components.month ?? 0) * 31) + (components.day ?? 0)
    }
}
