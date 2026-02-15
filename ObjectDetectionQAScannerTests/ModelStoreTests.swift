import XCTest
@testable import ObjectDetectionQAScanner

final class ModelStoreTests: XCTestCase {
    func testResolveSourceModelKindPrefersMLPackageWhenBothExist() throws {
        let kind = try ModelStore.resolveSourceModelKind(hasMLPackage: true, hasMLModel: true)
        XCTAssertEqual(kind, .mlpackage)
    }

    func testResolveSourceModelKindFallsBackToMLModel() throws {
        let kind = try ModelStore.resolveSourceModelKind(hasMLPackage: false, hasMLModel: true)
        XCTAssertEqual(kind, .mlmodel)
    }

    func testResolveSourceModelKindThrowsWhenNeitherExists() {
        XCTAssertThrowsError(try ModelStore.resolveSourceModelKind(hasMLPackage: false, hasMLModel: false)) { error in
            guard case ModelStore.ModelStoreError.missingModelFile = error else {
                return XCTFail("Expected missingModelFile, got \(error)")
            }
        }
    }
}
