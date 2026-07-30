import XCTest
@testable import TomatoBar

final class EnhancedPresentationTests: XCTestCase {
    func testEnhancementsStayHiddenByDefault() {
        let state = TimerPresentationPolicy.resolve(
            floatingEnabled: false,
            fullscreenBreakEnabled: false,
            status: .running,
            phase: .shortRest
        )

        XCTAssertEqual(
            state,
            EnhancedPresentationState(
                showsFloatingTimer: false,
                showsFullscreenBreak: false
            )
        )
    }

    func testFloatingTimerFollowsAnyActivePhase() {
        XCTAssertTrue(
            TimerPresentationPolicy.resolve(
                floatingEnabled: true,
                fullscreenBreakEnabled: false,
                status: .running,
                phase: .work
            ).showsFloatingTimer
        )
        XCTAssertTrue(
            TimerPresentationPolicy.resolve(
                floatingEnabled: true,
                fullscreenBreakEnabled: false,
                status: .paused,
                phase: .longRest
            ).showsFloatingTimer
        )
        XCTAssertFalse(
            TimerPresentationPolicy.resolve(
                floatingEnabled: true,
                fullscreenBreakEnabled: false,
                status: .idle,
                phase: nil
            ).showsFloatingTimer
        )
    }

    func testFullscreenPromptOnlyAppearsDuringActiveBreak() {
        XCTAssertTrue(
            TimerPresentationPolicy.resolve(
                floatingEnabled: false,
                fullscreenBreakEnabled: true,
                status: .running,
                phase: .shortRest
            ).showsFullscreenBreak
        )
        XCTAssertFalse(
            TimerPresentationPolicy.resolve(
                floatingEnabled: false,
                fullscreenBreakEnabled: true,
                status: .running,
                phase: .work
            ).showsFullscreenBreak
        )
        XCTAssertFalse(
            TimerPresentationPolicy.resolve(
                floatingEnabled: false,
                fullscreenBreakEnabled: true,
                status: .idle,
                phase: .longRest
            ).showsFullscreenBreak
        )
    }
}
