import SwiftUI

extension View {
    /// The device's keys, taken at the window level (`KeyCatcher`). CLA-202: Mac only; on iOS
    /// it does nothing.
    func catchesKeys(_ on: Bool, _ onKey: @escaping @MainActor (KeyEquivalent, _ repeated: Bool) -> Bool) -> some View {
        #if os(macOS)
        return background { if on { KeyCatcher(onKey: onKey) } }
        #else
        return self
        #endif
    }

    /// Trackpad and mouse-wheel scrolling as wheel detents (`ScrollCatcher`). CLA-202: Mac only;
    /// on iOS it does nothing.
    func catchesScroll(_ on: Bool, _ onDetent: @escaping @MainActor (Int) -> Void) -> some View {
        #if os(macOS)
        return background { if on { ScrollCatcher(onDetent: onDetent) } }
        #else
        return self
        #endif
    }
}
