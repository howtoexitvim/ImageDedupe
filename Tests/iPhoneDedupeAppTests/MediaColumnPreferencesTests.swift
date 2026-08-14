import DeduperCore
import XCTest
@testable import iPhoneDedupeApp

/// Phase 3: column order, widths, and the sort descriptor persist locally.
///
/// Every test uses its own in-memory `UserDefaults` suite so no test can read or write
/// the real user's preferences.
final class MediaColumnPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "MediaColumnPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Defaults

    func testDefaultsMatchTheDeclaredColumnModel() {
        let store = MediaColumnPreferences(defaults: defaults)

        XCTAssertEqual(store.columnOrder, MediaTableColumn.allCases)
        for column in MediaTableColumn.allCases {
            XCTAssertEqual(store.width(for: column), column.defaultWidth)
        }
    }

    func testDefaultSortMatchesTheProductDefault() {
        let store = MediaColumnPreferences(defaults: defaults)
        XCTAssertEqual(store.sortField, .timestamp)
        XCTAssertEqual(store.sortOrder, .descending)
    }

    // MARK: - Width persistence

    func testWidthSurvivesReload() {
        let store = MediaColumnPreferences(defaults: defaults)
        store.setWidth(320, for: .name)

        let reloaded = MediaColumnPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.width(for: .name), 320)
    }

    func testWidthIsClampedToTheColumnMinimum() {
        let store = MediaColumnPreferences(defaults: defaults)
        store.setWidth(10, for: .name)

        XCTAssertEqual(store.width(for: .name), MediaTableColumn.name.minimumWidth)
    }

    func testWidthIsClampedToTheColumnMaximum() {
        let store = MediaColumnPreferences(defaults: defaults)
        store.setWidth(99_999, for: .kind)

        XCTAssertEqual(store.width(for: .kind), MediaTableColumn.kind.maximumWidth)
    }

    /// A persisted width from an older build must not be able to shrink Name into the
    /// checkbox/thumbnail geometry.
    func testCorruptPersistedWidthFallsBackToASafeValue() {
        defaults.set(["name": 4.0], forKey: "media.column.widths")
        let store = MediaColumnPreferences(defaults: defaults)

        XCTAssertEqual(store.width(for: .name), MediaTableColumn.name.minimumWidth)
    }

    func testNonFiniteWidthIsRejected() {
        let store = MediaColumnPreferences(defaults: defaults)
        store.setWidth(.nan, for: .size)

        XCTAssertEqual(store.width(for: .size), MediaTableColumn.size.defaultWidth)
    }

    // MARK: - Order persistence

    func testOrderSurvivesReload() {
        let store = MediaColumnPreferences(defaults: defaults)
        let reordered: [MediaTableColumn] = [.selection, .thumbnail, .name, .size, .kind, .timestamp, .duration]
        store.setColumnOrder(reordered)

        let reloaded = MediaColumnPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.columnOrder, reordered)
    }

    func testPersistedOrderMissingAColumnIsRepairedNotDiscarded() {
        // A build that adds a column must not lose the user's existing arrangement.
        defaults.set(["name", "kind"], forKey: "media.column.order")
        let store = MediaColumnPreferences(defaults: defaults)

        XCTAssertEqual(store.columnOrder.prefix(2).map(\.identifier), ["name", "kind"])
        XCTAssertEqual(Set(store.columnOrder), Set(MediaTableColumn.allCases))
    }

    func testPersistedOrderWithUnknownColumnIgnoresIt() {
        defaults.set(["name", "notarealcolumn", "kind"], forKey: "media.column.order")
        let store = MediaColumnPreferences(defaults: defaults)

        XCTAssertEqual(Set(store.columnOrder), Set(MediaTableColumn.allCases))
        XCTAssertEqual(store.columnOrder.prefix(2).map(\.identifier), ["name", "kind"])
    }

    func testDuplicateEntriesInPersistedOrderAreCollapsed() {
        defaults.set(["name", "name", "kind"], forKey: "media.column.order")
        let store = MediaColumnPreferences(defaults: defaults)

        XCTAssertEqual(store.columnOrder.count, MediaTableColumn.allCases.count)
        XCTAssertEqual(Set(store.columnOrder), Set(MediaTableColumn.allCases))
    }

    // MARK: - Reorder policy

    func testRowFurnitureColumnsCannotBeReordered() {
        XCTAssertFalse(MediaTableColumn.selection.isReorderable)
        XCTAssertFalse(MediaTableColumn.thumbnail.isReorderable)
    }

    func testEveryDataColumnCanBeReordered() {
        for column in MediaTableColumn.allCases where column.sortField != nil {
            XCTAssertTrue(column.isReorderable, "\(column.identifier) should be reorderable")
        }
    }

    /// Even if a persisted arrangement puts a data column first, the pinned columns still
    /// exist and the arrangement stays complete.
    func testPersistedOrderCanPlaceDataColumnsFirstWithoutLosingPinnedOnes() {
        defaults.set(["name", "kind", "selection", "thumbnail"], forKey: "media.column.order")
        let store = MediaColumnPreferences(defaults: defaults)

        XCTAssertEqual(Set(store.columnOrder), Set(MediaTableColumn.allCases))
    }

    // MARK: - Sort persistence

    func testSortDescriptorSurvivesReload() {
        let store = MediaColumnPreferences(defaults: defaults)
        store.setSort(field: .size, order: .ascending)

        let reloaded = MediaColumnPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.sortField, .size)
        XCTAssertEqual(reloaded.sortOrder, .ascending)
    }

    func testUnknownPersistedSortFieldFallsBackToDefault() {
        defaults.set("notafield", forKey: "media.sort.field")
        let store = MediaColumnPreferences(defaults: defaults)

        XCTAssertEqual(store.sortField, .timestamp)
    }

    // MARK: - Reset

    func testResetRestoresEveryDefault() {
        let store = MediaColumnPreferences(defaults: defaults)
        store.setWidth(320, for: .name)
        store.setColumnOrder([.name, .selection, .thumbnail, .kind, .timestamp, .size, .duration])
        store.setSort(field: .size, order: .ascending)

        store.reset()

        XCTAssertEqual(store.columnOrder, MediaTableColumn.allCases)
        XCTAssertEqual(store.width(for: .name), MediaTableColumn.name.defaultWidth)
        XCTAssertEqual(store.sortField, .timestamp)
        XCTAssertEqual(store.sortOrder, .descending)
    }

    func testResetIsPersistedNotJustInMemory() {
        let store = MediaColumnPreferences(defaults: defaults)
        store.setWidth(320, for: .name)
        store.reset()

        let reloaded = MediaColumnPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.width(for: .name), MediaTableColumn.name.defaultWidth)
    }
}

