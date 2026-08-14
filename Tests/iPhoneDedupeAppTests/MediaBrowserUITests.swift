import AppKit
import SwiftUI
import XCTest
@testable import iPhoneDedupeApp

@MainActor
final class MediaBrowserUITests: XCTestCase {
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
}
