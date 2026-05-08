import SwiftUI
import UIKit
import XCTest
@testable import VirtualTrainer

@MainActor
final class WorkoutDetailEvidenceModelTests: XCTestCase {
    func testFadedSetEvidenceSurfacesSparklineBreakdownCueAndRestRationale() throws {
        let summary = makeFadedSummary()
        let model = WorkoutDetailEvidenceModel(summary: summary)

        let setEvidence = try XCTUnwrap(model.setEvidence.first)
        XCTAssertEqual(setEvidence.formSamples.map(\.score), [94, 93, 91, 88, 76, 72])
        XCTAssertEqual(setEvidence.totalScoredReps, 6)
        XCTAssertEqual(setEvidence.goodFormReps, 4)
        XCTAssertEqual(setEvidence.excellentFormReps, 3)
        XCTAssertEqual(setEvidence.breakdownRepIndex, 5)
        XCTAssertEqual(setEvidence.qualityTrend, .faded)
        XCTAssertEqual(setEvidence.topCue, "Keep your chest up")
        XCTAssertEqual(setEvidence.worstCue, "Chest dropped late")
        XCTAssertEqual(setEvidence.bestCue, "Depth stayed strong early")
        XCTAssertEqual(setEvidence.restIndicators.map(\.rationale), ["Rest extended after this set."])
    }

    func testMissingFormScoresAreDroppedFromSparklineButRemainInTimeline() throws {
        let now = Self.now
        let repEvents = [
            makeRep(score: 91, repIndex: 1, timestamp: now.addingTimeInterval(1)),
            makeRep(score: nil, repIndex: 2, timestamp: now.addingTimeInterval(2)),
            makeRep(score: 87, repIndex: 3, timestamp: now.addingTimeInterval(3))
        ]
        let set = makeSet(repEvents: repEvents)
        let summary = makeSummary(sets: [set], startedAt: now)

        let model = WorkoutDetailEvidenceModel(summary: summary)
        let setEvidence = try XCTUnwrap(model.setEvidence.first)

        XCTAssertEqual(setEvidence.formSamples.map(\.repIndex), [1, 3])
        XCTAssertEqual(model.timelineEvents.filter { event in
            if case .repQuality = event.kind { return true }
            return false
        }.count, 3)
    }

    func testNoRepEventsBuildsCleanSetEvidenceWithoutSparkline() throws {
        let set = makeSet(repEvents: [], qualitySummary: nil)
        let summary = makeSummary(sets: [set])

        let model = WorkoutDetailEvidenceModel(summary: summary)
        let setEvidence = try XCTUnwrap(model.setEvidence.first)

        XCTAssertFalse(setEvidence.hasRepEvidence)
        XCTAssertTrue(setEvidence.formSamples.isEmpty)
        XCTAssertEqual(setEvidence.totalScoredReps, 0)
        XCTAssertNil(setEvidence.breakdownRepIndex)
        XCTAssertTrue(model.timelineEvents.isEmpty)
    }

    func testTimelineOrdersCueAndRepQualityEventsChronologically() {
        let now = Self.now
        let cue = CueEvent(
            timestamp: now.addingTimeInterval(2),
            exerciseType: .squat,
            cueMessage: "Brace your ribs",
            severity: .warning,
            setIndex: 0,
            repIndex: 1,
            secondsIntoSet: 2,
            formScoreAtEvent: 82
        )
        let rep = makeRep(score: 92, repIndex: 1, timestamp: now.addingTimeInterval(1))
        let set = makeSet(repEvents: [rep], cueEvents: [cue])
        let summary = makeSummary(sets: [set], startedAt: now)

        let model = WorkoutDetailEvidenceModel(summary: summary)

        XCTAssertEqual(model.timelineEvents.map(\.title), ["Rep 1 completed", "Brace your ribs"])
    }

    func testCleanDetailSheetPreviewSnapshotRenders() throws {
        let image = try renderSnapshot(summary: makeCleanSummary(), name: "WorkoutDetail-Clean-Preview")

        XCTAssertGreaterThan(image.pngData()?.count ?? 0, 10_000)
    }

    func testFadedDetailSheetPreviewSnapshotRenders() throws {
        let image = try renderSnapshot(summary: makeFadedSummary(), name: "WorkoutDetail-Faded-Preview")

        XCTAssertGreaterThan(image.pngData()?.count ?? 0, 10_000)
    }
}

private extension WorkoutDetailEvidenceModelTests {
    static let now = Date(timeIntervalSince1970: 1_777_100_000)

    func makeCleanSummary() -> WorkoutSessionSummary {
        let repEvents = [92, 93, 94, 95, 96].enumerated().map { index, score in
            makeRep(
                score: score,
                repIndex: index + 1,
                timestamp: Self.now.addingTimeInterval(TimeInterval(index + 1))
            )
        }
        let quality = SetQualitySummary.build(repQualityEvents: repEvents)
        let set = makeSet(
            exerciseType: .pushup,
            repEvents: repEvents,
            qualitySummary: quality,
            bestCue: "Core stayed braced"
        )

        return makeSummary(
            title: "Clean Push-Up Session",
            sets: [set],
            averageFormScore: quality.averageFormScore,
            startedAt: Self.now.addingTimeInterval(-300)
        )
    }

