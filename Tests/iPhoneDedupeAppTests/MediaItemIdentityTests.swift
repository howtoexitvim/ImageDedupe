import DeduperCore
import Foundation
import XCTest

@testable import DeviceMediaKit

/// A media item's `id` keys the thumbnail and preview caches, so it must identify the
/// *file*, not its position in a scan.
///
/// Reported on 2026-08-15: after deleting from Grid and scanning again, tiles showed other
/// files' pictures, and the inspector disagreed with the tile. The cause was an id built as
/// "handle-index-name", where the index is the file's ordinal in the enumeration. Deleting
/// one file shifts every later file up a position, so the same photo gets a new id and — the
/// damaging half — a *different* photo inherits the old id, and with it the cached image.
final class MediaItemIdentityTests: XCTestCase {
    /// The identity must survive a neighbour being deleted.
    func testIdentityDoesNotDependOnPositionInTheCatalog() {
        let before = DeviceMediaFileIdentity.make(objectHandle: 42, name: "IMG_0001.HEIC", index: 7)
        let afterNeighbourDeleted = DeviceMediaFileIdentity.make(
            objectHandle: 42,
            name: "IMG_0001.HEIC",
            index: 6
        )

        XCTAssertEqual(
            before,
            afterNeighbourDeleted,
            "The same file moved up one position must keep its identity."
        )
    }

    /// The inverse, and the one that actually put the wrong picture on screen: the file that
    /// slides into a vacated position must not inherit the departed file's identity.
    func testADifferentFileNeverInheritsAVacatedIdentity() {
        let deleted = DeviceMediaFileIdentity.make(objectHandle: 42, name: "IMG_0001.HEIC", index: 7)
        let slidUp = DeviceMediaFileIdentity.make(objectHandle: 99, name: "IMG_0002.HEIC", index: 7)

        XCTAssertNotEqual(
            deleted,
            slidUp,
            "A different file occupying the same position must not reuse the cached image."
        )
    }

    /// Distinct files remain distinct even when the device reuses a PTP object handle for a
    /// different name, which it is free to do across catalogs.
    func testFilesWithTheSameHandleButDifferentNamesStayDistinct() {
        let first = DeviceMediaFileIdentity.make(objectHandle: 42, name: "IMG_0001.HEIC", index: 0)
        let second = DeviceMediaFileIdentity.make(objectHandle: 42, name: "IMG_0002.HEIC", index: 1)

        XCTAssertNotEqual(first, second)
    }

    /// A file with no usable name still needs a unique identity, so the index remains the
    /// last resort — but only there, where nothing better exists.
    func testUnnamedFilesStillReceiveDistinctIdentities() {
        let first = DeviceMediaFileIdentity.make(objectHandle: 0, name: nil, index: 3)
        let second = DeviceMediaFileIdentity.make(objectHandle: 0, name: nil, index: 4)

        XCTAssertNotEqual(first, second)
    }
}
