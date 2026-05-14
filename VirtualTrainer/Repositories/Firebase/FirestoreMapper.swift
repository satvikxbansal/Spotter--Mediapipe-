import Foundation

nonisolated func mapToProfileDocument(_ profile: UserProfile) -> FirestoreProfileDocument {
    let operationId = profile.syncMetadata.pendingOperationId ?? UUID()
    return FirestoreProfileDocument(
        schemaVersion: FirestoreDTOSchema.currentVersion,
        accountId: normalizedAccountId(profile.accountId),
        profileId: lowercaseUUID(profile.id),
        displayName: profile.displayName,
        genderIdentity: profile.genderIdentity.rawValue,
        age: profile.age,
        height: profile.height,
        heightUnit: profile.heightUnit.rawValue,
        weight: profile.weight,
        weightUnit: profile.weightUnit.rawValue,
        primaryGoal: profile.primaryGoal.rawValue,
        fitnessLevel: profile.fitnessLevel.rawValue,
        equipment: profile.equipment.map(\.rawValue).sorted(),
        preferredCoach: profile.preferredCoach.rawValue,
        selectedTheme: profile.selectedTheme.rawValue,
        limitations: profile.limitations.map(\.rawValue).sorted(),
        preferredSessionLength: profile.preferredSessionLength.rawValue,
        workoutDaysPerWeek: profile.workoutDaysPerWeek,
        reminderPreference: profile.reminderPreference.rawValue,
        timezoneIdentifier: profile.timezoneIdentifier,
        avatarStyle: profile.avatarStyle?.rawValue,
        onboardingSchemaVersion: profile.onboardingSchemaVersion,
        profileSchemaVersion: profile.profileSchemaVersion,
        onboardingCompletedAt: profile.onboardingCompletedAt,
        createdAt: profile.createdAt,
        updatedAt: profile.updatedAt,
        serverUpdatedAt: nil,
        deletedAt: profile.deletedAt,
        syncMetadata: mapToFirestoreSyncMetadata(profile.syncMetadata),
        operationId: operationId
    )
}

nonisolated func mapFromProfileDocument(_ doc: FirestoreProfileDocument) -> UserProfile {
    let updatedAt = doc.updatedAt
    return UserProfile(
        id: uuid(from: doc.profileId),
        accountId: doc.accountId,
        displayName: doc.displayName,
        genderIdentity: GenderIdentity(rawValue: doc.genderIdentity) ?? .preferNotToSay,
        age: doc.age,
        height: doc.height,
        heightUnit: UnitPreference(rawValue: doc.heightUnit) ?? .metric,
        weight: doc.weight,
        weightUnit: UnitPreference(rawValue: doc.weightUnit) ?? .metric,
        primaryGoal: FitnessGoal(rawValue: doc.primaryGoal) ?? .strength,
        fitnessLevel: FitnessLevel(rawValue: doc.fitnessLevel) ?? .beginner,
        equipment: doc.equipment.compactMap(EquipmentOption.init(rawValue:)),
        preferredCoach: CoachPreference(rawValue: doc.preferredCoach) ?? .bennett,
        selectedTheme: SpotterThemeOption(rawValue: doc.selectedTheme) ?? .hyper,
        limitations: Set(doc.limitations.compactMap(PhysicalLimitation.init(rawValue:))),
        preferredSessionLength: PlanSessionLength(rawValue: doc.preferredSessionLength) ?? .twentyFive,
        workoutDaysPerWeek: doc.workoutDaysPerWeek ?? UserProfile.defaultWorkoutDaysPerWeek,
        reminderPreference: ReminderPreference(rawValue: doc.reminderPreference) ?? .none,
        timezoneIdentifier: doc.timezoneIdentifier.isEmpty ? TimeZone.current.identifier : doc.timezoneIdentifier,
        avatarStyle: doc.avatarStyle.flatMap(AvatarStyle.init(rawValue:)) ?? .default,
        onboardingSchemaVersion: doc.onboardingSchemaVersion,
        profileSchemaVersion: doc.profileSchemaVersion,
        onboardingCompletedAt: doc.onboardingCompletedAt,
        createdAt: doc.createdAt,
        updatedAt: updatedAt,
        deletedAt: doc.deletedAt,
        syncMetadata: mapFromFirestoreSyncMetadata(
            doc.syncMetadata,
            accountId: doc.accountId,
            fallbackDate: updatedAt
        )
    )
}

