import Foundation
import XCTest
@testable import iPhoneDedupeApp

final class OperationResultStoreTests: XCTestCase {
    private var directoryURL: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("iphone-dedupe-result-tests-\(UUID().uuidString)", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("history.json")
    }

    override func tearDownWithError() throws {
        if let directoryURL {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    func testPartialFailureSurvivesAStoreReload() throws {
        let store = OperationResultStore(fileURL: fileURL)
        let record = makeRecord(failedName: "IMG_0002.HEIC")

        _ = try store.append(record)
        let reloaded = OperationResultStore(fileURL: fileURL).load()

        XCTAssertEqual(reloaded.records, [record])
        XCTAssertNil(reloaded.warning)
    }

    func testSuccessOnlyResultIsNotPersisted() throws {
        let store = OperationResultStore(fileURL: fileURL)
        let record = OperationResultRecord(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1),
            kind: .importing,
            destinationPath: "/Pictures",
            requestedCount: 2,
            successfulCount: 2,
            failures: [],
            canceledFilenames: []
        )

        let records = try store.append(record)

        XCTAssertTrue(records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testHistoryKeepsNewestTwentyRecords() throws {
        let store = OperationResultStore(fileURL: fileURL, maximumRecordCount: 20)

        for index in 0..<25 {
            _ = try store.append(makeRecord(index: index, failedName: "IMG_\(index).HEIC"))
        }

        let records = store.load().records
        XCTAssertEqual(records.count, 20)
        XCTAssertEqual(records.first?.failures.first?.filename, "IMG_24.HEIC")
        XCTAssertEqual(records.last?.failures.first?.filename, "IMG_5.HEIC")
    }

    func testCorruptHistoryFailsClosedWithAWarning() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: fileURL)

        let result = OperationResultStore(fileURL: fileURL).load()

        XCTAssertTrue(result.records.isEmpty)
        XCTAssertNotNil(result.warning)
    }

    func testClearRemovesPersistedHistory() throws {
        let store = OperationResultStore(fileURL: fileURL)
        _ = try store.append(makeRecord(failedName: "IMG_0002.HEIC"))

        try store.clear()

        XCTAssertTrue(store.load().records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    private func makeRecord(index: Int = 0, failedName: String) -> OperationResultRecord {
        OperationResultRecord(
            id: UUID(),
            date: Date(timeIntervalSince1970: TimeInterval(index)),
            kind: .importing,
            destinationPath: "/Pictures",
            requestedCount: 2,
            successfulCount: 1,
            failures: [
                OperationResultRecord.Failure(filename: failedName, reason: "Device error")
            ],
            canceledFilenames: []
        )
    }
}
