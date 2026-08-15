import AppKit
import SwiftUI
import XCTest
@testable import iPhoneDedupeApp

@MainActor
final class MediaBrowserUITests: XCTestCase {
    func testMediaSurfacesHaveStableAccessibilityLabels() {
        XCTAssertEqual(MediaNativeTableView().accessibilityLabel(), "Media list")
        XCTAssertEqual(MediaNativeCollectionView().accessibilityLabel(), "Media grid")
    }

    func testSelectionCheckboxesDoNotCreateThousandsOfKeyboardTabStops() {
        let listCell = MediaCheckboxCellView(identifier: .init("selection"))
        let gridItem = MediaGridItemView()
        let gridView = gridItem.view

        let listCheckbox = firstCheckbox(in: listCell)
        let gridCheckbox = firstCheckbox(in: gridView)

        XCTAssertEqual(listCheckbox?.refusesFirstResponder, true)
        XCTAssertEqual(gridCheckbox?.refusesFirstResponder, true)
    }

    func testSearchCoordinatorPublishesNativeFieldChanges() {
        var searchText = ""
        let binding = Binding(
            get: { searchText },
            set: { searchText = $0 }
        )
        let coordinator = NativeSearchField.Coordinator(text: binding)
        let searchField = NSSearchField()
        searchField.stringValue = "kind:heic"

        coordinator.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: searchField)
        )

        XCTAssertEqual(searchText, "kind:heic")
    }

    func testListContentFillsWideViewport() {
        XCTAssertEqual(MediaListLayout.contentWidth(viewportWidth: 1_200), 1_200)
    }

    /// The List's minimum width is now the sum of its native columns, not a hard-coded
    /// 820 pt fallback. A narrow viewport scrolls horizontally instead of compressing.
    func testListContentKeepsOverflowWidthInNarrowViewport() {
        XCTAssertEqual(
            MediaListLayout.contentWidth(viewportWidth: 200),
            MediaListLayout.minimumContentWidth
        )
    }

    func testListMinimumWidthComesFromColumnsOnly() {
        XCTAssertEqual(
            MediaListLayout.minimumContentWidth,
            Double(MediaTableColumn.totalDefaultWidth)
        )
    }

    private func firstCheckbox(in view: NSView) -> NSButton? {
        if let button = view as? NSButton {
            return button
        }
        return view.subviews.lazy.compactMap(firstCheckbox(in:)).first
    }
}
