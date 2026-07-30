import SwiftState
import XCTest
@testable import TomatoBar

final class TBTimerStateMachineTests: XCTestCase {
    func testStartsIdle() {
        let stateMachine = makeTBStateMachine { false }

        XCTAssertEqual(stateMachine.state, .idle)
    }

    func testStartStopStartsAndCancelsWork() {
        let stateMachine = makeTBStateMachine { false }

        stateMachine <-! .startStop
        XCTAssertEqual(stateMachine.state, .work)

        stateMachine <-! .startStop
        XCTAssertEqual(stateMachine.state, .idle)
    }

    func testCompletedWorkStartsRest() {
        let stateMachine = makeTBStateMachine { false }
        stateMachine <-! .startStop

        stateMachine <-! .timerFired

        XCTAssertEqual(stateMachine.state, .rest)
    }

    func testCompletedRestStartsNextWorkByDefault() {
        let stateMachine = makeTBStateMachine { false }
        moveToRest(stateMachine)

        stateMachine <-! .timerFired

        XCTAssertEqual(stateMachine.state, .work)
    }

    func testCompletedRestStopsWhenPreferenceIsEnabled() {
        let stateMachine = makeTBStateMachine { true }
        moveToRest(stateMachine)

        stateMachine <-! .timerFired

        XCTAssertEqual(stateMachine.state, .idle)
    }

    func testStartStopCancelsRest() {
        let stateMachine = makeTBStateMachine { false }
        moveToRest(stateMachine)

        stateMachine <-! .startStop

        XCTAssertEqual(stateMachine.state, .idle)
    }

    func testSkipRestStartsNextWork() {
        let stateMachine = makeTBStateMachine { false }
        moveToRest(stateMachine)

        stateMachine <-! .skipRest

        XCTAssertEqual(stateMachine.state, .work)
    }

    private func moveToRest(_ stateMachine: TBStateMachine) {
        stateMachine <-! .startStop
        stateMachine <-! .timerFired
        XCTAssertEqual(stateMachine.state, .rest)
    }
}
