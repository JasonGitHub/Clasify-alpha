import AppKit
import ClasifyCore

/// Card AN.1 (CLA-43): the menu bar icon. A click or a right-click shows or hides myPod; there
/// is no menu and no pop-up (343, 344, 347). The reducer decides which (`.menuBarClick`), and
/// the Settings row "Menu Bar" adds or takes away the icon (346). A small AppKit wrapper,
/// because SwiftUI's `MenuBarExtra` always opens a menu or a window under the icon.
@MainActor
final class MenuBarIcon: NSObject {
    private let store: Store
    private var item: NSStatusItem?

    init(store: Store) {
        self.store = store
        super.init()
        follow()
    }

    /// Adds or takes away the icon each time the setting changes.
    private func follow() {
        withObservationTracking { sync(on: store.state.menuBar) } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
    }

    private func sync(on: Bool) {
        if on, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = Self.icon
            item.button?.setAccessibilityLabel("myPod")
            item.button?.target = self
            item.button?.action = #selector(click)
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])  // 347: a right-click is a click
            self.item = item
        } else if !on, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
            if DeviceWindow.isHidden { DeviceWindow.show() }  // with no icon, myPod does not stay hidden
        }
    }

    @objc private func click() {
        // Build 323: after the icon's hide, a click always shows (`iconHid`).
        let shown = !DeviceWindow.iconHid && DeviceWindow.isShown
        let before = DeviceWindow.debugState
        store.send(.menuBarClick(shown: shown))
        debug(before: before, decision: shown && store.state.setupDone ? "hide" : "show")
    }

    /// Build 323 debug read-out, off by default. `defaults write com.cappyai.mypod debug.menuBar
    /// -bool true` turns it on: each click writes the state before, the decision, and 0.4 s
    /// later the state after, next to the icon, for a screen recording. Nothing is stored.
    private var clicks = 0
    private func debug(before: String, decision: String) {
        guard let item, let button = item.button else { return }
        guard UserDefaults.standard.bool(forKey: "debug.menuBar") else {
            if !button.title.isEmpty {
                button.title = ""
                item.length = NSStatusItem.squareLength
            }
            return
        }
        clicks += 1
        let line = "\(clicks) \(before) >\(decision)"
        item.length = NSStatusItem.variableLength
        button.imagePosition = .imageLeft
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        button.title = line
        let click = clicks
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.4))
            guard let self, self.clicks == click, let button = self.item?.button else { return }
            button.title = line + " | " + DeviceWindow.debugState
        }
    }

    /// 343, option C: a solid player, 18 points. The body is filled; the screen and the wheel
    /// are cut out, and the wheel's center button stays. A template image, so macOS draws it
    /// black or white and pressed.
    static let icon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let body = NSBezierPath(roundedRect: NSRect(x: 3.6, y: 1, width: 10.8, height: 16), xRadius: 2.4, yRadius: 2.4)
            body.append(NSBezierPath(roundedRect: NSRect(x: 5.4, y: 10.1, width: 7.2, height: 5), xRadius: 0.7, yRadius: 0.7))
            body.append(NSBezierPath(ovalIn: NSRect(x: 6.1, y: 2.5, width: 5.8, height: 5.8)))
            body.windingRule = .evenOdd
            NSColor.black.setFill()
            body.fill()
            NSBezierPath(ovalIn: NSRect(x: 8, y: 4.4, width: 2, height: 2)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "myPod"
        return image
    }()
}
