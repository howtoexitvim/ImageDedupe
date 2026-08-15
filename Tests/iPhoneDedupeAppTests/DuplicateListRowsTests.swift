import DeduperCore
import Foundation
import XCTest

@testable import iPhoneDedupeApp

/// Duplicates shows every copy of a group, so the List needs a header telling one group
/// from the next. This is the row model behind that: a flat sequence of header and item
/// rows, which is what `NSTableView` wants, since it addresses rows by a single index.
///
/// Keeping this pure matters because every index-based behaviour in the List — selection,
/// arrow keys, drag-selection, scroll-to-row — is built on these indices.
@MainActor
final class DuplicateListRowsTests: XCTestCase {
    private func file(id: String, name: String) -> DeviceMediaFile {
        DeviceMediaFile(
            id: id,
            name: name,
            kind: "HEIC",
            size: 1_000,
            timestamp: "2026-08-15T00:00:00.000Z",
            width: nil,
            height: nil
        )
    }

    private func groups(_ files: [DeviceMediaFile]) -> [DuplicateGrouping.Group] {
        DuplicateGrouping.groups(
            files: files,
            definition: DuplicateRuleSelection.default.definition
        )
    }

    func testEachGroupContributesAHeaderFollowedByItsMembers() {
        let rows = MediaListRow.rows(forGroups: groups([
            file(id: "a1", name: "A.HEIC"),
            file(id: "a2", name: "A.HEIC"),
            file(id: "b1", name: "B.HEIC"),
            file(id: "b2", name: "B.HEIC")
        ]))

        XCTAssertEqual(rows.count, 6, "Two groups of two: two headers plus four items.")
        guard case .header = rows[0] else { return XCTFail("Expected a header first") }
        guard case .item = rows[1] else { return XCTFail("Expected an item") }
        guard case .item = rows[2] else { return XCTFail("Expected an item") }
        guard case .header = rows[3] else { return XCTFail("Expected the next header") }
    }

    func testAHeaderNamesTheFileAndItsCopyCount() {
        let rows = MediaListRow.rows(forGroups: groups([
            file(id: "a1", name: "A.HEIC"),
            file(id: "a2", name: "A.HEIC"),
            file(id: "a3", name: "A.HEIC")
        ]))

        guard case let .header(title, groupID) = rows[0] else {
            return XCTFail("Expected a header")
        }
        XCTAssertEqual(title, "A.HEIC — 3 copies")
        // The header carries its group id so its select-all control knows what to act on.
        XCTAssertFalse(groupID.isEmpty)
    }

    /// Header rows are not selectable, so Select All and arrow keys must be able to skip
    /// them. Every index-based List behaviour depends on telling the two apart.
    func testHeaderRowsAreDistinguishableFromItemRows() {
        let rows = MediaListRow.rows(forGroups: groups([
            file(id: "a1", name: "A.HEIC"),
            file(id: "a2", name: "A.HEIC")
        ]))

        XCTAssertTrue(rows[0].isHeader)
        XCTAssertFalse(rows[1].isHeader)
        XCTAssertEqual(rows.compactMap(\.itemID), ["a1", "a2"])
    }

    /// Mapping an item id back to its row index is what scroll-to-row and focus need.
    func testAnItemsRowIndexAccountsForTheHeadersAboveIt() {
        let rows = MediaListRow.rows(forGroups: groups([
            file(id: "a1", name: "A.HEIC"),
            file(id: "a2", name: "A.HEIC"),
            file(id: "b1", name: "B.HEIC"),
            file(id: "b2", name: "B.HEIC")
        ]))

        // header, a1, a2, header, b1, b2
        XCTAssertEqual(MediaListRow.rowIndex(ofItemID: "a1", in: rows), 1)
        XCTAssertEqual(MediaListRow.rowIndex(ofItemID: "b1", in: rows), 4)
        XCTAssertNil(MediaListRow.rowIndex(ofItemID: "missing", in: rows))
    }

    func testNoGroupsProducesNoRows() {
        XCTAssertTrue(MediaListRow.rows(forGroups: []).isEmpty)
    }

    /// The mapping the List installs, checked round-trip. Getting it wrong would point a
    /// click at the row above or below the one clicked — and the row context menu contains
    /// Delete, so that would be unrecoverable.
    func testRowAndItemMappingAgreeInBothDirections() {
        let rows = MediaListRow.rows(forGroups: groups([
            file(id: "a1", name: "A.HEIC"),
            file(id: "a2", name: "A.HEIC"),
            file(id: "b1", name: "B.HEIC"),
            file(id: "b2", name: "B.HEIC")
        ]))

        for (index, row) in rows.enumerated() {
            guard let id = row.itemID else {
                XCTAssertTrue(row.isHeader, "A row is either a header or an item.")
                continue
            }
            XCTAssertEqual(
                MediaListRow.rowIndex(ofItemID: id, in: rows),
                index,
                "Row \(index) must map back to itself."
            )
        }
    }

