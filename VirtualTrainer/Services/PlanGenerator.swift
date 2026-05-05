import Foundation

nonisolated final class PlanGenerator {
    func generate(
        input: PlanGenerationInput,
        planId: UUID = UUID(),
        generatedAt: Date = Date()
    ) -> WorkoutPlanV2 {
        let rules = PlanGenerationRules.resolved(for: input)
        let candidates = filteredCandidates(for: input, rules: rules)
        let slots = templateSlots(for: input.goal, maxExercises: rules.maxExercises)
        let selected = selectExercises(from: candidates, slots: slots, input: input, rules: rules)
        let blocks = buildBlocks(from: selected, input: input, rules: rules)

        return WorkoutPlanV2(
            id: planId,
            title: planTitle(for: input),
            subtitle: planSubtitle(for: input),
            goal: goalStatement(for: input.goal),
            estimatedMinutes: input.sessionLength.rawValue,
            difficulty: planDifficulty(for: input.fitnessLevel),
            coach: input.preferredCoach.coachPersonality,
            blocks: blocks,
            generatedAt: generatedAt,
            planReason: planReason(for: input, rules: rules),
            source: .generatedLocal
        )
    }
}

nonisolated private extension PlanGenerator {
    struct PlanSlot {
        let title: String
        let blockTitle: String
        let blockType: WorkoutBlockType
        let patterns: [MovementPattern]
        let requiredTags: Set<PlanTag>
        let preferredTags: Set<PlanTag>
        let coachingFocus: String
    }

    struct SelectedExercise {
        let slot: PlanSlot
        let metadata: ExercisePlanMetadata
    }

    func filteredCandidates(
        for input: PlanGenerationInput,
        rules: PlanGenerationRules
    ) -> [ExercisePlanMetadata] {
        ExerciseMetadataCatalog.plannedWorkoutMetadata.filter { metadata in
            guard !input.excludedExercises.contains(metadata.exerciseType),
                  let difficulty = metadata.difficulty,
                  rules.allowedDifficulties.contains(difficulty),
                  metadata.requiredEquipment.isSubset(of: input.effectiveEquipment)
            else { return false }

            if input.fitnessLevel == .beginner,
               !metadata.planTags.contains(.beginnerFriendly) {
                return false
            }

            if isDumbbellExercise(metadata),
               !input.effectiveEquipment.contains(.dumbbells) {
                return false
            }

            return true
        }
    }

    func selectExercises(
        from candidates: [ExercisePlanMetadata],
        slots: [PlanSlot],
        input: PlanGenerationInput,
        rules: PlanGenerationRules
    ) -> [SelectedExercise] {
        var selected: [SelectedExercise] = []
        var usedExerciseTypes = Set<ExerciseType>()

        for slot in slots {
            guard selected.count < rules.maxExercises else { break }

            let matching = candidates.filter {
                !usedExerciseTypes.contains($0.exerciseType) && matches($0, slot: slot)
            }
            let fallback = candidates.filter {
                !usedExerciseTypes.contains($0.exerciseType) && sharesGoalTag($0, goal: input.goal)
            }
            let pool = matching.isEmpty ? fallback : matching
            let impactAdjustedPool = lowImpactPoolIfAvailable(pool, rules: rules)

            guard let metadata = sorted(
                impactAdjustedPool,
                for: slot,
                input: input,
                rules: rules
            ).first(where: {
                respectsCameraSwitchLimit(
                    adding: $0.exerciseType.cameraPosition,
                    to: selected.map { $0.metadata.exerciseType.cameraPosition },
                    limit: rules.maxCameraSwitches
                )
            }) else {
                continue
            }

            selected.append(SelectedExercise(slot: slot, metadata: metadata))
            usedExerciseTypes.insert(metadata.exerciseType)
        }

        return selected
    }

    func buildBlocks(
        from selected: [SelectedExercise],
        input: PlanGenerationInput,
        rules: PlanGenerationRules
    ) -> [WorkoutBlock] {
        var blockGroups: [(title: String, type: WorkoutBlockType, exercises: [PlannedExercise])] = []

        for item in selected {
            let exercise = plannedExercise(for: item.metadata, slot: item.slot, input: input, rules: rules)

            if let lastIndex = blockGroups.indices.last,
               blockGroups[lastIndex].title == item.slot.blockTitle,
               blockGroups[lastIndex].type == item.slot.blockType {
                blockGroups[lastIndex].exercises.append(exercise)
            } else {
                blockGroups.append(
                    (
                        title: item.slot.blockTitle,
                        type: item.slot.blockType,
                        exercises: [exercise]
                    )
                )
            }
        }

        return blockGroups.map {
            WorkoutBlock(title: $0.title, type: $0.type, exercises: $0.exercises)
        }
    }

    func plannedExercise(
        for metadata: ExercisePlanMetadata,
        slot: PlanSlot,
        input: PlanGenerationInput,
        rules: PlanGenerationRules
    ) -> PlannedExercise {
        let setCount = setCount(for: slot.blockType, input: input)
        let baseTarget = workoutTarget(for: metadata, slot: slot, input: input, rules: rules)
        let sets = (1...setCount).map { index in
            PlannedSet(
                setIndex: index,
                target: progressedTarget(baseTarget, setIndex: index, input: input)
            )
        }

        return PlannedExercise(
            exerciseType: metadata.exerciseType,
            sets: sets,
            restSeconds: restSeconds(for: metadata, slot: slot, rules: rules),
            coachingFocus: slot.coachingFocus,
            cameraPosition: metadata.exerciseType.cameraPosition,
            allowSwap: true
        )
    }

    func setCount(for blockType: WorkoutBlockType, input: PlanGenerationInput) -> Int {
        switch blockType {
        case .warmup, .cooldown:
            return 1
        case .finisher:
            return input.sessionLength == .thirtyFive ? 2 : 1
        case .main, .circuit:
            return input.sessionLength.mainSetCount
        }
    }

    func workoutTarget(
        for metadata: ExercisePlanMetadata,
        slot: PlanSlot,
        input: PlanGenerationInput,
        rules: PlanGenerationRules
    ) -> WorkoutTarget {
        let definition = metadata.exerciseType.definition
        let base = input.fitnessLevel == .beginner
            ? metadata.defaultBeginnerTarget
            : metadata.defaultIntermediateTarget
        let adjusted = adjustedTarget(base, multiplier: rules.targetMultiplier)

        if definition?.movementType == .isometric || metadata.planTags.contains(.isometric) {
            return .hold(seconds: max(adjusted, 10))
        }

        if input.goal == .performance || slot.blockType == .warmup {
            let timedSeconds = timedWorkSeconds(for: input, rules: rules)
            return .timed(seconds: timedSeconds)
        }

        return .reps(max(adjusted, 4))
    }

    func progressedTarget(
        _ target: WorkoutTarget,
        setIndex: Int,
        input: PlanGenerationInput
    ) -> WorkoutTarget {
        guard setIndex > 1 else { return target }

        switch target {
        case .reps(let count):
            let increment = input.goal == .strength ? setIndex - 1 : 0
            return .reps(count + increment)
        case .hold(let seconds):
            return .hold(seconds: seconds + ((setIndex - 1) * 5))
        case .timed(let seconds):
            return .timed(seconds: seconds)
        case .amrap, .open:
            return target
        }
    }

    func adjustedTarget(_ base: Int, multiplier: Double) -> Int {
        max(Int((Double(base) * multiplier).rounded()), 1)
    }

    func timedWorkSeconds(for input: PlanGenerationInput, rules: PlanGenerationRules) -> Int {
        let base: Int
        switch input.sessionLength {
        case .seven:
            base = 25
        case .fifteen:
            base = 30
        case .twentyFive:
            base = 40
        case .thirtyFive:
            base = 45
        }
        return max(Int((Double(base) * rules.targetMultiplier).rounded()), 20)
    }

    func restSeconds(
        for metadata: ExercisePlanMetadata,
        slot: PlanSlot,
        rules: PlanGenerationRules
    ) -> Int {
        let slotBonus: Int
        switch slot.blockType {
        case .warmup, .cooldown:
            slotBonus = 0
        case .finisher:
            slotBonus = -10
        case .main, .circuit:
            slotBonus = 0
        }

        return max(15, metadata.defaultRestSeconds + rules.restBonusSeconds + slotBonus)
    }

    func sorted(
        _ candidates: [ExercisePlanMetadata],
        for slot: PlanSlot,
        input: PlanGenerationInput,
        rules: PlanGenerationRules
    ) -> [ExercisePlanMetadata] {
        candidates.sorted { lhs, rhs in
            let leftScore = score(lhs, slot: slot, input: input, rules: rules)
            let rightScore = score(rhs, slot: slot, input: input, rules: rules)
            if leftScore == rightScore {
                return catalogIndex(of: lhs.exerciseType) < catalogIndex(of: rhs.exerciseType)
            }
            return leftScore < rightScore
        }
    }

    func score(
        _ metadata: ExercisePlanMetadata,
        slot: PlanSlot,
        input: PlanGenerationInput,
        rules: PlanGenerationRules
    ) -> Int {
        var score = catalogIndex(of: metadata.exerciseType)

        if !sharesGoalTag(metadata, goal: input.goal) {
            score += 40
        }
        if metadata.preferredTagsIntersection(slot.preferredTags).isEmpty {
            score += 10
        }
        if metadata.difficulty == .intermediate {
            score += input.fitnessLevel == .intermediate ? 4 : 80
        }
        if isHighImpact(metadata) {
            score += rules.avoidHighImpactWhenAlternativesExist ? 80 : 8
        }
        if rules.lowerImpactBias && metadata.planTags.contains(.lowImpact) {
            score -= 8
        }
        if rules.balanceMobilityBias && isBalanceMobilityOrIsometric(metadata) {
            score -= 12
        }
        if rules.bodyweightFirst && !isBodyweightPrimary(metadata) {
            score += 35
        }
        if input.goal == .strength,
           input.fitnessLevel == .intermediate,
           input.effectiveEquipment.contains(.dumbbells),
           isDumbbellExercise(metadata) {
            score -= 25
        }
        if input.recentWorkoutHistory.contains(where: { $0.exerciseType == metadata.exerciseType }) {
            score += 12
        }

        return score
    }

    func matches(_ metadata: ExercisePlanMetadata, slot: PlanSlot) -> Bool {
        guard slot.requiredTags.isSubset(of: metadata.planTags) else { return false }

        if slot.patterns.contains(metadata.movementPattern) {
            return true
        }

        return !metadata.preferredTagsIntersection(slot.preferredTags).isEmpty
    }

    func lowImpactPoolIfAvailable(
        _ pool: [ExercisePlanMetadata],
        rules: PlanGenerationRules
    ) -> [ExercisePlanMetadata] {
        guard rules.avoidHighImpactWhenAlternativesExist else { return pool }
        return pool.filter { !isHighImpact($0) }
    }

    func respectsCameraSwitchLimit(
        adding cameraPosition: CameraPosition,
        to existing: [CameraPosition],
        limit: Int
    ) -> Bool {
        var cameras = existing
        cameras.append(cameraPosition)
        return cameraSwitchCount(in: cameras) <= limit
    }

    func cameraSwitchCount(in cameras: [CameraPosition]) -> Int {
        guard cameras.count > 1 else { return 0 }

        var switches = 0
        for index in cameras.indices.dropFirst() {
            if cameras[index] != cameras[cameras.index(before: index)] {
                switches += 1
            }
        }
        return switches
    }

    func sharesGoalTag(_ metadata: ExercisePlanMetadata, goal: FitnessGoal) -> Bool {
        metadata.planTags.contains(planTag(for: goal))
    }

    func planTag(for goal: FitnessGoal) -> PlanTag {
        switch goal {
        case .strength:
            return .strength
        case .performance:
            return .performance
        case .longevity:
            return .longevity
        }
    }

    func isHighImpact(_ metadata: ExercisePlanMetadata) -> Bool {
        metadata.planTags.contains(.highImpact) || metadata.contraindicationTags.contains(.highImpact)
    }

    func isDumbbellExercise(_ metadata: ExercisePlanMetadata) -> Bool {
        metadata.requiredEquipment.contains(.dumbbells) || metadata.planTags.contains(.dumbbell)
    }

    func isBodyweightPrimary(_ metadata: ExercisePlanMetadata) -> Bool {
        let bodyweightEquipment: Set<EquipmentOption> = [.bodyweight, .mat, .chair, .wall, .bench, .step]
        return metadata.requiredEquipment.isSubset(of: bodyweightEquipment)
            && !isDumbbellExercise(metadata)
    }

    func isBalanceMobilityOrIsometric(_ metadata: ExercisePlanMetadata) -> Bool {
        metadata.movementPattern == .balance
            || metadata.movementPattern == .mobility
            || metadata.movementPattern == .yogaHold
            || metadata.planTags.contains(.isometric)
    }

    func catalogIndex(of exerciseType: ExerciseType) -> Int {
        ExerciseMetadataCatalog.all.firstIndex { $0.exerciseType == exerciseType } ?? Int.max
    }

    func planDifficulty(for level: FitnessLevel) -> ExerciseDifficulty {
        switch level {
        case .beginner:
            return .beginner
        case .intermediate:
            return .intermediate
        }
    }
}

