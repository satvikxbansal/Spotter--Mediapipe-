import Foundation

nonisolated enum FirestorePathBuilder {
    static func users(_ uid: String) throws -> String {
        "users/\(try pathComponent(uid, label: "uid"))"
    }

    static func profileDocument(uid: String) throws -> String {
        "\(try users(uid))/profile/current"
    }

    static func workoutDocument(uid: String, workoutId: String) throws -> String {
        "\(try users(uid))/workouts/\(try pathComponent(workoutId, label: "workoutId"))"
    }

    static func workoutDocument(uid: String, workoutId: UUID) throws -> String {
        try workoutDocument(uid: uid, workoutId: workoutId.uuidString.lowercased())
    }

    static func workoutsCollection(uid: String) throws -> String {
        "\(try users(uid))/workouts"
    }

    static func setsCollection(uid: String, workoutId: String) throws -> String {
        "\(try workoutDocument(uid: uid, workoutId: workoutId))/sets"
    }

    static func setsCollection(uid: String, workoutId: UUID) throws -> String {
        try setsCollection(uid: uid, workoutId: workoutId.uuidString.lowercased())
    }

    static func setDocument(uid: String, workoutId: String, setId: String) throws -> String {
        "\(try workoutDocument(uid: uid, workoutId: workoutId))/sets/\(try pathComponent(setId, label: "setId"))"
    }

    static func setDocument(uid: String, workoutId: UUID, setId: String) throws -> String {
        try setDocument(uid: uid, workoutId: workoutId.uuidString.lowercased(), setId: setId)
    }

    static func trophyEvent(uid: String, eventId: String) throws -> String {
        "\(try users(uid))/trophyEvents/\(try pathComponent(eventId, label: "eventId"))"
    }

    static func trophyEventsCollection(uid: String) throws -> String {
        "\(try users(uid))/trophyEvents"
    }

    static func trophyEvent(uid: String, eventId: UUID) throws -> String {
        try trophyEvent(uid: uid, eventId: eventId.uuidString.lowercased())
    }

    static func trophyProgressCache(uid: String) throws -> String {
        "\(try users(uid))/trophyProgress/current"
    }

    static func insight(uid: String, dedupeKey: String) throws -> String {
        "\(try users(uid))/insights/\(try pathComponent(dedupeKey, label: "dedupeKey"))"
    }

    static func insightsCollection(uid: String) throws -> String {
        "\(try users(uid))/insights"
    }

    static func insightDelivery(uid: String, dedupeKey: String) throws -> String {
        "\(try users(uid))/insightDelivery/\(try pathComponent(dedupeKey, label: "dedupeKey"))"
    }

    static func insightDeliveryCollection(uid: String) throws -> String {
        "\(try users(uid))/insightDelivery"
    }

    static func insightEngagement(uid: String, dedupeKey: String) throws -> String {
        "\(try users(uid))/insightEngagement/\(try pathComponent(dedupeKey, label: "dedupeKey"))"
    }

    static func insightEngagementCollection(uid: String) throws -> String {
        "\(try users(uid))/insightEngagement"
    }

    static func calibration(uid: String) throws -> String {
        "\(try users(uid))/calibration/status"
    }

    static func plan(uid: String, planId: String) throws -> String {
        "\(try users(uid))/plans/\(try pathComponent(planId, label: "planId"))"
    }

    static func plan(uid: String, planId: UUID) throws -> String {
        try plan(uid: uid, planId: planId.uuidString.lowercased())
    }

    static func plansCollection(uid: String) throws -> String {
        "\(try users(uid))/plans"
    }

    private static func pathComponent(_ value: String, label: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RepositoryError.invalidPayload("\(label) must not be empty.")
        }
        guard trimmed != "." && trimmed != ".." && !trimmed.contains("/") else {
            throw RepositoryError.invalidPayload("\(label) contains an invalid path component.")
        }
        return trimmed
    }
}