nonisolated func mapToWorkoutDocument(_ summary: WorkoutSessionSummary) -> FirestoreWorkoutDocument {
    FirestoreWorkoutDocument(
        schemaVersion: FirestoreDTOSchema.currentVersion,
        accountId: normalizedAccountId(summary.accountId),
        workoutId: lowercaseUUID(summary.id),
        summarySchemaVersion: summary.summarySchemaVersion,
        appBuildVersion: summary.appBuildVersion,
        mode: summary.mode.rawValue,
        planId: summary.planId.map(lowercaseUUID),
        planTitle: summary.planTitle,
        title: summary.title,
        goal: summary.goal,
        coach: summary.coach.rawValue,
        startedAt: summary.startedAt,
        endedAt: summary.endedAt,
        serverEndedAt: summary.serverEndedAt,
        durationSeconds: summary.durationSeconds,
        totalReps: summary.totalReps,
        totalHoldSeconds: summary.totalHoldSeconds,
        averageFormScore: summary.averageFormScore,
        completionPercent: summary.completionPercent,
        setCount: summary.exerciseSummaries.count,
        repQualityEventCount: summary.exerciseSummaries.flatMap(\.repQualityEvents).count,
        cueEventCount: summary.exerciseSummaries.flatMap(\.cueEvents).count,
        topCue: summary.topCue.map(mapToFirestoreCueEvent),
        effortSummary: summary.effortSummary,
        workoutOutcome: summary.workoutOutcome.rawValue,
        structuredEffortSummary: summary.structuredEffortSummary.map(mapToFirestoreStructuredEffortSummary),
        totalGoodFormReps: summary.totalGoodFormReps,
        totalExcellentFormReps: summary.totalExcellentFormReps,
        totalHighSeverityCues: summary.totalHighSeverityCues,
        createdAt: summary.createdAt,
        deletedAt: summary.deletedAt,
        syncMetadata: mapToFirestoreSyncMetadata(summary.syncMetadata),
        operationId: summary.syncMetadata.pendingOperationId ?? UUID()
    )
}

nonisolated func mapFromWorkoutDocument(_ doc: FirestoreWorkoutDocument) -> WorkoutSessionSummary {
    mapFromWorkoutDocument(doc, sets: [])
}

nonisolated func mapFromWorkoutDocument(
    _ doc: FirestoreWorkoutDocument,
    sets: [FirestoreWorkoutSetDocument]
) -> WorkoutSessionSummary {
    let sortedSets = sets.sorted {
        if ($0.setIndex ?? Int.max) != ($1.setIndex ?? Int.max) {
            return ($0.setIndex ?? Int.max) < ($1.setIndex ?? Int.max)
        }
        return $0.setId < $1.setId
    }
    return WorkoutSessionSummary(
        id: uuid(from: doc.workoutId),
        accountId: doc.accountId,
        summarySchemaVersion: doc.summarySchemaVersion,
        appBuildVersion: doc.appBuildVersion,
        mode: WorkoutSessionSummaryMode(rawValue: doc.mode) ?? .freeAnalysis,
        planId: doc.planId.map(uuid(from:)),
        planTitle: doc.planTitle,
        title: doc.title,
        goal: doc.goal,
        coach: CoachPersonality(rawValue: doc.coach) ?? .good,
        startedAt: doc.startedAt,
        endedAt: doc.endedAt,
        serverEndedAt: doc.serverEndedAt,
        durationSeconds: doc.durationSeconds,
        totalReps: doc.totalReps,
        totalHoldSeconds: doc.totalHoldSeconds,
        averageFormScore: doc.averageFormScore,
        completionPercent: doc.completionPercent,
        exerciseSummaries: sortedSets.map(mapFromWorkoutSetDocument),
        topCue: doc.topCue.map(mapFromFirestoreCueEvent),
        effortSummary: doc.effortSummary,
        workoutOutcome: WorkoutOutcome(rawValue: doc.workoutOutcome) ?? .partial,
        structuredEffortSummary: doc.structuredEffortSummary.map(mapFromFirestoreStructuredEffortSummary),
        totalGoodFormReps: doc.totalGoodFormReps,
        totalExcellentFormReps: doc.totalExcellentFormReps,
        totalHighSeverityCues: doc.totalHighSeverityCues,
        createdAt: doc.createdAt,
        deletedAt: doc.deletedAt,
        syncMetadata: mapFromFirestoreSyncMetadata(
            doc.syncMetadata,
            accountId: doc.accountId,
            fallbackDate: doc.createdAt
        )
    )
}

