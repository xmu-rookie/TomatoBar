import SwiftState

typealias TBStateMachine = StateMachine<TBStateMachineStates, TBStateMachineEvents>

enum TBStateMachineEvents: EventType {
    case startStop, timerFired, skipRest
}

enum TBStateMachineStates: StateType {
    case idle, work, rest
}

func makeTBStateMachine(stopAfterBreak: @escaping () -> Bool) -> TBStateMachine {
    let stateMachine = TBStateMachine(state: .idle)

    stateMachine.addRoutes(event: .startStop, transitions: [
        .idle => .work, .work => .idle, .rest => .idle,
    ])
    stateMachine.addRoutes(event: .timerFired, transitions: [.work => .rest])
    stateMachine.addRoutes(event: .timerFired, transitions: [.rest => .idle]) { _ in
        stopAfterBreak()
    }
    stateMachine.addRoutes(event: .timerFired, transitions: [.rest => .work]) { _ in
        !stopAfterBreak()
    }
    stateMachine.addRoutes(event: .skipRest, transitions: [.rest => .work])

    return stateMachine
}
