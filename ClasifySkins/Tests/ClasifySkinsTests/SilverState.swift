import ClasifyCore

extension AppState {
    /// A fresh state on Silver. Black is the default since Jason's 15:33 JST 11-22 OK; the
    /// snapshot tests keep the Silver device they were drawn with.
    static var silver: AppState {
        var s = AppState()
        s.deviceColor = .silver
        return s
    }
}
