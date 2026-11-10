import AppKit
import SwiftUI

/// Takes the device's keys at the window level (CLA-79). SwiftUI keyboard focus needs the window
/// in front when the view appears, and a click does not give it back, so keys could beep instead.
/// Put it in the background of the device. It never takes clicks: it watches the window's key
/// events and takes only the ones that `key(for:)` knows.
struct KeyCatcher: NSViewRepresentable {
    /// Gets each key the device takes, and whether it is a held-key repeat.
    let onKey: @MainActor (KeyEquivalent, _ repeated: Bool) -> Bool

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onKey = onKey
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onKey = onKey
    }

    /// The key for a key code and its characters, or nil for a key the device does not use.
    static func key(keyCode: UInt16, characters: String?) -> KeyEquivalent? {
        switch keyCode {
        case 126: return .upArrow
        case 125: return .downArrow
        case 123: return .leftArrow
        case 124: return .rightArrow
        case 36, 76: return .return  // Return, and Enter on the keypad
        case 53: return .escape
        case 51: return .delete
        case 49: return .space
        default:
            guard let characters, characters.count == 1, let character = characters.first else { return nil }
            return KeyEquivalent(character)
        }
    }

    /// Keys with Command, Option or Control belong to the menus. Shift and Caps Lock are fine.
    static func takes(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.intersection(.deviceIndependentFlagsMask).isDisjoint(with: [.command, .option, .control])
    }

    final class CatcherView: NSView {
        var onKey: @MainActor (KeyEquivalent, Bool) -> Bool = { _, _ in false }
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }  // clicks and drags go to SwiftUI

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            // AppKit calls local monitors on the main thread.
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let taken = MainActor.assumeIsolated { self?.take(event) ?? false }
                return taken ? nil : event
            }
        }

        /// Sends the key if it is for this window and the device uses it. Returns false to pass it on.
        private func take(_ event: NSEvent) -> Bool {
            guard let window, event.window === window, KeyCatcher.takes(event.modifierFlags) else { return false }
            // A text field that is typing gets its own keys.
            if window.firstResponder is NSText { return false }
            guard let key = KeyCatcher.key(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
            else { return false }
            return onKey(key, event.isARepeat)
        }
    }
}
