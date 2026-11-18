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
        store.send(.menuBarClick(shown: DeviceWindow.isShown))
    }

    /// 343, option C: a solid player, 18 points. The body is filled; the screen and the wheel
    /// are cut out, and the wheel's center button stays. A template image, so macOS draws it
    /// black or white and pressed.
    static let icon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let body = NSBezierPath(roundedRect: NSRect(x: 4, y: 1, width: 10, height: 16), xRadius: 2.5, yRadius: 2.5)
            body.append(NSBezierPath(roundedRect: NSRect(x: 5.5, y: 10, width: 7, height: 5.5), xRadius: 1, yRadius: 1))
            body.append(NSBezierPath(ovalIn: NSRect(x: 5.75, y: 2.5, width: 6.5, height: 6.5)))
            body.windingRule = .evenOdd
            NSColor.black.setFill()
            body.fill()
            NSBezierPath(ovalIn: NSRect(x: 7.75, y: 4.5, width: 2.5, height: 2.5)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "myPod"
        return image
    }()
}