nonisolated func mapToWorkoutSetDocument(
    _ setSummary: ExerciseSetSummary,
    accountId: String,
    workoutId: UUID,
    setId: String? = nil,
    operationId: UUID = UUID()
) -> FirestoreWorkoutSetDocument {
    let resolvedSetId = setId ?? defaultSetDocumentId(for: setSummary)
    return FirestoreWorkoutSetDocument(
        schemaVersion: FirestoreDTOSchema.currentVersion,
        accountId: normalizedAccountId(accountId),
        workoutId: lowercaseUUID(workoutId),
        setId: resolvedSetId,
        exerciseType: setSummary.exerciseType.rawValue,
        setIndex: setSummary.setIndex,
        target: setSummary.target.map(mapToFirestoreWorkoutTarget),
        achievedReps: setSummary.achievedReps,
        achievedHoldSeconds: setSummary.achievedHoldSeconds,
        averageFormScore: setSummary.averageFormScore,
        cueEvents: setSummary.cueEvents.map(mapToFirestoreCueEvent),
        restExtended: setSummary.restExtended,
        skipped: setSummary.skipped,
        qualitySummary: setSummary.qualitySummary.map(mapToFirestoreSetQualitySummary),
        repQualityEvents: setSummary.repQualityEvents.map(mapToFirestoreRepQualityEvent),
        completionSource: setSummary.completionSource?.rawValue,
        completedAt: setSummary.completedAt,
        serverCompletedAt: nil,
        durationSeconds: setSummary.durationSeconds,
        peakEffort: setSummary.peakEffort,
        bestCue: setSummary.bestCue,
        worstCue: setSummary.worstCue,
        createdAt: setSummary.completedAt,
        deletedAt: nil,
        syncMetadata: nil,
        operationId: operationId
    )
}

nonisolated func mapFromWorkoutSetDocument(_ doc: FirestoreWorkoutSetDocument) -> ExerciseSetSummary {
    ExerciseSetSummary(
        exerciseType: ExerciseType(rawValue: doc.exerciseType) ?? .squat,
        setIndex: doc.setIndex,
        target: doc.target.map(mapFromFirestoreWorkoutTarget),
        achievedReps: doc.achievedReps,
        achievedHoldSeconds: doc.achievedHoldSeconds,
        averageFormScore: doc.averageFormScore,
        cueEvents: doc.cueEvents.map(mapFromFirestoreCueEvent),
        restExtended: doc.restExtended,
        skipped: doc.skipped,
        qualitySummary: doc.qualitySummary.map(mapFromFirestoreSetQualitySummary),
        repQualityEvents: doc.repQualityEvents.map(mapFromFirestoreRepQualityEvent),
        completionSource: doc.completionSource.flatMap(PlannedSetCompletionSource.init(rawValue:)),
        completedAt: doc.completedAt,
        durationSeconds: doc.durationSeconds,
        peakEffort: doc.peakEffort,
        bestCue: doc.bestCue,
        worstCue: doc.worstCue
    )
}

nonisolated func mapToTrophyEventDocument(_ event: TrophyUnlockEvent) -> FirestoreTrophyEventDocument {
    FirestoreTrophyEventDocument(
        schemaVersion: FirestoreDTOSchema.currentVersion,
        accountId: normalizedAccountId(event.accountId),
        eventId: lowercaseUUID(event.id),
        dedupeKey: event.dedupeKey,
        trophyId: event.trophyId,
        title: event.title,
        subtitle: event.subtitle,
        earnedAt: event.earnedAt,
        serverEarnedAt: event.serverEarnedAt,
        retractedAt: event.retractedAt,
        reason: event.reason,
        celebrationStyle: event.celebrationStyle.rawValue,
        deletedAt: nil,
        syncMetadata: mapToFirestoreSyncMetadata(event.syncMetadata),
        operationId: event.syncMetadata.pendingOperationId ?? UUID()
    )
}

nonisolated func mapFromTrophyEventDocument(_ doc: FirestoreTrophyEventDocument) -> TrophyUnlockEvent {
    TrophyUnlockEvent(
        id: uuid(from: doc.eventId),
        accountId: doc.accountId,
        dedupeKey: doc.dedupeKey,
        trophyId: doc.trophyId,
        title: doc.title,
        subtitle: doc.subtitle,
        earnedAt: doc.earnedAt,
        serverEarnedAt: doc.serverEarnedAt,
        retractedAt: doc.retractedAt ?? doc.deletedAt,
        reason: doc.reason,
        celebrationStyle: TrophyCelebrationStyle(rawValue: doc.celebrationStyle) ?? .standard,
        syncMetadata: mapFromFirestoreSyncMetadata(
            doc.syncMetadata,
            accountId: doc.accountId,
            fallbackDate: doc.earnedAt
        )
    )
}

nonisolated func mapToTrophyProgressCacheDocument(_ snapshot: TrophyProgressSnapshot) -> FirestoreTrophyProgressCacheDocument {
    let operationId = snapshot.progress.compactMap(\.syncMetadata.pendingOperationId).first ?? UUID()
    return FirestoreTrophyProgressCacheDocument(
        schemaVersion: FirestoreDTOSchema.currentVersion,
        accountId: normalizedAccountId(snapshot.accountId),
        catalogVersion: snapshot.catalogVersion,
        generatedAt: snapshot.generatedAt,
        serverGeneratedAt: nil,
        progress: snapshot.progress
            .sorted { $0.trophyId < $1.trophyId }
            .map(mapToFirestoreTrophyProgress),
        earnedCount: snapshot.earnedProgress.count,
        deletedAt: nil,
        syncMetadata: nil,
        operationId: operationId
    )
}

