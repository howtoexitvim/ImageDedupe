import DeduperCore
import Foundation
import XCTest

@testable import DeviceMediaKit

/// The app builds `Dictionary(uniqueKeysWithValues:)` keyed by `model.id`, which **traps**
/// on a repeated key. So a catalog containing two files with the same id does not degrade
/// gracefully — it terminates the process.
///
/// That is the crash reported on 2026-08-15 after deleting several photos at once: a real
/// device produced two files sharing the unassigned object handle `0` and the name
/// `QVKQ5385.JPG`, giving `0-QVKQ5385.JPG` twice.
///
/// `DeviceMediaFileIdentity` handles every case it can see, but it is given one file at a
/// time. `DeviceCatalogIndex` is the only place with a view of the whole catalog, so the
/// guarantee lives there: no device quirk may be able to crash the app.
final class CatalogIdentityUniquenessTests: XCTestCase {
    private func catalogFile(id: String, name: String, handle: UInt32) -> DeviceCatalogFile {
        DeviceCatalogFile(
            model: DeviceMediaFile(
                id: id,
                name: name,
                kind: "JPG",
                size: 1_000,
                timestamp: nil,
                width: nil,
                height: nil
            ),
            token: DeviceFileToken(
                generation: UUID(),
                objectHandle: handle,
                fingerprint: DeviceFileFingerprint(
                    name: name,
                    kind: "JPG",
                    size: 1_000,
                    timestamp: nil
                )
            )
        )
    }

    /// The exact catalog that crashed the app.
    func testTwoFilesSharingAnIdBothSurviveWithDistinctIds() {
        var index = DeviceCatalogIndex()

        XCTAssertTrue(index.insert(catalogFile(id: "0-QVKQ5385.JPG", name: "QVKQ5385.JPG", handle: 0)))
        XCTAssertTrue(index.insert(catalogFile(id: "0-QVKQ5385.JPG", name: "QVKQ5385.JPG", handle: 0)))

        XCTAssertEqual(index.files.count, 2, "Neither file may be silently dropped.")
        XCTAssertEqual(
            Set(index.files.map(\.model.id)).count,
            2,
            "Duplicate ids trap Dictionary(uniqueKeysWithValues:)."
        )
    }

    /// The property the crash actually depends on, stated directly: building the dictionary
    /// the view model builds must not trap.
    func testTheCatalogCanBeKeyedByIdWithoutTrapping() {
        var index = DeviceCatalogIndex()
        for _ in 0..<5 {
            _ = index.insert(catalogFile(id: "0-SAME.JPG", name: "SAME.JPG", handle: 0))
        }

        // This is the call that crashed in `deriveVisibleItems`.
        let byID = Dictionary(uniqueKeysWithValues: index.files.map { ($0.model.id, $0) })
        XCTAssertEqual(byID.count, index.files.count)
    }

    /// Disambiguating must not disturb files that were already unique.
    func testUniqueIdsArePreservedExactly() {
        var index = DeviceCatalogIndex()
        _ = index.insert(catalogFile(id: "7-A.JPG", name: "A.JPG", handle: 7))
        _ = index.insert(catalogFile(id: "8-B.JPG", name: "B.JPG", handle: 8))

        XCTAssertEqual(index.files.map(\.model.id), ["7-A.JPG", "8-B.JPG"])
    }

    /// The existing token-level de-duplication still applies: the same token twice is one
    /// file reported twice, not two files.
    func testARepeatedTokenIsStillRejected() {
        var index = DeviceCatalogIndex()
        let file = catalogFile(id: "7-A.JPG", name: "A.JPG", handle: 7)

        XCTAssertTrue(index.insert(file))
        XCTAssertFalse(index.insert(file), "The same token is the same file.")
        XCTAssertEqual(index.files.count, 1)
    }
}
