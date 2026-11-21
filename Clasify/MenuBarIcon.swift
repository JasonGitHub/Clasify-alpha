import AppKit
import ClasifyCore
import ClasifySkins

/// Card AN.1 (CLA-43): the menu bar icon. A click or a right-click shows or hides myPod; there
/// is no menu and no pop-up (343, 344, 347). The reducer decides which (`.menuBarClick`), and
/// the Settings row "Menu Bar" adds or takes away the icon (346). A small AppKit wrapper,
/// because SwiftUI's `MenuBarExtra` always opens a menu or a window under the icon.
@MainActor
final class MenuBarIcon: NSObject {
    private let store: Store
    private var item: NSStatusItem?
    /// CLA-163, card CE.1: the menu bar hint's glow in the icon, while it shows.
    private var glow: MenuBarGlow?
    private var glowOn = false
    /// 388: the click that ended the hint hid myPod. The glow stays until myPod is back.
    private var keep = false
    private var unhides: NSObjectProtocol?
    /// CLA-163, card CE option F: the words under the icon, while the hint shows.
    private var words: MenuBarWordsPanel?
    private var wordsOn = false
    private var wordsWait: Task<Void, Never>?

    init(store: Store) {
        self.store = store
        super.init()
        store.send(.menuBarLabel(MenuBarHintStyle.current == .a))  // CLA-163, card CE option A
        follow()
        // myPod came back another way (the Dock, the app switcher): the kept glow ends.
        unhides = NotificationCenter.default.addObserver(forName: NSApplication.didUnhideNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.keep else { return }
                self.keep = false
                self.syncGlow()
            }
        }
    }

    /// Adds or takes away the icon each time the setting changes, and its glow with the hint.
    private func follow() {
        withObservationTracking {
            sync(on: store.state.menuBar)
            syncGlow()
            syncWords()
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
    }

    /// CLA-163, card CE.1: the icon glows while the tour's menu bar hint shows (the reducer
    /// decides when), and after the click that ended it hid myPod (388).
    private func syncGlow() {
        let on = HintsTrial.on && (store.state.hint == .tourMenuBar || keep)
        guard on != glowOn, let button = item?.button else { return }
        glowOn = on
        if !on {
            glow?.hide()  // it goes away after its fade
        } else if let glow, glow.superview === button {
            glow.show()  // a fade-out that runs turns back
        } else {
            // The glow lies over the template icon, on the icon's own place in the button.
            let box = button.bounds
            let icon = (button.cell as? NSButtonCell)?.imageRect(forBounds: box)
                ?? NSRect(x: (box.width - 18) / 2, y: (box.height - 18) / 2, width: 18, height: 18)
            let flipped = button.isFlipped ? NSRect(x: icon.minX, y: box.height - icon.maxY, width: icon.width, height: icon.height) : icon
            let view = MenuBarGlow(frame: box, icon: flipped)
            button.addSubview(view)
            view.show()
            glow = view
        }
    }

    /// CLA-163, card CE option F: the words fade in 1 s after the glow, over 0.9 s. When the
    /// hint ends or hides, they fade out over 0.45 s; a glow that the click keeps stays alone.
    private func syncWords() {
        let on = HintsTrial.on && MenuBarHintStyle.current == .f && store.state.hint == .tourMenuBar && item != nil
        guard on != wordsOn else { return }
        wordsOn = on
        wordsWait?.cancel()
        guard on else { words?.hide(); return }
        wordsWait = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard let self, self.wordsOn else { return }
            if let words = self.words, words.panel.isVisible {
                words.show()  // a fade-out that runs turns back
            } else if let icon = self.iconOnScreen {
                let words = MenuBarWordsPanel(under: icon)
                self.words = words
                words.show()
            }
        }
    }

    /// The 18 pt icon's frame on the screen.
    private var iconOnScreen: NSRect? {
        guard let button = item?.button, let window = button.window else { return nil }
        let box = button.bounds
        let icon = (button.cell as? NSButtonCell)?.imageRect(forBounds: box)
            ?? NSRect(x: (box.width - 18) / 2, y: (box.height - 18) / 2, width: 18, height: 18)
        return window.convertToScreen(button.convert(icon, to: nil))
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
            (glow, glowOn, keep) = (nil, false, false)
            wordsWait?.cancel()
            words?.panel.orderOut(nil)
            (words, wordsOn) = (nil, false)
            if DeviceWindow.isHidden { DeviceWindow.show() }  // with no icon, myPod does not stay hidden
        }
    }

    @objc private func click() {
        // Build 323: after the icon's hide, a click always shows (`iconHid`).
        let shown = !DeviceWindow.iconHid && DeviceWindow.isShown
        // CLA-163, card CE.1 (388): the first click ends the menu bar hint. When it hides
        // myPod, the glow stays until the next click brings myPod back. Later hides have none.
        keep = HintsTrial.on && store.state.tour == .tourMenuBar && shown && store.state.setupDone
        store.send(.menuBarClick(shown: shown))
        syncGlow()
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