nonisolated func mapFromTrophyProgressCacheDocument(_ doc: FirestoreTrophyProgressCacheDocument) -> TrophyProgressSnapshot {
    TrophyProgressSnapshot(
        accountId: doc.accountId,
        catalogVersion: doc.catalogVersion,
        generatedAt: doc.generatedAt,
        progress: doc.progress.map(mapFromFirestoreTrophyProgress),
        unlockEventLog: [],
        newlyEarnedEvents: []
    )
}

nonisolated func mapToInsightDocument(_ insight: AIInsight) -> FirestoreInsightDocument {
    FirestoreInsightDocument(
        schemaVersion: FirestoreDTOSchema.currentVersion,
        accountId: normalizedAccountId(insight.accountId),
        insightId: insight.id,
        type: insight.type.rawValue,
        headline: insight.headline,
        message: insight.message,
        shortMessage: insight.shortMessage,
        evidence: insight.evidence.map(mapToFirestoreInsightEvidence),
        recommendedAction: insight.recommendedAction.rawValue,
        severity: insight.severity.rawValue,
        emotionalIntent: insight.emotionalIntent.rawValue,
        userValueScore: insight.userValueScore,
        confidence: insight.confidence,
        surfaces: insight.surfaces.map(\.rawValue).sorted(),
        relatedExerciseType: insight.relatedExerciseType?.rawValue,
        relatedGoal: insight.relatedGoal?.rawValue,
        createdAt: insight.createdAt,
        serverCreatedAt: insight.serverCreatedAt,
        sourcePolicyVersion: insight.sourcePolicyVersion,
        expiresAt: insight.expiresAt,
        dedupeKey: insight.dedupeKey,
        deletedAt: insight.deletedAt,
        syncMetadata: mapToFirestoreSyncMetadata(insight.syncMetadata),
        operationId: insight.syncMetadata.pendingOperationId ?? UUID()
    )
}

nonisolated func mapFromInsightDocument(_ doc: FirestoreInsightDocument) -> AIInsight {
    AIInsight(
        id: doc.insightId,
        accountId: doc.accountId,
        type: InsightType(rawValue: doc.type) ?? .consistency,
        headline: doc.headline,
        message: doc.message,
        shortMessage: doc.shortMessage,
        evidence: doc.evidence.map(mapFromFirestoreInsightEvidence),
        recommendedAction: InsightAction(rawValue: doc.recommendedAction) ?? .noActionNeeded,
        severity: InsightSeverity(rawValue: doc.severity) ?? .neutral,
        emotionalIntent: InsightEmotionalIntent(rawValue: doc.emotionalIntent) ?? .buildConfidence,
        userValueScore: doc.userValueScore,
        confidence: doc.confidence,
        surfaces: doc.surfaces.compactMap(InsightSurface.init(rawValue:)),
        relatedExerciseType: doc.relatedExerciseType.flatMap(ExerciseType.init(rawValue:)),
        relatedGoal: doc.relatedGoal.flatMap(FitnessGoal.init(rawValue:)),
        createdAt: doc.createdAt,
        serverCreatedAt: doc.serverCreatedAt,
        sourcePolicyVersion: doc.sourcePolicyVersion,
        expiresAt: doc.expiresAt,
        dedupeKey: doc.dedupeKey,
        deletedAt: doc.deletedAt,
        syncMetadata: mapFromFirestoreSyncMetadata(
            doc.syncMetadata,
            accountId: doc.accountId,
            fallbackDate: doc.createdAt
        )
    )
}

nonisolated func mapToInsightDeliveryDocument(_ record: InsightDeliveryRecord) -> FirestoreInsightDeliveryDocument {
    FirestoreInsightDeliveryDocument(
        schemaVersion: FirestoreDTOSchema.currentVersion,
        accountId: normalizedAccountId(record.accountId),
        dedupeKey: record.dedupeKey,
        firstPresentedAt: record.firstPresentedAt,
        lastPresentedAt: record.lastPresentedAt,
        serverLastPresentedAt: nil,
        presentationCount: record.presentationCount,
        surfaceLastPresentedAt: record.surfaceLastPresentedAt,
        deletedAt: record.deletedAt,
        syncMetadata: mapToFirestoreSyncMetadata(record.syncMetadata),
        operationId: record.syncMetadata.pendingOperationId ?? UUID()
    )
}

nonisolated func mapFromInsightDeliveryDocument(_ doc: FirestoreInsightDeliveryDocument) -> InsightDeliveryRecord {
    InsightDeliveryRecord(
        accountId: doc.accountId,
        dedupeKey: doc.dedupeKey,
        firstPresentedAt: doc.firstPresentedAt,
        lastPresentedAt: doc.lastPresentedAt,
        presentationCount: doc.presentationCount,
        surfaceLastPresentedAt: doc.surfaceLastPresentedAt,
        deletedAt: doc.deletedAt,
        syncMetadata: mapFromFirestoreSyncMetadata(
            doc.syncMetadata,
            accountId: doc.accountId,
            fallbackDate: doc.lastPresentedAt
        )
    )
}