    /// A header row yields no item, so a click or context menu on it does nothing rather
    /// than acting on a neighbouring file.
    func testAHeaderRowYieldsNoItem() {
        let rows = MediaListRow.rows(forGroups: groups([
            file(id: "a1", name: "A.HEIC"),
            file(id: "a2", name: "A.HEIC")
        ]))

        XCTAssertNil(rows[0].itemID)
    }

    /// Scrolling to the first item of a group should bring that group's header with it.
    ///
    /// The header is the same height as the keyboard reveal padding, so relying on the
    /// padding to happen to expose it landed the scroll exactly on the header's edge and
    /// fought the next adjustment — the twitchy scrolling reported on 2026-08-16. Asking
    /// for the header row explicitly is stable, and it also reads better: arrowing into a
    /// new group shows which group you have entered.
    func testScrollTargetForAGroupsFirstItemIsItsHeader() {
        let rows = MediaListRow.rows(forGroups: groups([
            file(id: "a1", name: "A.HEIC"),
            file(id: "a2", name: "A.HEIC"),
            file(id: "b1", name: "B.HEIC"),
            file(id: "b2", name: "B.HEIC")
        ]))

        // rows: 0 header, 1 a1, 2 a2, 3 header, 4 b1, 5 b2
        XCTAssertEqual(MediaListRow.scrollTargetRow(forItemID: "a1", in: rows), 0)
        XCTAssertEqual(MediaListRow.scrollTargetRow(forItemID: "b1", in: rows), 3)
    }

    /// A later member scrolls to itself; dragging its header along would jump the view
    /// backwards for no reason.
    func testScrollTargetForALaterMemberIsTheItemItself() {
        let rows = MediaListRow.rows(forGroups: groups([
            file(id: "a1", name: "A.HEIC"),
            file(id: "a2", name: "A.HEIC")
        ]))

        XCTAssertEqual(MediaListRow.scrollTargetRow(forItemID: "a2", in: rows), 2)
    }

    /// Without headers — All Media — the target is simply the item's own row.
    func testScrollTargetWithoutHeadersIsTheItemRow() {
        let rows: [MediaListRow] = [.item("x"), .item("y")]
        XCTAssertEqual(MediaListRow.scrollTargetRow(forItemID: "y", in: rows), 1)
    }

    /// Searching in Duplicates filters the files, and a group whose files all disappear
    /// must take its header with it.
    ///
    /// Reported on 2026-08-16: typing a query that matched nothing left the headers behind,
    /// so the list read "WDAW8576.JPG — 2 copies" above no rows at all. A header is a label
    /// for the rows beneath it; with none left it is a lie about what is on screen.
    func testAGroupWhoseMembersAreAllFilteredOutLosesItsHeader() {
        let allGroups = groups([
            file(id: "a1", name: "A.HEIC"),
            file(id: "a2", name: "A.HEIC"),
            file(id: "b1", name: "B.HEIC"),
            file(id: "b2", name: "B.HEIC")
        ])

        // Only B's copies survive the search.
        let rows = MediaListRow.rows(forGroups: allGroups, visibleItemIDs: ["b1", "b2"])

        XCTAssertEqual(rows.count, 3, "One header and its two surviving copies.")
        guard case let .header(title, _) = rows[0] else { return XCTFail("Expected a header") }
        XCTAssertEqual(title, "B.HEIC — 2 copies")
        XCTAssertEqual(rows.compactMap(\.itemID), ["b1", "b2"])
    }

    /// A partly-filtered group keeps its header: some of its copies are still shown.
    func testAPartlyFilteredGroupKeepsItsHeader() {
        let allGroups = groups([
            file(id: "a1", name: "A.HEIC"),
            file(id: "a2", name: "A.HEIC")
        ])

        let rows = MediaListRow.rows(forGroups: allGroups, visibleItemIDs: ["a2"])

        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows[0].isHeader)
        XCTAssertEqual(rows.compactMap(\.itemID), ["a2"])
    }

    /// A search matching nothing leaves an empty list, not a list of bare headers.
    func testFilteringEverythingOutLeavesNoRows() {
        let allGroups = groups([
            file(id: "a1", name: "A.HEIC"),
            file(id: "a2", name: "A.HEIC")
        ])

        XCTAssertTrue(MediaListRow.rows(forGroups: allGroups, visibleItemIDs: []).isEmpty)
    }
}
