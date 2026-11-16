import XCTest
@testable import NotchLyricsKit

final class NotchBehaviorTests: XCTestCase {
    func testExpandedPlayerOnlyCollapsesAfterARealHoverExit() {
        XCTAssertFalse(NotchContainerView.shouldScheduleCollapse(expanded: true, hasHoveredExpanded: false, hovering: false))
        XCTAssertTrue(NotchContainerView.shouldScheduleCollapse(expanded: true, hasHoveredExpanded: true, hovering: false))
        XCTAssertFalse(NotchContainerView.shouldScheduleCollapse(expanded: true, hasHoveredExpanded: true, hovering: true))
    }

    func testCanvasIsFixed() {
        XCTAssertEqual(NotchWindowController.canvas, CGSize(width: 624, height: 320))
    }
}