nonisolated func mapToInsightEngagementDocument(_ record: InsightEngagementRecord) -> FirestoreInsightEngagementDocument {
    let counts = Dictionary(
        uniqueKeysWithValues: InsightEngagementKind.allCases.map { ($0.rawValue, record.count(for: $0)) }
    ).filter { $0.value > 0 }
    let dates = Dictionary(
        uniqueKeysWithValues: InsightEngagementKind.allCases.compactMap { kind in
            record.lastEngagedAt(for: kind).map { (kind.rawValue, $0) }
        }
    )
    return FirestoreInsightEngagementDocument(
        schemaVersion: FirestoreDTOSchema.currentVersion,
        accountId: normalizedAccountId(record.accountId),
        dedupeKey: record.dedupeKey,
        engagementCounts: counts,
        lastEngagementDates: dates,
        serverLastEngagedAt: nil,
        deletedAt: record.deletedAt,
        syncMetadata: mapToFirestoreSyncMetadata(record.syncMetadata),
        operationId: record.syncMetadata.pendingOperationId ?? UUID()
    )
}

nonisolated func mapFromInsightEngagementDocument(_ doc: FirestoreInsightEngagementDocument) -> InsightEngagementRecord {
    InsightEngagementRecord(
        accountId: doc.accountId,
        dedupeKey: doc.dedupeKey,
        engagementCounts: doc.engagementCounts,
        lastEngagementDates: doc.lastEngagementDates,
        deletedAt: doc.deletedAt,
        syncMetadata: mapFromFirestoreSyncMetadata(
            doc.syncMetadata,
            accountId: doc.accountId,
            fallbackDate: doc.lastEngagementDates.values.max() ?? doc.deletedAt ?? Date()
        )
    )
}

nonisolated func mapToCalibrationDocument(_ record: CalibrationRecord) -> FirestoreCalibrationDocument {
    FirestoreCalibrationDocument(
        schemaVersion: FirestoreDTOSchema.currentVersion,
        accountId: normalizedAccountId(record.accountId),
        calibrationId: lowercaseUUID(record.id),
        status: record.status.rawValue,
        exerciseType: record.exerciseType.rawValue,
        targetReps: record.targetReps,
        completedReps: record.completedReps,
        startedAt: record.startedAt,
        completedAt: record.completedAt,
        serverCompletedAt: record.serverCompletedAt,
        visibilityPassed: record.visibilityPassed,
        averageFormScore: record.averageFormScore,
        notes: record.notes,
        deletedAt: record.deletedAt,
        syncMetadata: mapToFirestoreSyncMetadata(record.syncMetadata),
        operationId: record.syncMetadata.pendingOperationId ?? UUID()
    )
}

nonisolated func mapFromCalibrationDocument(_ doc: FirestoreCalibrationDocument) -> CalibrationRecord {
    CalibrationRecord(
        id: uuid(from: doc.calibrationId),
        accountId: doc.accountId,
        status: CalibrationStatus(rawValue: doc.status) ?? .notStarted,
        exerciseType: ExerciseType(rawValue: doc.exerciseType) ?? CalibrationDefaults.exerciseType,
        targetReps: doc.targetReps,
        completedReps: doc.completedReps,
        startedAt: doc.startedAt,
        completedAt: doc.completedAt,
        serverCompletedAt: doc.serverCompletedAt,
        visibilityPassed: doc.visibilityPassed,
        averageFormScore: doc.averageFormScore,
        notes: doc.notes,
        deletedAt: doc.deletedAt,
        syncMetadata: mapFromFirestoreSyncMetadata(
            doc.syncMetadata,
            accountId: doc.accountId,
            fallbackDate: doc.completedAt
        )
    )
}

nonisolated func mapToPlanDocument(
    _ plan: WorkoutPlanV2,
    accountId: String,
    active: Bool = false,
    savedAt: Date? = nil,
    deletedAt: Date? = nil,
    syncMetadata: SyncMetadata? = nil,
    operationId: UUID = UUID()
) -> FirestorePlanDocument {
    let normalized = normalizedAccountId(accountId)
    let resolvedSavedAt = savedAt ?? plan.generatedAt
    let metadata = syncMetadata ?? .initialPendingUpload(operationId: operationId, now: resolvedSavedAt)
    return FirestorePlanDocument(
        schemaVersion: FirestoreDTOSchema.currentVersion,
        accountId: normalized,
        planId: lowercaseUUID(plan.id),
        active: active,
        savedAt: resolvedSavedAt,
        title: plan.title,
        subtitle: plan.subtitle,
        goal: plan.goal,
        estimatedMinutes: plan.estimatedMinutes,
        difficulty: plan.difficulty.rawValue,
        coach: plan.coach.rawValue,
        blocks: plan.blocks.map(mapToFirestoreWorkoutBlock),
        generatedAt: plan.generatedAt,
        serverGeneratedAt: nil,
        planReason: plan.planReason,
        source: plan.source.rawValue,
        deletedAt: deletedAt,
        syncMetadata: mapToFirestoreSyncMetadata(metadata),
        operationId: operationId
    )
}

