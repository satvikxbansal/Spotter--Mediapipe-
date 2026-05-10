import Foundation

nonisolated struct DataExportResult: Equatable {
    let archiveURL: URL
    let fileNames: [String]
    let generatedAt: Date
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

nonisolated struct DataExportService {
    let container: LocalModeDataContainer
    let persistenceActor: PersistenceActor

    private let expectedFileNames = [
        "profile.json",
        "workouts.json",
        "trophies.json",
        "trophyEvents.json",
        "insights.json",
        "insightDelivery.json",
        "insightEngagement.json",
        "calibration.json",
        "theme.json",
        "schemaVersions.json",
        "README.txt"
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
        try writeJSONObject(schemaVersions(generatedAt: now), to: archiveURL.appendingPathComponent("schemaVersions.json"))
        try readmeText(generatedAt: now).write(
            to: archiveURL.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )

        return DataExportResult(
            archiveURL: archiveURL,
            fileNames: expectedFileNames,
            generatedAt: now
        )
    }

    private func waitForSourceWrites() async {
        for url in [
            container.profileURL,
            container.workoutsURL,
            container.trophiesURL,
            container.insightsURL,
            container.calibrationURL,
            container.themeURL
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

    private func schemaVersions(generatedAt: Date) -> [String: Any] {
        [
            "exportSchemaVersion": 1,
            "generatedAt": ISO8601DateFormatter().string(from: generatedAt),
            "mode": "local",
            "onboardingSchemaVersion": UserProfile.currentOnboardingSchemaVersion,
            "profileSchemaVersion": UserProfile.currentProfileSchemaVersion,
            "workoutSummarySchemaVersion": WorkoutSessionSummary.currentSchemaVersion,
            "trophyCatalogVersion": TrophyDefinitionCatalog.version,
            "insightSourcePolicyVersion": AIInsight.currentSourcePolicyVersion,
            "piiRegistrySchemaVersion": PIIRegistry.schemaVersion,
            "localWriteJournalSchemaVersion": 1,
            "privacyBoundary": "Export contains local profile, preferences, derived workout summaries, trophies, insights, calibration, theme, and sync metadata. It does not contain raw video, camera frames, face images, raw pose streams, raw biometric face data, or raw pose timelines."
        ]
    }

    private func readmeText(generatedAt: Date) -> String {
        """
        Spotter Local Data Export
        Generated: \(ISO8601DateFormatter().string(from: generatedAt))

        This folder is a human-readable local-mode export. It is meant to help users review what Spotter keeps on device before cloud accounts exist.

        Files:
        - profile.json: Local profile, training preferences, health-adjacent preference fields, account ownership placeholders, and sync metadata.
        - workouts.json: Saved workout summaries, set summaries, cue events, rep-quality events, rest behavior, derived effort summaries, tombstones, and sync metadata.
        - trophies.json: Trophy progress records.
        - trophyEvents.json: Canonical trophy unlock event records.
        - insights.json: Deterministic local coach insight records.
        - insightDelivery.json: Insight presentation and cooldown records.
        - insightEngagement.json: Lightweight opened, helpful, not-helpful, and dismissed counts.
        - calibration.json: Local calibration status and derived calibration result.
        - theme.json: Selected app theme.
        - schemaVersions.json: Export, model, and policy versions used to read this archive.

        Privacy boundary:
        This export does not include raw video, camera frames, face images, raw pose streams, raw biometric face data, raw pose timelines, or secrets.
        """
    }
}
