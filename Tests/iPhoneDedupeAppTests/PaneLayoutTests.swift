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
        XCTAssertEqual(MediaPaneLayout.minimumWindowWidth, 940)
    }

    /// The declared minimums must actually fit inside the declared minimum window, or the
    /// split view can never satisfy its own constraints.
    func testMinimumPanesFitInsideTheMinimumWindow() {
        let required = MediaPane.sidebar.minimumWidth
            + MediaPaneLayout.minimumCenterWidth
            + MediaPane.inspector.minimumWidth
        XCTAssertLessThanOrEqual(required, MediaPaneLayout.minimumWindowWidth)
    }

    /// The ideal widths (220 + 480 + 300 = 1000) deliberately exceed the 940 pt minimum
    /// window. At that width the center pane gives up room down toward its own minimum
    /// rather than the sidebars being squeezed, so this documents which pane yields.
    func testIdealPanesExceedTheMinimumWindowSoCenterAbsorbsTheDifference() {
        let idealTotal = MediaPane.sidebar.defaultWidth
            + MediaPaneLayout.minimumCenterWidth
            + MediaPane.inspector.defaultWidth
        XCTAssertGreaterThan(idealTotal, MediaPaneLayout.minimumWindowWidth)

        // At the minimum window with both sidebars at their ideal widths, the center still
        // has usable room, even though it is below its preferred minimum.
        let centerAtMinimumWindow = MediaPaneLayout.minimumWindowWidth
            - MediaPane.sidebar.defaultWidth
            - MediaPane.inspector.defaultWidth
        XCTAssertGreaterThan(centerAtMinimumWindow, 0)

        // And the declared minimums do fit, which is what the split view must guarantee.
        let minimumTotal = MediaPane.sidebar.minimumWidth
            + MediaPaneLayout.minimumCenterWidth
            + MediaPane.inspector.minimumWidth
        XCTAssertLessThanOrEqual(minimumTotal, MediaPaneLayout.minimumWindowWidth)
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