nonisolated func mapFromPlanDocument(_ doc: FirestorePlanDocument) -> WorkoutPlanV2 {
    WorkoutPlanV2(
        id: uuid(from: doc.planId),
        title: doc.title,
        subtitle: doc.subtitle,
        goal: doc.goal,
        estimatedMinutes: doc.estimatedMinutes,
        difficulty: ExerciseDifficulty(rawValue: doc.difficulty) ?? .beginner,
        coach: CoachPersonality(rawValue: doc.coach) ?? .good,
        blocks: doc.blocks.map(mapFromFirestoreWorkoutBlock),
        generatedAt: doc.generatedAt,
        planReason: doc.planReason,
        source: PlanSource(rawValue: doc.source) ?? .generatedLocal
    )
}

private nonisolated func mapToFirestoreSyncMetadata(_ metadata: SyncMetadata) -> FirestoreSyncMetadataFields {
    FirestoreSyncMetadataFields(
        localUpdatedAt: metadata.localUpdatedAt,
        lastSyncedAt: metadata.lastSyncedAt,
        serverVersion: metadata.serverVersion,
        syncState: metadata.syncState.rawValue,
        pendingOperationId: metadata.pendingOperationId.map(lowercaseUUID)
    )
}

private nonisolated func mapFromFirestoreSyncMetadata(
    _ fields: FirestoreSyncMetadataFields?,
    accountId: String,
    fallbackDate: Date
) -> SyncMetadata {
    guard let fields else {
        let hasAccount = AccountOwnership.normalizedAccountId(accountId) != nil
        return SyncMetadata(
            localUpdatedAt: fallbackDate,
            lastSyncedAt: hasAccount ? fallbackDate : nil,
            serverVersion: nil,
            syncState: hasAccount ? .synced : .localOnly,
            pendingOperationId: nil
        )
    }

    return SyncMetadata(
        localUpdatedAt: fields.localUpdatedAt,
        lastSyncedAt: fields.lastSyncedAt,
        serverVersion: fields.serverVersion,
        syncState: SyncState(rawValue: fields.syncState) ?? .synced,
        pendingOperationId: fields.pendingOperationId.flatMap(UUID.init(uuidString:))
    )
}

private nonisolated func mapToFirestoreCueEvent(_ event: CueEvent) -> FirestoreCueEventDTO {
    FirestoreCueEventDTO(
        id: lowercaseUUID(event.id),
        timestamp: event.timestamp,
        exerciseType: event.exerciseType.rawValue,
        cueMessage: event.cueMessage,
        severity: event.severity.rawValue,
        setIndex: event.setIndex,
        repIndex: event.repIndex,
        secondsIntoSet: event.secondsIntoSet,
        formScoreAtEvent: event.formScoreAtEvent,
        metricKey: event.metricKey,
        metricValue: event.metricValue
    )
}

private nonisolated func mapFromFirestoreCueEvent(_ dto: FirestoreCueEventDTO) -> CueEvent {
    CueEvent(
        id: uuid(from: dto.id),
        timestamp: dto.timestamp,
        exerciseType: ExerciseType(rawValue: dto.exerciseType) ?? .squat,
        cueMessage: dto.cueMessage,
        severity: CoachCue.Severity(rawValue: dto.severity) ?? .info,
        setIndex: dto.setIndex,
        repIndex: dto.repIndex,
        secondsIntoSet: dto.secondsIntoSet,
        formScoreAtEvent: dto.formScoreAtEvent,
        metricKey: dto.metricKey,
        metricValue: dto.metricValue
    )
}

private nonisolated func mapToFirestoreRepQualityEvent(_ event: RepQualityEvent) -> FirestoreRepQualityEventDTO {
    FirestoreRepQualityEventDTO(
        id: lowercaseUUID(event.id),
        exerciseType: event.exerciseType.rawValue,
        setIndex: event.setIndex,
        repIndex: event.repIndex,
        timestamp: event.timestamp,
        secondsIntoSet: event.secondsIntoSet,
        formScore: event.formScore,
        formGrade: event.formGrade,
        phase: event.phase,
        cueMessageNearRep: event.cueMessageNearRep,
        cueSeverityNearRep: event.cueSeverityNearRep?.rawValue,
        effortAtRep: event.effortAtRep
    )
}

