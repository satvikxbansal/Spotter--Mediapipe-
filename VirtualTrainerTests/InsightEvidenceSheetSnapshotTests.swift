import SwiftUI
import UIKit
import XCTest
@testable import VirtualTrainer

@MainActor
final class InsightEvidenceSheetSnapshotTests: XCTestCase {
    func testEvidenceSheetSnapshotRenders() throws {
        let summary = makeSummary()
        let insight = AIInsight(
            type: .formCorrection,
            headline: "Push-Up form needs protection",
            message: "Push-Up form dropped after rep 4 in set 1. Keep the next target steady and make the first cue happen before adding reps.",
            shortMessage: "Push-Up form dropped after rep 4.",
            evidence: [
                InsightEvidence(
                    metric: "formDropOff",
                    value: "after rep 4",
                    comparison: "92% to 76%",
                    workoutId: summary.id,
                    exerciseType: .pushup,
                    setIndex: 0,
                    repIndex: 4,
                    confidence: 0.9
                )
            ],
            recommendedAction: .focusCue,
            severity: .caution,
            emotionalIntent: .preventOverreach,
            userValueScore: 110,
            confidence: 0.9,
            surfaces: [.profile],
            relatedExerciseType: .pushup,
            relatedGoal: .strength,
            createdAt: summary.createdAt,
            dedupeKey: "snapshot-evidence"
        )

        let image = try renderSnapshot(insight: insight, summaries: [summary], name: "Insight-Evidence-Sheet")

        XCTAssertGreaterThan(image.pngData()?.count ?? 0, 10_000)
    }
}

private extension InsightEvidenceSheetSnapshotTests {
    static let now = Date(timeIntervalSince1970: 1_778_067_200)

    func makeSummary() -> WorkoutSessionSummary {
        let repEvents = [92, 90, 82, 76].enumerated().map { index, score in
            RepQualityEvent(
                exerciseType: .pushup,
                setIndex: 0,
                repIndex: index + 1,
                timestamp: Self.now.addingTimeInterval(Double(index + 1)),
                secondsIntoSet: Double(index + 1) * 3,
                formScore: score,
                formGrade: FormScore.Grade.from(score: score).rawValue,
                cueMessageNearRep: index == 3 ? "Stack shoulders" : nil,
                cueSeverityNearRep: index == 3 ? .warning : nil
            )
        }
        let quality = SetQualitySummary.build(repQualityEvents: repEvents)
        return WorkoutSessionSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000004444") ?? UUID(),
            mode: .plannedWorkout,
            planTitle: "Snapshot Strength",
            title: "Snapshot Strength",
            goal: "Build clean strength.",
            coach: .good,
            startedAt: Self.now.addingTimeInterval(-600),
            endedAt: Self.now,
            durationSeconds: 600,
            totalReps: 4,
            totalHoldSeconds: 0,
            averageFormScore: quality.averageFormScore,
            completionPercent: 1,
            exerciseSummaries: [
                ExerciseSetSummary(
                    exerciseType: .pushup,
                    setIndex: 0,
                    target: .reps(4),
                    achievedReps: 4,
                    achievedHoldSeconds: 0,
                    averageFormScore: quality.averageFormScore,
                    qualitySummary: quality,
                    repQualityEvents: repEvents
                )
            ],
            topCue: nil,
            effortSummary: "Controlled session.",
            createdAt: Self.now
        )
    }

    func renderSnapshot(
        insight: AIInsight,
        summaries: [WorkoutSessionSummary],
        name: String
    ) throws -> UIImage {
        let size = CGSize(width: 390, height: 844)
        let controller = UIHostingController(
            rootView: InsightEvidenceSheetView(
                insight: insight,
                summaries: summaries,
                onEngagement: { _ in }
            )
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
}
