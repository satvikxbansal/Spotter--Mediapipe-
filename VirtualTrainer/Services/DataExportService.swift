import Foundation

nonisolated struct DataExportResult: Equatable {
    let archiveURL: URL
    let fileNames: [String]
    let generatedAt: Date
    let remoteWarnings: [String]
}

enum DataExportServiceError: Error, LocalizedError {
    case unreadableLocalFile(String, String)

    var errorDescription: String? {
        switch self {
        case let .unreadableLocalFile(fileName, reason):
            return "Could not export \(fileName): \(reason)"
        }
    }
}

@MainActor
struct RemoteDataExportRepositories {
    let profile: any ProfileRepository
    let workouts: any WorkoutRepository
    let trophies: any TrophyRepository
    let insights: any InsightRepository
    let theme: any ThemeRepository
    let calibration: any CalibrationRepository
    let plans: any PlanRepository
}

nonisolated struct DataExportService {
    let container: LocalModeDataContainer
    let persistenceActor: PersistenceActor

    private let localFileNames = [
        "profile.json",
        "workouts.json",
        "trophies.json",
        "trophyEvents.json",
        "insights.json",
        "insightDelivery.json",
        "insightEngagement.json",
        "calibration.json",
        "theme.json",
        "plans.json",
        "schemaVersions.json",
        "README.txt"
    ]

    private let remoteFileNames = [
        "profile.remote.json",
        "workouts.remote.json",
        "trophies.remote.json",
        "trophyEvents.remote.json",
        "insights.remote.json",
        "insightDelivery.remote.json",
        "insightEngagement.remote.json",
        "calibration.remote.json",
        "theme.remote.json",
        "plans.remote.json"
    ]

    init(
        container: LocalModeDataContainer = LocalModeDataContainer(),
        persistenceActor: PersistenceActor = .shared
    ) {
        self.container = container
        self.persistenceActor = persistenceActor
    }

    func exportLocalData(now: Date = Date()) async throws -> DataExportResult {
        await waitForSourceWrites()
        let archiveURL = try makeArchiveDirectory(now: now)
        let fileNames = try writeLocalFiles(
            to: archiveURL,
            generatedAt: now,
            mode: .local,
            remoteWarnings: []
        )

        return DataExportResult(
            archiveURL: archiveURL,
            fileNames: fileNames,
            generatedAt: now,
            remoteWarnings: []
        )
    }

    @MainActor
    func exportLocalAndRemoteData(
        accountId: String,
        repositories: RemoteDataExportRepositories,
        now: Date = Date()
    ) async throws -> DataExportResult {
        await waitForSourceWrites()
        let archiveURL = try makeArchiveDirectory(now: now)
        let remotePayload = await remoteExportPayload(
            accountId: accountId,
            repositories: repositories
        )
        let fileNames = try writeLocalFiles(
            to: archiveURL,
            generatedAt: now,
            mode: .firebase,
            remoteWarnings: remotePayload.warnings
        )

        for fileName in remoteFileNames {
            try writeJSONObject(
                remotePayload.files[fileName] ?? [],
                to: archiveURL.appendingPathComponent(fileName)
            )
        }

        return DataExportResult(
            archiveURL: archiveURL,
            fileNames: fileNames + remoteFileNames,
            generatedAt: now,
            remoteWarnings: remotePayload.warnings
        )
    }

    private func writeLocalFiles(
        to archiveURL: URL,
        generatedAt now: Date,
        mode: BackendMode,
        remoteWarnings: [String]
    ) throws -> [String] {
        try writeJSONObject(
            normalizedJSONObject(from: container.profileURL, missingObject: ["profile": NSNull()]),
            to: archiveURL.appendingPathComponent("profile.json")
        )
        try writeJSONObject(
            normalizedJSONObject(from: container.workoutsURL, missingObject: []),
            to: archiveURL.appendingPathComponent("workouts.json")
        )
        let trophyPayload = try trophyExportPayload()
        try writeJSONObject(trophyPayload.progress, to: archiveURL.appendingPathComponent("trophies.json"))
        try writeJSONObject(trophyPayload.events, to: archiveURL.appendingPathComponent("trophyEvents.json"))

        let insightPayload = try insightExportPayload()
        try writeJSONObject(insightPayload.insights, to: archiveURL.appendingPathComponent("insights.json"))
        try writeJSONObject(insightPayload.delivery, to: archiveURL.appendingPathComponent("insightDelivery.json"))
        try writeJSONObject(insightPayload.engagement, to: archiveURL.appendingPathComponent("insightEngagement.json"))

        try writeJSONObject(
            normalizedJSONObject(from: container.calibrationURL, missingObject: ["calibration": NSNull()]),
            to: archiveURL.appendingPathComponent("calibration.json")
        )
        try writeJSONObject(
            normalizedJSONObject(from: container.themeURL, missingObject: ["theme": NSNull()]),
            to: archiveURL.appendingPathComponent("theme.json")
        )
        try writeJSONObject(
            normalizedJSONObject(from: container.plansURL, missingObject: ["schemaVersion": 1, "records": []]),
            to: archiveURL.appendingPathComponent("plans.json")
        )
        try writeJSONObject(
            schemaVersions(generatedAt: now, mode: mode, remoteWarnings: remoteWarnings),
            to: archiveURL.appendingPathComponent("schemaVersions.json")
        )
        try readmeText(generatedAt: now, mode: mode, remoteWarnings: remoteWarnings).write(
            to: archiveURL.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )

        return localFileNames
    }

    private func waitForSourceWrites() async {
        for url in [
            container.profileURL,
            container.workoutsURL,
            container.trophiesURL,
            container.insightsURL,
            container.calibrationURL,
            container.themeURL,
            container.plansURL
        ] {
            await persistenceActor.waitForWrites(to: url)
        }
    }

    private func makeArchiveDirectory(now: Date) throws -> URL {
        try FileManager.default.createDirectory(
            at: container.generatedExportCacheDirectory,
            withIntermediateDirectories: true
        )

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let folderName = "Spotter-Data-Export-\(formatter.string(from: now))-\(UUID().uuidString.prefix(8))"
        let archiveURL = container.generatedExportCacheDirectory.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: archiveURL, withIntermediateDirectories: true)
        return archiveURL
    }

    private func normalizedJSONObject(from url: URL, missingObject: Any) throws -> Any {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return missingObject
        }

        do {
            let data = try Data(contentsOf: url)
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            if JSONSerialization.isValidJSONObject(object) {
                return object
            }
            return ["value": object]
        } catch {
            throw DataExportServiceError.unreadableLocalFile(url.lastPathComponent, error.localizedDescription)
        }
    }

    private func trophyExportPayload() throws -> (progress: Any, events: Any) {
        guard FileManager.default.fileExists(atPath: container.trophiesURL.path) else {
            return ([], [])
        }

        do {
            let snapshot = try decode(TrophyProgressSnapshot.self, from: container.trophiesURL)
            return (
                try jsonObject(from: snapshot.progress),
                try jsonObject(from: snapshot.unlockEventLog)
            )
        } catch {
            throw DataExportServiceError.unreadableLocalFile(container.trophiesURL.lastPathComponent, error.localizedDescription)
        }
    }

    private func insightExportPayload() throws -> (insights: Any, delivery: Any, engagement: Any) {
        guard FileManager.default.fileExists(atPath: container.insightsURL.path) else {
            return ([], [], [])
        }

        do {
            let snapshot = try decode(PersistedInsightStoreSnapshot.self, from: container.insightsURL)
            return (
                try jsonObject(from: snapshot.recentInsights),
                try jsonObject(from: snapshot.deliveryRecords),
                try jsonObject(from: snapshot.engagementRecords)
            )
        } catch {
            throw DataExportServiceError.unreadableLocalFile(container.insightsURL.lastPathComponent, error.localizedDescription)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    private func jsonObject<T: Encodable>(from value: T) throws -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func writeJSONObject(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url, options: [.atomic])
    }

    @MainActor
    private func remoteExportPayload(
        accountId: String,
        repositories: RemoteDataExportRepositories
    ) async -> (files: [String: Any], warnings: [String]) {
        guard let uid = AccountOwnership.normalizedAccountId(accountId) else {
            let warning = "Remote export skipped because no Firebase account was available."
            return (emptyRemoteFiles(), [warning])
        }

        var files = emptyRemoteFiles()
        var warnings: [String] = []

        do {
            if let profile = try await repositories.profile.loadProfile(accountId: uid) {
                files["profile.remote.json"] = try jsonObject(from: profile)
            } else {
                files["profile.remote.json"] = ["profile": NSNull()]
            }
        } catch {
            files["profile.remote.json"] = ["profile": NSNull()]
            warnings.append("Remote profile could not be fetched.")
        }

        do {
            let compactWorkouts = try await repositories.workouts.loadRecentWorkouts(
                accountId: uid,
                limit: 80,
                since: nil
            )
            var detailedWorkouts: [WorkoutSessionSummary] = []
            for summary in compactWorkouts {
                do {
                    detailedWorkouts.append(
                        try await repositories.workouts.loadWorkout(accountId: uid, id: summary.id) ?? summary
                    )
                } catch {
                    detailedWorkouts.append(summary)
                    warnings.append("A remote workout detail could not be fetched; compact workout data was exported.")
                }
            }
            files["workouts.remote.json"] = try jsonObject(from: detailedWorkouts)
        } catch {
            files["workouts.remote.json"] = []
            warnings.append("Remote workouts could not be fetched.")
        }

        do {
            files["trophies.remote.json"] = try jsonObject(
                from: try await repositories.trophies.loadTrophyProgress(accountId: uid)
            )
        } catch {
            files["trophies.remote.json"] = []
            warnings.append("Remote trophy progress could not be fetched.")
        }

        do {
            files["trophyEvents.remote.json"] = try jsonObject(
                from: try await repositories.trophies.loadTrophyEvents(accountId: uid, since: nil)
            )
        } catch {
            files["trophyEvents.remote.json"] = []
            warnings.append("Remote trophy events could not be fetched.")
        }

        do {
            files["insights.remote.json"] = try jsonObject(
                from: try await repositories.insights.loadRecentInsights(accountId: uid, limit: 80)
            )
        } catch {
            files["insights.remote.json"] = []
            warnings.append("Remote insights could not be fetched.")
        }

        do {
            files["insightDelivery.remote.json"] = try jsonObject(
                from: try await repositories.insights.loadDeliveryRecords(accountId: uid)
            )
        } catch {
            files["insightDelivery.remote.json"] = []
            warnings.append("Remote insight delivery records could not be fetched.")
        }

        do {
            files["insightEngagement.remote.json"] = try jsonObject(
                from: try await repositories.insights.loadEngagementRecords(accountId: uid)
            )
        } catch {
            files["insightEngagement.remote.json"] = []
            warnings.append("Remote insight engagement records could not be fetched.")
        }

        do {
            if let calibration = try await repositories.calibration.loadCalibrationRecord(accountId: uid) {
                files["calibration.remote.json"] = try jsonObject(from: calibration)
            } else {
                files["calibration.remote.json"] = ["calibration": NSNull()]
            }
        } catch {
            files["calibration.remote.json"] = ["calibration": NSNull()]
            warnings.append("Remote calibration could not be fetched.")
        }

        do {
            let theme = try await repositories.theme.loadTheme(accountId: uid)
            files["theme.remote.json"] = ["selectedTheme": theme.rawValue]
        } catch {
            files["theme.remote.json"] = ["theme": NSNull()]
            warnings.append("Remote theme could not be fetched.")
        }

        do {
            files["plans.remote.json"] = try jsonObject(
                from: try await repositories.plans.loadPlanHistory(accountId: uid, limit: 50)
            )
        } catch {
            files["plans.remote.json"] = []
            warnings.append("Remote plans could not be fetched.")
        }

        return (files, Array(Set(warnings)).sorted())
    }

    private func emptyRemoteFiles() -> [String: Any] {
        Dictionary(uniqueKeysWithValues: remoteFileNames.map { ($0, []) })
    }

    private func schemaVersions(
        generatedAt: Date,
        mode: BackendMode,
        remoteWarnings: [String]
    ) -> [String: Any] {
        [
            "exportSchemaVersion": 1,
            "generatedAt": ISO8601DateFormatter().string(from: generatedAt),
            "mode": mode.rawValue,
            "onboardingSchemaVersion": UserProfile.currentOnboardingSchemaVersion,
            "profileSchemaVersion": UserProfile.currentProfileSchemaVersion,
            "workoutSummarySchemaVersion": WorkoutSessionSummary.currentSchemaVersion,
            "trophyCatalogVersion": TrophyDefinitionCatalog.version,
            "insightSourcePolicyVersion": AIInsight.currentSourcePolicyVersion,
            "piiRegistrySchemaVersion": PIIRegistry.schemaVersion,
            "localWriteJournalSchemaVersion": 1,
            "localPlanCacheSchemaVersion": 1,
            "remoteWarnings": remoteWarnings,
            "privacyBoundary": "Export contains local profile, preferences, derived workout summaries, trophies, insights, calibration, theme, and sync metadata. It does not contain raw video, camera frames, face images, raw pose streams, raw biometric face data, raw pose timelines, or raw face blendshape streams."
        ]
    }

    private func readmeText(
        generatedAt: Date,
        mode: BackendMode,
        remoteWarnings: [String]
    ) -> String {
        let remoteSection: String
        if mode == .firebase {
            let warningText = remoteWarnings.isEmpty
                ? "Remote fetch status: complete for the available Firebase account."
                : "Remote fetch notes:\n\(remoteWarnings.map { "- \($0)" }.joined(separator: "\n"))"
            remoteSection = """

            Remote files:
            Files ending in .remote.json were fetched from Firebase at export time. They are labeled separately from local files so users can compare the on-device cache with the latest server-side copies. Recent remote workouts include set evidence when the server detail document was available.

            \(warningText)
            """
        } else {
            remoteSection = """

            Remote files:
            This archive was generated in local mode, so no .remote.json files are included.
            """
        }

        return """
        Spotter Data Export
        Generated: \(ISO8601DateFormatter().string(from: generatedAt))
        Mode: \(mode.rawValue)

        This folder is a human-readable export. Local files show what Spotter keeps on this device. In Firebase mode, matching .remote.json files show the latest server-side copies the app could fetch.

        Local files:
        - profile.json: Local profile, training preferences, health-adjacent preference fields, account ownership placeholders, and sync metadata.
        - workouts.json: Saved workout summaries, set summaries, cue events, rep-quality events, rest behavior, derived effort summaries, tombstones, and sync metadata.
        - trophies.json: Trophy progress records.
        - trophyEvents.json: Canonical trophy unlock event records.
        - insights.json: Deterministic local coach insight records.
        - insightDelivery.json: Insight presentation and cooldown records.
        - insightEngagement.json: Lightweight opened, helpful, not-helpful, and dismissed counts.
        - calibration.json: Local calibration status and derived calibration result.
        - theme.json: Selected app theme.
        - plans.json: Local active-plan cache and plan history records when present.
        - schemaVersions.json: Export, model, and policy versions used to read this archive.
        \(remoteSection)

        Schema versions:
        - exportSchemaVersion: 1
        - onboardingSchemaVersion: \(UserProfile.currentOnboardingSchemaVersion)
        - profileSchemaVersion: \(UserProfile.currentProfileSchemaVersion)
        - workoutSummarySchemaVersion: \(WorkoutSessionSummary.currentSchemaVersion)
        - trophyCatalogVersion: \(TrophyDefinitionCatalog.version)
        - insightSourcePolicyVersion: \(AIInsight.currentSourcePolicyVersion)
        - piiRegistrySchemaVersion: \(PIIRegistry.schemaVersion)
        - localPlanCacheSchemaVersion: 1

        Privacy boundary:
        This export does not include raw video, camera frames, face images, raw pose streams, raw biometric face data, raw pose timelines, raw face blendshape streams, or secrets.
        """
    }
}