private nonisolated func mapFromFirestoreRepQualityEvent(_ dto: FirestoreRepQualityEventDTO) -> RepQualityEvent {
    RepQualityEvent(
        id: uuid(from: dto.id),
        exerciseType: ExerciseType(rawValue: dto.exerciseType) ?? .squat,
        setIndex: dto.setIndex,
        repIndex: dto.repIndex,
        timestamp: dto.timestamp,
        secondsIntoSet: dto.secondsIntoSet,
        formScore: dto.formScore,
        formGrade: dto.formGrade,
        phase: dto.phase,
        cueMessageNearRep: dto.cueMessageNearRep,
        cueSeverityNearRep: dto.cueSeverityNearRep.flatMap(CoachCue.Severity.init(rawValue:)),
        effortAtRep: dto.effortAtRep
    )
}

private nonisolated func mapToFirestoreSetQualitySummary(_ summary: SetQualitySummary) -> FirestoreSetQualitySummaryDTO {
    FirestoreSetQualitySummaryDTO(
        totalScoredReps: summary.totalScoredReps,
        goodFormReps: summary.goodFormReps,
        excellentFormReps: summary.excellentFormReps,
        minFormScore: summary.minFormScore,
        maxFormScore: summary.maxFormScore,
        averageFormScore: summary.averageFormScore,
        firstHalfAverageFormScore: summary.firstHalfAverageFormScore,
        secondHalfAverageFormScore: summary.secondHalfAverageFormScore,
        breakdownRepIndex: summary.breakdownRepIndex,
        improvementRepIndex: summary.improvementRepIndex,
        highSeverityCueCount: summary.highSeverityCueCount,
        mostRepeatedCue: summary.mostRepeatedCue,
        qualityTrend: summary.qualityTrend.rawValue
    )
}

private nonisolated func mapFromFirestoreSetQualitySummary(_ dto: FirestoreSetQualitySummaryDTO) -> SetQualitySummary {
    SetQualitySummary(
        totalScoredReps: dto.totalScoredReps,
        goodFormReps: dto.goodFormReps,
        excellentFormReps: dto.excellentFormReps,
        minFormScore: dto.minFormScore,
        maxFormScore: dto.maxFormScore,
        averageFormScore: dto.averageFormScore,
        firstHalfAverageFormScore: dto.firstHalfAverageFormScore,
        secondHalfAverageFormScore: dto.secondHalfAverageFormScore,
        breakdownRepIndex: dto.breakdownRepIndex,
        improvementRepIndex: dto.improvementRepIndex,
        highSeverityCueCount: dto.highSeverityCueCount,
        mostRepeatedCue: dto.mostRepeatedCue,
        qualityTrend: SetQualityTrend(rawValue: dto.qualityTrend) ?? .unknown
    )
}

private nonisolated func mapToFirestoreStructuredEffortSummary(
    _ summary: StructuredEffortSummary
) -> FirestoreStructuredEffortSummaryDTO {
    FirestoreStructuredEffortSummaryDTO(
        averageEffort: summary.averageEffort,
        peakEffort: summary.peakEffort,
        trend: summary.trend.rawValue,
        source: summary.source.rawValue
    )
}

private nonisolated func mapFromFirestoreStructuredEffortSummary(
    _ dto: FirestoreStructuredEffortSummaryDTO
) -> StructuredEffortSummary {
    StructuredEffortSummary(
        averageEffort: dto.averageEffort,
        peakEffort: dto.peakEffort,
        trend: EffortTrend(rawValue: dto.trend) ?? .unavailable,
        source: EffortSource(rawValue: dto.source) ?? .unavailable
    )
}

private nonisolated func mapToFirestoreWorkoutTarget(_ target: WorkoutTarget) -> FirestoreWorkoutTargetDTO {
    switch target {
    case .reps(let count):
        FirestoreWorkoutTargetDTO(kind: "reps", value: count)
    case .hold(let seconds):
        FirestoreWorkoutTargetDTO(kind: "hold", value: seconds)
    case .timed(let seconds):
        FirestoreWorkoutTargetDTO(kind: "timed", value: seconds)
    case .amrap(let seconds):
        FirestoreWorkoutTargetDTO(kind: "amrap", value: seconds)
    case .open:
        FirestoreWorkoutTargetDTO(kind: "open", value: nil)
    }
}

private nonisolated func mapFromFirestoreWorkoutTarget(_ dto: FirestoreWorkoutTargetDTO) -> WorkoutTarget {
    switch dto.kind {
    case "reps":
        .reps(dto.value ?? 0)
    case "hold":
        .hold(seconds: dto.value ?? 0)
    case "timed":
        .timed(seconds: dto.value ?? 0)
    case "amrap":
        .amrap(seconds: dto.value)
    default:
        .open
    }
}

