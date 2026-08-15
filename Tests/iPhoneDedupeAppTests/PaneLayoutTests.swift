import XCTest
@testable import iPhoneDedupeApp

/// Phase 5: pane geometry contract and persistence.
///
/// Each test uses its own in-memory `UserDefaults` suite, so no test can read or write the
/// real user's preferences.
final class PaneLayoutTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PaneLayoutTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Declared contract

    func testPaneContractMatchesTheRoadmap() {
        XCTAssertEqual(MediaPane.sidebar.minimumWidth, 180)
        XCTAssertEqual(MediaPane.sidebar.maximumWidth, 320)
        XCTAssertEqual(MediaPane.sidebar.defaultWidth, 220)

        XCTAssertEqual(MediaPane.inspector.minimumWidth, 260)
        XCTAssertEqual(MediaPane.inspector.maximumWidth, 420)
        XCTAssertEqual(MediaPane.inspector.defaultWidth, 300)

        XCTAssertEqual(MediaPaneLayout.minimumCenterWidth, 480)
        XCTAssertEqual(MediaPaneLayout.minimumWindowWidth, 920)
    }

    /// Regression: the window minimum was a hard-coded 940 pt that had drifted out of
    /// agreement with the pane minimums. At 940 with default panes the center got only
    /// 420 pt — below its own 480 pt minimum — so the table's leading checkbox, thumbnail,
    /// and name columns were clipped with no way to scroll back to them.
    func testWindowMinimumIsDerivedFromPaneMinimums() {
        XCTAssertEqual(
            MediaPaneLayout.minimumWindowWidth,
            MediaPane.sidebar.minimumWidth
                + MediaPaneLayout.minimumCenterWidth
                + MediaPane.inspector.minimumWidth
        )
    }

    /// The center pane must never be handed less than its declared minimum once the window
    /// itself respects that minimum.
    func testCenterKeepsItsMinimumAtTheSmallestWindow() {
        let center = MediaPaneLayout.centerWidth(
            windowWidth: MediaPaneLayout.minimumWindowWidth,
            sidebarWidth: MediaPane.sidebar.minimumWidth,
            inspectorWidth: MediaPane.inspector.minimumWidth,
            isSidebarCollapsed: false,
            isInspectorCollapsed: false
        )
        XCTAssertGreaterThanOrEqual(center, MediaPaneLayout.minimumCenterWidth)
    }

    /// The declared minimums must actually fit inside the declared minimum window, or the
    /// split view can never satisfy its own constraints.
    func testMinimumPanesFitInsideTheMinimumWindow() {
        let required = MediaPane.sidebar.minimumWidth
            + MediaPaneLayout.minimumCenterWidth
            + MediaPane.inspector.minimumWidth
        XCTAssertLessThanOrEqual(required, MediaPaneLayout.minimumWindowWidth)
    }

    /// The ideal widths (220 + 480 + 300 = 1000) exceed the minimum window, which is fine:
    /// at small widths the sidebars shrink toward their own minimums rather than the center
    /// being squeezed below 480. This documents which pane yields.
    func testIdealPanesExceedTheMinimumWindowSoSidebarsYieldFirst() {
        let idealTotal = MediaPane.sidebar.defaultWidth
            + MediaPaneLayout.minimumCenterWidth
            + MediaPane.inspector.defaultWidth
        XCTAssertGreaterThan(idealTotal, MediaPaneLayout.minimumWindowWidth)

        // Shrinking both sidebars to their minimums is exactly enough for a full center.
        let recovered = (MediaPane.sidebar.defaultWidth - MediaPane.sidebar.minimumWidth)
            + (MediaPane.inspector.defaultWidth - MediaPane.inspector.minimumWidth)
        XCTAssertGreaterThanOrEqual(idealTotal - recovered, MediaPaneLayout.minimumWindowWidth)
    }

    func testCenterWidthForWindowRespectsPaneWidths() {
        let center = MediaPaneLayout.centerWidth(
            windowWidth: 1_280,
            sidebarWidth: 220,
            inspectorWidth: 300,
            isSidebarCollapsed: false,
            isInspectorCollapsed: false
        )
        XCTAssertEqual(center, 760)
    }

    func testCollapsedPanesGiveTheirWidthToTheCenter() {
        let center = MediaPaneLayout.centerWidth(
            windowWidth: 1_280,
            sidebarWidth: 220,
            inspectorWidth: 300,
            isSidebarCollapsed: true,
            isInspectorCollapsed: true
        )
        XCTAssertEqual(center, 1_280)
    }

    func testCenterWidthNeverGoesNegative() {
        let center = MediaPaneLayout.centerWidth(
            windowWidth: 300,
            sidebarWidth: 320,
            inspectorWidth: 420,
            isSidebarCollapsed: false,
            isInspectorCollapsed: false
        )
        XCTAssertGreaterThanOrEqual(center, 0)
    }

    // MARK: - Width clamping

    func testWidthIsClampedIntoThePaneRange() {
        let store = MediaPanePreferences(defaults: defaults)

        store.setWidth(10, for: .sidebar)
        XCTAssertEqual(store.width(for: .sidebar), MediaPane.sidebar.minimumWidth)

        store.setWidth(9_999, for: .sidebar)
        XCTAssertEqual(store.width(for: .sidebar), MediaPane.sidebar.maximumWidth)
    }

    func testNonFiniteWidthIsRejected() {
        let store = MediaPanePreferences(defaults: defaults)
        store.setWidth(.nan, for: .inspector)
        XCTAssertEqual(store.width(for: .inspector), MediaPane.inspector.defaultWidth)
    }

    func testCorruptPersistedWidthFallsBackIntoRange() {
        defaults.set(["sidebar": 4.0], forKey: "media.pane.widths")
        let store = MediaPanePreferences(defaults: defaults)
        XCTAssertEqual(store.width(for: .sidebar), MediaPane.sidebar.minimumWidth)
    }

    // MARK: - Persistence

    func testWidthSurvivesReload() {
        let store = MediaPanePreferences(defaults: defaults)
        store.setWidth(260, for: .sidebar)

        let reloaded = MediaPanePreferences(defaults: defaults)
        XCTAssertEqual(reloaded.width(for: .sidebar), 260)
    }

    func testCollapseStateSurvivesReload() {
        let store = MediaPanePreferences(defaults: defaults)
        store.setCollapsed(true, for: .inspector)

        let reloaded = MediaPanePreferences(defaults: defaults)
        XCTAssertTrue(reloaded.isCollapsed(.inspector))
    }

    func testPanesStartExpandedByDefault() {
        let store = MediaPanePreferences(defaults: defaults)
        XCTAssertFalse(store.isCollapsed(.sidebar))
        XCTAssertFalse(store.isCollapsed(.inspector))
    }

    func testPanesCollapseIndependently() {
        let store = MediaPanePreferences(defaults: defaults)
        store.setCollapsed(true, for: .sidebar)

        XCTAssertTrue(store.isCollapsed(.sidebar))
        XCTAssertFalse(store.isCollapsed(.inspector))
    }

    /// A collapsed pane must remember the width to restore, not reopen at the minimum.
    func testCollapsingPreservesTheRestoreWidth() {
        let store = MediaPanePreferences(defaults: defaults)
        store.setWidth(300, for: .sidebar)
        store.setCollapsed(true, for: .sidebar)

        XCTAssertEqual(store.width(for: .sidebar), 300)
    }

    // MARK: - Reset

    /// The user asked for Reset Layout to cover panes, not just List columns.
    func testResetRestoresPaneWidthsAndCollapseState() {
        let store = MediaPanePreferences(defaults: defaults)
        store.setWidth(310, for: .sidebar)
        store.setWidth(400, for: .inspector)
        store.setCollapsed(true, for: .sidebar)

        store.reset()

        XCTAssertEqual(store.width(for: .sidebar), MediaPane.sidebar.defaultWidth)
        XCTAssertEqual(store.width(for: .inspector), MediaPane.inspector.defaultWidth)
        XCTAssertFalse(store.isCollapsed(.sidebar))
    }

    func testResetIsPersistedNotJustInMemory() {
        let store = MediaPanePreferences(defaults: defaults)
        store.setWidth(310, for: .sidebar)
        store.reset()

        let reloaded = MediaPanePreferences(defaults: defaults)
        XCTAssertEqual(reloaded.width(for: .sidebar), MediaPane.sidebar.defaultWidth)
    }
}
