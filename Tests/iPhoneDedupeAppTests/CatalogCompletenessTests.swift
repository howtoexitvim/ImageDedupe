import DeduperCore
import Foundation
import XCTest

@testable import DeviceMediaKit

/// A scan must never publish a partially enumerated catalog.
///
/// Reported on 2026-08-16: a scan returned 104 files where Image Capture showed ~3,977, and
/// a later scan returned the full count. `adoptAlreadyBrowsedDevice` publishes an already
/// open session's `mediaFiles` immediately, without waiting for
/// `deviceDidBecomeReady(withCompleteContentCatalog:)`, so whatever the framework has
/// enumerated *so far* becomes the catalog.
///
/// A short catalog is not a cosmetic problem. Duplicates is computed from it, the delete
/// plan is computed from Duplicates, and post-delete verification asks whether a file is
/// "still present" — against a catalog that may simply not list it yet.
final class CatalogCompletenessTests: XCTestCase {
    /// A published catalog carries the count it was built from, so a caller can tell a
    /// genuinely small catalog from a truncated one.
    func testSnapshotReportsTheSourceCountItWasBuiltFrom() {
        let snapshot = DeviceCatalogSnapshot(
            generation: UUID(),
            deviceName: "iPhone",
            deviceIdentityHash: nil,
            files: [],
            sourceFileCount: 3_952
        )

        XCTAssertEqual(snapshot.sourceFileCount, 3_952)
    }

    /// An empty `mediaFiles` on an open session means enumeration has not produced anything
    /// yet, which must never be published as "the device has no media".
    func testAnEmptyAdoptedCatalogIsNotConsideredComplete() {
        XCTAssertFalse(DeviceCatalogCompleteness.isPlausiblyComplete(
            sourceFileCount: 0,
            previousFileCount: 3_952
        ))
    }

    /// The case from the report: a catalog far smaller than the last one seen for this
    /// device is enumeration in progress, not a device that lost 97% of its photos.
    func testACatalogFarSmallerThanTheLastOneIsTreatedAsIncomplete() {
        XCTAssertFalse(DeviceCatalogCompleteness.isPlausiblyComplete(
            sourceFileCount: 104,
            previousFileCount: 3_952
        ))
    }

    /// Deleting files legitimately shrinks a catalog, so an ordinary reduction must still
    /// be accepted — otherwise a real delete would look like a fault.
    func testAnOrdinaryDeletionShrinkIsAccepted() {
        XCTAssertTrue(DeviceCatalogCompleteness.isPlausiblyComplete(
            sourceFileCount: 3_951,
            previousFileCount: 3_952
        ))
        // Even clearing a large batch by hand stays within the tolerance.
        XCTAssertTrue(DeviceCatalogCompleteness.isPlausiblyComplete(
            sourceFileCount: 3_000,
            previousFileCount: 3_952
        ))
    }

    /// With nothing to compare against, any non-empty catalog is accepted: a first scan has
    /// no baseline, and refusing it would make the app unusable on a fresh launch.
    func testTheFirstScanIsAcceptedWheneverItHasContent() {
        XCTAssertTrue(DeviceCatalogCompleteness.isPlausiblyComplete(
            sourceFileCount: 104,
            previousFileCount: nil
        ))
        XCTAssertFalse(DeviceCatalogCompleteness.isPlausiblyComplete(
            sourceFileCount: 0,
            previousFileCount: nil
        ))
    }

    /// A genuinely emptied device must eventually be representable, or the app could never
    /// show an empty phone.
    func testAnEmptyDeviceIsAcceptedOnceThatIsTheSteadyState() {
        // Zero is refused while a previous catalog existed...
        XCTAssertFalse(DeviceCatalogCompleteness.isPlausiblyComplete(
            sourceFileCount: 0,
            previousFileCount: 10
        ))
        // ...but the readiness callback publishes unconditionally, which is the path a
        // genuinely empty device takes. This guard only gates the adopted-cache shortcut.
        XCTAssertTrue(DeviceCatalogCompleteness.isPlausiblyComplete(
            sourceFileCount: 0,
            previousFileCount: nil,
            isFromReadinessCallback: true
        ))
    }
}