    func makeFadedSummary() -> WorkoutSessionSummary {
        let repEvents = [94, 93, 91, 88, 76, 72].enumerated().map { index, score in
            makeRep(
                score: score,
                repIndex: index + 1,
                timestamp: Self.now.addingTimeInterval(TimeInterval(index + 1) * 8),
                cueMessageNearRep: index >= 3 ? "Keep your chest up" : nil
            )
        }
        let cue = CueEvent(
            timestamp: Self.now.addingTimeInterval(42),
            exerciseType: .squat,
            cueMessage: "Keep your chest up",
            severity: .warning,
            setIndex: 0,
            repIndex: 5,
            secondsIntoSet: 42,
            formScoreAtEvent: 76
        )
        let quality = SetQualitySummary.build(
            repQualityEvents: repEvents,
            cueEvents: [cue]
        )
        let set = makeSet(
            exerciseType: .squat,
            repEvents: repEvents,
            cueEvents: [cue],
            restExtended: true,
            qualitySummary: quality,
            bestCue: "Depth stayed strong early",
            worstCue: "Chest dropped late"
        )

        return makeSummary(
            title: "Faded Squat Session",
            sets: [set],
            topCue: cue,
            averageFormScore: quality.averageFormScore,
            effortSummary: "Peak effort hit 84%. High strain captured near the end.",
            startedAt: Self.now.addingTimeInterval(-360)
        )
    }

    func makeSummary(
        title: String = "Evidence Session",
        sets: [ExerciseSetSummary],
        topCue: CueEvent? = nil,
        averageFormScore: Double? = nil,
        effortSummary: String = "Peak effort reached 52%. Solid working intensity.",
        startedAt: Date? = nil
    ) -> WorkoutSessionSummary {
        let resolvedStartedAt = startedAt ?? Self.now.addingTimeInterval(-120)
        return WorkoutSessionSummary(
            mode: .plannedWorkout,
            planId: UUID(uuidString: "00000000-0000-0000-0000-000000000301"),
            title: title,
            goal: "Build clean strength.",
            coach: .good,
            startedAt: resolvedStartedAt,
            endedAt: Self.now.addingTimeInterval(120),
            durationSeconds: Int(Self.now.addingTimeInterval(120).timeIntervalSince(resolvedStartedAt)),
            totalReps: sets.reduce(0) { $0 + $1.achievedReps },
            totalHoldSeconds: sets.reduce(0) { $0 + $1.achievedHoldSeconds },
            averageFormScore: averageFormScore,
            completionPercent: 1,
            exerciseSummaries: sets,
            topCue: topCue,
            effortSummary: effortSummary,
            createdAt: Self.now
        )
    }

    func makeSet(
        exerciseType: ExerciseType = .squat,
        repEvents: [RepQualityEvent],
        cueEvents: [CueEvent] = [],
        restExtended: Bool = false,
        qualitySummary: SetQualitySummary? = nil,
        bestCue: String? = nil,
        worstCue: String? = nil
    ) -> ExerciseSetSummary {
        ExerciseSetSummary(
            exerciseType: exerciseType,
            setIndex: 0,
            target: .reps(max(repEvents.count, 1)),
            achievedReps: repEvents.count,
            achievedHoldSeconds: 0,
            averageFormScore: qualitySummary?.averageFormScore,
            cueEvents: cueEvents,
            restExtended: restExtended,
            qualitySummary: qualitySummary,
            repQualityEvents: repEvents,
            completedAt: Self.now,
            durationSeconds: 90,
            peakEffort: 0.62,
            bestCue: bestCue,
            worstCue: worstCue
        )
    }

    func makeRep(
        score: Int?,
        repIndex: Int,
        timestamp: Date,
        cueMessageNearRep: String? = nil
    ) -> RepQualityEvent {
        RepQualityEvent(
            exerciseType: .squat,
            setIndex: 0,
            repIndex: repIndex,
            timestamp: timestamp,
            secondsIntoSet: TimeInterval(repIndex * 8),
            formScore: score,
            formGrade: score.map { FormScore.Grade.from(score: $0).rawValue },
            cueMessageNearRep: cueMessageNearRep,
            cueSeverityNearRep: cueMessageNearRep == nil ? nil : .warning,
            effortAtRep: 0.45 + Double(repIndex) * 0.04
        )
    }

    func renderSnapshot(summary: WorkoutSessionSummary, name: String) throws -> UIImage {
        let size = CGSize(width: 390, height: 844)
        let historyStore = WorkoutHistoryStore(fileURL: temporaryHistoryURL())
        _ = historyStore.addSummary(summary)
        let controller = UIHostingController(
            rootView: WorkoutDetailSheetView(summary: summary)
                .environmentObject(CalibrationStore(fileURL: temporaryCalibrationURL()))
                .environmentObject(historyStore)
                .environmentObject(TrophyStore(fileURL: temporaryTrophyURL()))
                .environmentObject(InsightStore(fileURL: temporaryInsightURL()))
        )
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()

        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        window.isHidden = true
        return image
    }

    func temporaryHistoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("WorkoutHistory.json")
    }

    func temporaryCalibrationURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("CalibrationRecord.json")
    }

    func temporaryTrophyURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("TrophyProgress.json")
    }

    func temporaryInsightURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("CoachInsights.json")
    }
}
