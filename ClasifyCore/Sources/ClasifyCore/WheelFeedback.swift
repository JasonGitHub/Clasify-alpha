/// Whether a wheel step moved something, so the wheel clicks and the trackpad ticks.
/// As on the original pocket players, a step that moves nothing is silent: at the top or
/// bottom of a list, and at the end of the volume bar, the scrub bar or a slider.
/// `old` is the state before the `.wheel` action, and `new` is the state after it.
public func wheelMoved(from old: AppState, to new: AppState) -> Bool {
    guard old.stack.count == new.stack.count, old.top.screen == new.top.screen else { return false }
    if new.top.screen.isList || new.top.screen == .coverFlow { return old.top.sel != new.top.sel }
    if new.top.screen == .about { return old.top.off != new.top.off }  // card BF: the page moved
    if case .license = new.top.screen { return old.top.off != new.top.off }  // change 213: the text moved
    guard new.top.screen == .now, old.nowMode == new.nowMode else { return false }
    switch new.nowMode {
    case .volume: return old.volume != new.volume
    case .scrub: return old.t != new.t
    case .shuffle: return old.shuffle != new.shuffle
    case .repeatMode: return old.repeatMode != new.repeatMode
    }
}
