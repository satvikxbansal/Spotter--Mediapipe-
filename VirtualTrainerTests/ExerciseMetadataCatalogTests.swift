import XCTest
@testable import VirtualTrainer

final class ExerciseMetadataCatalogTests: XCTestCase {
    func testEveryExerciseTypeHasMetadata() {
        let metadataTypes = Set(ExerciseMetadataCatalog.all.map(\.exerciseType))
        let exerciseTypes = Set(ExerciseType.allCases)

        XCTAssertEqual(metadataTypes, exerciseTypes)
    }

    func testEveryMetadataExerciseExistsInExerciseLibrary() {
        for metadata in ExerciseMetadataCatalog.all {
            XCTAssertNotNil(
                metadata.exerciseType.definition,
                "\(metadata.exerciseType.rawValue) has metadata but no ExerciseLibrary definition"
            )
        }
    }

    func testPlannedExercisesDeclareRequiredEquipment() {
        for metadata in ExerciseMetadataCatalog.plannedWorkoutMetadata {
            XCTAssertFalse(
                metadata.requiredEquipment.isEmpty,
                "\(metadata.exerciseType.rawValue) is planned-workout eligible but has no required equipment"
            )
        }
    }

    func testFreeAnalysisSupportedExercisesMapToLibraryDefinitions() {
        for metadata in ExerciseMetadataCatalog.freeAnalysisMetadata {
            XCTAssertNotNil(
                ExerciseLibrary.definition(for: metadata.exerciseType.rawValue),
                "\(metadata.exerciseType.rawValue) supports free analysis but has no library definition"
            )
        }
    }
}