/// Sorting semantics the columns depend on. These guard the Phase 3 acceptance criteria
/// about natural string order and numeric size/duration order.
final class MediaColumnSortingTests: XCTestCase {
    private func file(_ name: String, size: Int64 = 0, duration: Double? = nil) -> DeviceMediaFile {
        DeviceMediaFile(
            id: name,
            name: name,
            kind: "jpg",
            size: size,
            timestamp: nil,
            width: nil,
            height: nil,
            duration: duration
        )
    }

    func testNamesSortNaturallyAroundDigitBoundaries() {
        let sorted = MediaSortDescriptor(field: .name, order: .ascending)
            .sorted([file("IMG_10.JPG"), file("IMG_9.JPG"), file("IMG_100.JPG")])

        XCTAssertEqual(sorted.map(\.name), ["IMG_9.JPG", "IMG_10.JPG", "IMG_100.JPG"])
    }

    func testNamesSortAcrossMixedScripts() {
        let sorted = MediaSortDescriptor(field: .name, order: .ascending)
            .sorted([file("照片.JPG"), file("Apple.JPG"), file("banana.JPG")])

        // Latin names sort before CJK under the standard locale-aware comparison.
        XCTAssertEqual(sorted.map(\.name).prefix(2), ["Apple.JPG", "banana.JPG"])
    }

    func testSizeSortsNumericallyAcrossPowersOfTen() {
        let sorted = MediaSortDescriptor(field: .size, order: .ascending)
            .sorted([file("a", size: 1_000_000), file("b", size: 999), file("c", size: 10_000)])

        XCTAssertEqual(sorted.map(\.size), [999, 10_000, 1_000_000])
    }

    func testDurationSortsNumericallyAcrossMinuteBoundaries() {
        let sorted = MediaSortDescriptor(field: .duration, order: .ascending)
            .sorted([file("a", duration: 61), file("b", duration: 59), file("c", duration: 600)])

        XCTAssertEqual(sorted.compactMap(\.duration), [59, 61, 600])
    }

    func testMissingDurationsSortAfterPresentOnesWhenAscending() {
        let sorted = MediaSortDescriptor(field: .duration, order: .ascending)
            .sorted([file("a", duration: nil), file("b", duration: 5)])

        XCTAssertEqual(sorted.map(\.name), ["b", "a"])
    }
}