nonisolated private extension PlanGenerator {
    func templateSlots(for goal: FitnessGoal, maxExercises: Int) -> [PlanSlot] {
        switch goal {
        case .strength:
            return strengthSlots(maxExercises: maxExercises)
        case .performance:
            return performanceSlots(maxExercises: maxExercises)
        case .longevity:
            return longevitySlots(maxExercises: maxExercises)
        }
    }

    func strengthSlots(maxExercises: Int) -> [PlanSlot] {
        var slots: [PlanSlot] = [
            PlanSlot(
                title: "Prime",
                blockTitle: "Warmup",
                blockType: .warmup,
                patterns: [.mobility, .balance, .cardio],
                requiredTags: [.warmup],
                preferredTags: [.lowImpact, .beginnerFriendly],
                coachingFocus: "Prepare joints and find controlled range before loading the session."
            ),
            PlanSlot(
                title: "Lower Body",
                blockTitle: "Strength Practice",
                blockType: .main,
                patterns: [.squat, .lunge],
                requiredTags: [.strength],
                preferredTags: [.lowImpact, .bodyweight],
                coachingFocus: "Build muscle with clean depth, tempo, and knee tracking."
            ),
            PlanSlot(
                title: "Push",
                blockTitle: "Strength Practice",
                blockType: .main,
                patterns: [.push],
                requiredTags: [.strength],
                preferredTags: [.lowImpact, .dumbbell, .bodyweight],
                coachingFocus: "Press with control and keep the shoulders stacked."
            ),
            PlanSlot(
                title: "Core",
                blockTitle: "Core Finish",
                blockType: .finisher,
                patterns: [.coreAntiExtension, .coreFlexion, .coreRotation],
                requiredTags: [.strength],
                preferredTags: [.lowImpact, .isometric, .beginnerFriendly],
                coachingFocus: "Keep the trunk steady and finish with strict control."
            ),
        ]

        if maxExercises >= 5 {
            slots.insert(
                PlanSlot(
                    title: "Hinge",
                    blockTitle: "Strength Practice",
                    blockType: .main,
                    patterns: [.hinge],
                    requiredTags: [.strength],
                    preferredTags: [.lowImpact, .bodyweight],
                    coachingFocus: "Train the posterior chain without rushing the hinge."
                ),
                at: 3
            )
        }

        if maxExercises >= 6 {
            slots.append(
                PlanSlot(
                    title: "Pull",
                    blockTitle: "Strength Practice",
                    blockType: .main,
                    patterns: [.pull],
                    requiredTags: [.strength],
                    preferredTags: [.dumbbell, .lowImpact],
                    coachingFocus: "Pull smoothly and avoid swinging through the reps."
                )
            )
        }

        if maxExercises >= 7 {
            slots.append(
                PlanSlot(
                    title: "Secondary Lower",
                    blockTitle: "Strength Practice",
                    blockType: .main,
                    patterns: [.hinge, .balance, .squat],
                    requiredTags: [.strength],
                    preferredTags: [.lowImpact, .beginnerFriendly],
                    coachingFocus: "Add more lower-body volume while staying precise."
                )
            )
        }

        if maxExercises >= 8 {
            slots.append(
                PlanSlot(
                    title: "Core Control",
                    blockTitle: "Core Finish",
                    blockType: .finisher,
                    patterns: [.coreAntiExtension, .coreRotation],
                    requiredTags: [.strength],
                    preferredTags: [.lowImpact, .isometric],
                    coachingFocus: "Close with a stable trunk and no wasted motion."
                )
            )
        }

        return Array(slots.prefix(maxExercises))
    }

    func performanceSlots(maxExercises: Int) -> [PlanSlot] {
        var slots: [PlanSlot] = [
            PlanSlot(
                title: "Warmup",
                blockTitle: "Warmup",
                blockType: .warmup,
                patterns: [.mobility, .balance, .coreFlexion, .cardio],
                requiredTags: [.warmup],
                preferredTags: [.performance, .lowImpact, .beginnerFriendly],
                coachingFocus: "Raise pace gradually before the circuit starts."
            ),
            PlanSlot(
                title: "Circuit Pace",
                blockTitle: "Athletic Circuit",
                blockType: .circuit,
                patterns: [.cardio, .coreFlexion, .lunge, .coreAntiExtension],
                requiredTags: [.performance],
                preferredTags: [.lowImpact, .beginnerFriendly],
                coachingFocus: "Move with rhythm and keep the effort sustainable."
            ),
            PlanSlot(
                title: "Athletic Strength",
                blockTitle: "Athletic Circuit",
                blockType: .circuit,
                patterns: [.lunge, .hinge, .push, .squat],
                requiredTags: [.performance],
                preferredTags: [.lowImpact, .bodyweight],
                coachingFocus: "Stay athletic without sacrificing clean mechanics."
            ),
            PlanSlot(
                title: "Core Finisher",
                blockTitle: "Core Finish",
                blockType: .finisher,
                patterns: [.coreAntiExtension, .coreFlexion, .coreRotation],
                requiredTags: [],
                preferredTags: [.performance, .finisher, .lowImpact],
                coachingFocus: "Finish strong with braced, repeatable movement."
            ),
        ]

        if maxExercises >= 5 {
            slots.insert(
                PlanSlot(
                    title: "Full-Body Pace",
                    blockTitle: "Athletic Circuit",
                    blockType: .circuit,
                    patterns: [.cardio, .coreAntiExtension, .coreFlexion],
                    requiredTags: [.performance],
                    preferredTags: [.lowImpact],
                    coachingFocus: "Keep pace high enough to train stamina, not sloppy."
                ),
                at: 3
            )
        }

        if maxExercises >= 6 {
            slots.append(
                PlanSlot(
                    title: "Power Control",
                    blockTitle: "Athletic Circuit",
                    blockType: .circuit,
                    patterns: [.squat, .hinge, .push],
                    requiredTags: [.performance],
                    preferredTags: [.lowImpact],
                    coachingFocus: "Add athletic volume with controlled speed."
                )
            )
        }

        if maxExercises >= 7 {
            slots.append(
                PlanSlot(
                    title: "Rotational Core",
                    blockTitle: "Core Finish",
                    blockType: .finisher,
                    patterns: [.coreRotation, .coreAntiExtension],
                    requiredTags: [],
                    preferredTags: [.performance, .finisher, .lowImpact],
                    coachingFocus: "Keep trunk control sharp while fatigue builds."
                )
            )
        }

        if maxExercises >= 8 {
            slots.append(
                PlanSlot(
                    title: "Cooldown Reset",
                    blockTitle: "Cooldown",
                    blockType: .cooldown,
                    patterns: [.mobility, .yogaHold, .balance],
                    requiredTags: [.longevity],
                    preferredTags: [.lowImpact, .isometric],
                    coachingFocus: "Bring the session down with mobility and balance."
                )
            )
        }

        return Array(slots.prefix(maxExercises))
    }

    func longevitySlots(maxExercises: Int) -> [PlanSlot] {
        var slots: [PlanSlot] = [
            PlanSlot(
                title: "Mobility",
                blockTitle: "Mobility Prep",
                blockType: .warmup,
                patterns: [.mobility, .yogaHold],
                requiredTags: [.longevity],
                preferredTags: [.warmup, .lowImpact, .beginnerFriendly],
                coachingFocus: "Open range of motion without forcing intensity."
            ),
            PlanSlot(
                title: "Balance",
                blockTitle: "Joint-Friendly Strength",
                blockType: .main,
                patterns: [.balance],
                requiredTags: [.longevity],
                preferredTags: [.lowImpact, .beginnerFriendly],
                coachingFocus: "Build balance and steady control from the ground up."
            ),
            PlanSlot(
                title: "Stability",
                blockTitle: "Joint-Friendly Strength",
                blockType: .main,
                patterns: [.coreAntiExtension, .squat, .hinge],
                requiredTags: [.longevity, .isometric],
                preferredTags: [.isometric, .lowImpact, .beginnerFriendly],
                coachingFocus: "Train stability with calm, joint-friendly mechanics."
            ),
            PlanSlot(
                title: "Cooldown",
                blockTitle: "Cooldown",
                blockType: .cooldown,
                patterns: [.yogaHold, .mobility, .balance],
                requiredTags: [.longevity],
                preferredTags: [.isometric, .lowImpact, .beginnerFriendly],
                coachingFocus: "Finish with controlled breathing, posture, and mobility."
            ),
        ]

        if maxExercises >= 5 {
            slots.insert(
                PlanSlot(
                    title: "Low-Impact Strength",
                    blockTitle: "Joint-Friendly Strength",
                    blockType: .main,
                    patterns: [.squat, .hinge, .coreFlexion],
                    requiredTags: [.longevity],
                    preferredTags: [.lowImpact, .beginnerFriendly],
                    coachingFocus: "Add useful strength without chasing intensity."
                ),
                at: 3
            )
        }

        if maxExercises >= 6 {
            slots.append(
                PlanSlot(
                    title: "Posture",
                    blockTitle: "Mobility Prep",
                    blockType: .warmup,
                    patterns: [.mobility, .balance],
                    requiredTags: [.longevity],
                    preferredTags: [.warmup, .lowImpact],
                    coachingFocus: "Keep posture tall and movement smooth."
                )
            )
        }

        if maxExercises >= 7 {
            slots.append(
                PlanSlot(
                    title: "Core Stability",
                    blockTitle: "Joint-Friendly Strength",
                    blockType: .main,
                    patterns: [.coreAntiExtension, .balance],
                    requiredTags: [.longevity],
                    preferredTags: [.isometric, .lowImpact],
                    coachingFocus: "Build trunk stability for repeatable daily movement."
                )
            )
        }

        if maxExercises >= 8 {
            slots.append(
                PlanSlot(
                    title: "Final Reset",
                    blockTitle: "Cooldown",
                    blockType: .cooldown,
                    patterns: [.yogaHold, .mobility],
                    requiredTags: [.longevity],
                    preferredTags: [.isometric, .lowImpact],
                    coachingFocus: "Close with mobility and a clean breathing rhythm."
                )
            )
        }

        return Array(slots.prefix(maxExercises))
    }

    func planTitle(for input: PlanGenerationInput) -> String {
        switch input.goal {
        case .strength:
            return "\(input.sessionLength.rawValue)-Minute Strength"
        case .performance:
            return "\(input.sessionLength.rawValue)-Minute Performance"
        case .longevity:
            return "\(input.sessionLength.rawValue)-Minute Longevity"
        }
    }

    func planSubtitle(for input: PlanGenerationInput) -> String {
        "\(input.fitnessLevel.displayName) plan for \(input.profile.firstName)"
    }

    func goalStatement(for goal: FitnessGoal) -> String {
        switch goal {
        case .strength:
            return "Build muscle, control, and progressive reps."
        case .performance:
            return "Train stamina, athleticism, pace, and circuit capacity."
        case .longevity:
            return "Build mobility, balance, and joint-friendly consistency."
        }
    }

    func planReason(for input: PlanGenerationInput, rules: PlanGenerationRules) -> String {
        let equipment = input.effectiveEquipment
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.displayName)
            .joined(separator: ", ")

        let ageNote: String
        switch input.profile.age {
        case ..<18:
            ageNote = "conservative bodyweight-first intensity"
        case 18...34:
            ageNote = "baseline training dose"
        case 35...49:
            ageNote = input.fitnessLevel == .beginner
                ? "extra rest for a beginner-friendly warmup"
                : "baseline training with modest rest padding"
        case 50...64:
            ageNote = "lower-impact selections and longer rest"
        default:
            ageNote = "conservative intensity with balance and mobility bias"
        }

        return "Generated locally from \(input.goal.displayName.lowercased()) goal, \(input.fitnessLevel.displayName.lowercased()) level, \(input.sessionLength.rawValue)-minute length, \(equipment), and \(ageNote). Camera switches capped at \(rules.maxCameraSwitches)."
    }
}

nonisolated private extension ExercisePlanMetadata {
    func preferredTagsIntersection(_ tags: Set<PlanTag>) -> Set<PlanTag> {
        planTags.intersection(tags)
    }
}
