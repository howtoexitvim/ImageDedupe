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

    func testListContentKeepsOverflowWidthInNarrowViewport() {
        XCTAssertEqual(MediaListLayout.contentWidth(viewportWidth: 700), 820)
    }
}