private nonisolated func mapToFirestoreTrophyProgress(_ progress: TrophyProgress) -> FirestoreTrophyProgressDTO {
    FirestoreTrophyProgressDTO(
        trophyId: progress.trophyId,
        currentValue: progress.currentValue,
        targetValue: progress.targetValue,
        earned: progress.earned,
        earnedAt: progress.earnedAt,
        lastUpdatedAt: progress.lastUpdatedAt,
        confidence: progress.confidence.rawValue,
        progressLabel: progress.progressLabel,
        accountId: normalizedAccountId(progress.accountId),
        syncMetadata: mapToFirestoreSyncMetadata(progress.syncMetadata)
    )
}

private nonisolated func mapFromFirestoreTrophyProgress(_ dto: FirestoreTrophyProgressDTO) -> TrophyProgress {
    TrophyProgress(
        trophyId: dto.trophyId,
        currentValue: dto.currentValue,
        targetValue: dto.targetValue,
        earned: dto.earned,
        earnedAt: dto.earnedAt,
        lastUpdatedAt: dto.lastUpdatedAt,
        confidence: TrophyProgressConfidence(rawValue: dto.confidence) ?? .unavailable,
        progressLabel: dto.progressLabel,
        accountId: dto.accountId,
        syncMetadata: mapFromFirestoreSyncMetadata(
            dto.syncMetadata,
            accountId: dto.accountId,
            fallbackDate: dto.lastUpdatedAt
        )
    )
}

private nonisolated func mapToFirestoreInsightEvidence(_ evidence: InsightEvidence) -> FirestoreInsightEvidenceDTO {
    FirestoreInsightEvidenceDTO(
        id: evidence.id,
        metric: evidence.metric,
        value: evidence.value,
        comparison: evidence.comparison,
        workoutId: evidence.workoutId.map(lowercaseUUID),
        exerciseType: evidence.exerciseType?.rawValue,
        setIndex: evidence.setIndex,
        repIndex: evidence.repIndex,
        signalId: evidence.signalId,
        confidence: evidence.confidence
    )
}

private nonisolated func mapFromFirestoreInsightEvidence(_ dto: FirestoreInsightEvidenceDTO) -> InsightEvidence {
    InsightEvidence(
        id: dto.id,
        metric: dto.metric,
        value: dto.value,
        comparison: dto.comparison,
        workoutId: dto.workoutId.map(uuid(from:)),
        exerciseType: dto.exerciseType.flatMap(ExerciseType.init(rawValue:)),
        setIndex: dto.setIndex,
        repIndex: dto.repIndex,
        signalId: dto.signalId,
        confidence: dto.confidence
    )
}

private nonisolated func mapToFirestoreWorkoutBlock(_ block: WorkoutBlock) -> FirestoreWorkoutBlockDTO {
    FirestoreWorkoutBlockDTO(
        title: block.title,
        type: block.type.rawValue,
        exercises: block.exercises.map { exercise in
            FirestorePlannedExerciseDTO(
                exerciseType: exercise.exerciseType.rawValue,
                sets: exercise.sets.map { set in
                    FirestorePlannedSetDTO(
                        setIndex: set.setIndex,
                        target: mapToFirestoreWorkoutTarget(set.target)
                    )
                },
                restSeconds: exercise.restSeconds,
                coachingFocus: exercise.coachingFocus,
                cameraPosition: exercise.cameraPosition.rawValue,
                allowSwap: exercise.allowSwap
            )
        }
    )
}

private nonisolated func mapFromFirestoreWorkoutBlock(_ dto: FirestoreWorkoutBlockDTO) -> WorkoutBlock {
    WorkoutBlock(
        title: dto.title,
        type: WorkoutBlockType(rawValue: dto.type) ?? .main,
        exercises: dto.exercises.map { exercise in
            PlannedExercise(
                exerciseType: ExerciseType(rawValue: exercise.exerciseType) ?? .squat,
                sets: exercise.sets.map {
                    PlannedSet(
                        setIndex: $0.setIndex,
                        target: mapFromFirestoreWorkoutTarget($0.target)
                    )
                },
                restSeconds: exercise.restSeconds,
                coachingFocus: exercise.coachingFocus,
                cameraPosition: CameraPosition(rawValue: exercise.cameraPosition) ?? .front,
                allowSwap: exercise.allowSwap
            )
        }
    )
}

private nonisolated func defaultSetDocumentId(for setSummary: ExerciseSetSummary) -> String {
    let index = setSummary.setIndex ?? 0
    return "\(setSummary.exerciseType.rawValue)-set-\(index)"
}

private nonisolated func normalizedAccountId(_ accountId: String?) -> String {
    AccountOwnership.normalizedAccountId(accountId) ?? ""
}

private nonisolated func lowercaseUUID(_ uuid: UUID) -> String {
    uuid.uuidString.lowercased()
}

private nonisolated func uuid(from string: String) -> UUID {
    UUID(uuidString: string) ?? UUID()
}
