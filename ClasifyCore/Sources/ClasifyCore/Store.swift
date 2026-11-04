/// Holds all app state. Only `send` changes it, and only through `reduce`.
@MainActor
public final class Store {
    public private(set) var state: AppState
    private let env: Dependencies

    public init(state: AppState = AppState(), env: Dependencies = .live) {
        self.state = state; self.env = env
    }

    public func send(_ action: Action) { reduce(&state, action, env) }
}
