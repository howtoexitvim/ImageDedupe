import Foundation
import DeviceMediaKit
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

    func testSuccessfulDeleteAuditIsPersistedAndCanBeUpdatedAfterVerification() throws {
        let store = OperationResultStore(fileURL: fileURL)
        let planned = DeletePlanSnapshot.Item(
            token: .fixture(name: "IMG_0001.HEIC"),
            filename: "IMG_0001.HEIC",
            kind: "HEIC",
            size: 100
        )
        let snapshot = DeletePlanSnapshot(
            date: Date(timeIntervalSince1970: 1_786_780_800),
            deviceName: "iPhone",
            items: [planned]
        )
        let pendingAudit = DeleteReconciler.unverified(snapshot: snapshot, reason: "Verification pending")
        let pending = OperationResultRecord(
            id: snapshot.id,
            date: snapshot.date,
            kind: .deleting,
            destinationPath: nil,
            requestedCount: 1,
            successfulCount: 0,
            failures: [],
            canceledFilenames: [],
            deleteAudit: pendingAudit
        )
        _ = try store.append(pending)

        let verifiedAudit = DeleteReconciler.reconcile(
            snapshot: snapshot,
            summary: DeviceGatewayDeleteSummary(successful: [planned.token]),
            catalog: DeviceCatalogSnapshot(generation: UUID(), deviceName: "iPhone", files: []),
            date: Date(timeIntervalSince1970: 1_786_780_801)
        )
        let verified = OperationResultRecord(
            id: snapshot.id,
            date: snapshot.date,
            kind: .deleting,
            destinationPath: nil,
            requestedCount: 1,
            successfulCount: 1,
            failures: [],
            canceledFilenames: [],
            deleteAudit: verifiedAudit
        )
        let records = try store.append(verified)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.deleteAudit?.verificationState, .verified)
        XCTAssertEqual(records.first?.deleteAudit?.items.first?.outcome, .confirmedRemoved)
        XCTAssertEqual(OperationResultStore(fileURL: fileURL).load().records, records)
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

    func testPendingDeleteAuditCannotBeEvictedByHistoryLimit() throws {
        let store = OperationResultStore(fileURL: fileURL, maximumRecordCount: 2)
        let pending = makePendingDeleteRecord()
        _ = try store.append(pending)
        _ = try store.append(makeRecord(index: 1, failedName: "A.HEIC"))
        _ = try store.append(makeRecord(index: 2, failedName: "B.HEIC"))

        let records = store.load().records

        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.contains { $0.id == pending.id })
        XCTAssertTrue(records.contains { $0.failures.first?.filename == "B.HEIC" })
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

    func testClearRetainsPendingDeleteAuditButRemovesResolvedHistory() throws {
        let store = OperationResultStore(fileURL: fileURL)
        let pending = makePendingDeleteRecord()
        _ = try store.append(makeRecord(failedName: "IMG_0002.HEIC"))
        _ = try store.append(pending)

        try store.clear()

        XCTAssertEqual(store.load().records.map(\.id), [pending.id])
    }

    func testSavedIssueHistoryIsPrivateToTheCurrentUser() throws {
        let store = OperationResultStore(fileURL: fileURL)

        _ = try store.append(makeRecord(failedName: "IMG_0002.HEIC"))

        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directoryURL.path)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testLoadingLegacyHistoryMigratesItsPermissionsBeforeReading() throws {
        let store = OperationResultStore(fileURL: fileURL)
        _ = try store.append(makeRecord(failedName: "IMG_0002.HEIC"))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: directoryURL.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: fileURL.path
        )

        let result = store.load()

        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directoryURL.path)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertNil(result.warning)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
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

    private func makePendingDeleteRecord() -> OperationResultRecord {
        let planned = DeletePlanSnapshot.Item(
            token: .fixture(name: "PENDING.HEIC"),
            filename: "PENDING.HEIC",
            kind: "HEIC",
            size: 100
        )
        let snapshot = DeletePlanSnapshot(
            date: Date(timeIntervalSince1970: 100),
            deviceName: "iPhone",
            items: [planned]
        )
        return OperationResultRecord(
            id: snapshot.id,
            date: snapshot.date,
            kind: .deleting,
            destinationPath: nil,
            requestedCount: 1,
            successfulCount: 0,
            failures: [],
            canceledFilenames: [],
            deleteAudit: DeleteReconciler.unverified(snapshot: snapshot, reason: "Pending")
        )
    }
}
