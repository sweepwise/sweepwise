import XCTest
@testable import SweepwiseCore

final class TrashServiceTests: XCTestCase {
    var dir: URL!
    let service = TrashService()

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sweepwise-trash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testPermanentDeleteRemovesFile() throws {
        let f = dir.appendingPathComponent("gone.txt")
        try "x".write(to: f, atomically: true, encoding: .utf8)
        let outcomes = service.permanentlyDelete(paths: [f.path])
        XCTAssertTrue(outcomes[0].success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.path))
    }

    func testFailureDoesNotAbortBatch() throws {
        let good = dir.appendingPathComponent("good.txt")
        try "x".write(to: good, atomically: true, encoding: .utf8)
        let outcomes = service.permanentlyDelete(paths: ["/nonexistent/nope", good.path])
        XCTAssertFalse(outcomes[0].success)
        XCTAssertNotNil(outcomes[0].error)
        XCTAssertTrue(outcomes[1].success)
    }

    func testTrashMovesFile() throws {
        // trashItem works for files in the user's temp domain on macOS.
        let f = dir.appendingPathComponent("trashed.txt")
        try "x".write(to: f, atomically: true, encoding: .utf8)
        let outcomes = service.trash(paths: [f.path])
        XCTAssertTrue(outcomes[0].success, outcomes[0].error ?? "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.path))
    }
}
