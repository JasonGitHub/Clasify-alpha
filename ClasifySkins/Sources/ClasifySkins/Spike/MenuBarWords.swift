import AppKit
import SwiftUI

/// CLA-163, card CE option F (Jason 14:07 JST 11-21, a test behind `hints.menuBarStyle` F): with
/// the menu bar glow, white words centered 16 pt under the icon. The turn hint's text style:
/// 14 pt medium, tracking 0.1, a navy shadow of 8 pt at 45 % (4 in SwiftUI). No box, no arrow.
public struct MenuBarWords: View {
    public static let words = "Click here to show or hide myPod"
    public static let width: CGFloat = 320, height: CGFloat = 40
    /// From the icon's bottom edge to the words' top.
    public static let gap: CGFloat = 16

    public init() {}

    public var body: some View {
        Text(Self.words)
            .font(.system(size: 14, weight: .medium))
            .tracking(0.1)
            .foregroundStyle(.white)
            .shadow(color: Color(red: 10 / 255, green: 20 / 255, blue: 50 / 255).opacity(0.45), radius: 4, y: 1)
            .frame(width: Self.width, height: Self.height, alignment: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The words' own clear window under the menu bar icon. It takes no clicks, and it stays when
/// the icon's click hides myPod. It fades in over 0.9 s and out over 0.45 s.
@MainActor public final class MenuBarWordsPanel {
    public static let fadeIn = 0.9, fadeOut = 0.45

    public let panel: NSPanel

    /// `icon` is the 18 pt icon's frame on the screen.
    public init(under icon: NSRect) {
        let frame = Self.frame(under: icon, screens: NSScreen.screens.map(\.frame))
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true  // clicks go to what is under the words
        panel.isReleasedWhenClosed = false
        panel.canHide = false  // stays when the icon's click hides myPod
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.alphaValue = 0
        let host = NSHostingView(rootView: MenuBarWords())
        host.frame = NSRect(origin: .zero, size: frame.size)
        panel.contentView = host
    }

    /// Centered under the icon, `gap` below it, but kept on the icon's screen.
    static func frame(under icon: NSRect, screens: [NSRect]) -> NSRect {
        let size = CGSize(width: MenuBarWords.width, height: MenuBarWords.height)
        var x = icon.midX - size.width / 2
        if let screen = screens.first(where: { $0.contains(NSPoint(x: icon.midX, y: icon.midY)) }) {
            x = min(max(x, screen.minX + 8), screen.maxX - 8 - size.width)
        }
        return NSRect(x: x, y: icon.minY - MenuBarWords.gap - size.height, width: size.width, height: size.height)
    }

    public func show() {
        panel.orderFrontRegardless()
        fade(to: 1, duration: Self.fadeIn, timing: .easeOut)
    }

    /// Fades out, then the window goes away.
    public func hide() {
        fade(to: 0, duration: Self.fadeOut, timing: .easeInEaseOut) { [weak self] in
            guard let self, self.panel.alphaValue == 0 else { return }  // not if it showed again
            self.panel.orderOut(nil)
        }
    }

    private func fade(to alpha: CGFloat, duration: Double, timing: CAMediaTimingFunctionName, then done: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: timing)
            panel.animator().alphaValue = alpha
        }
        guard let done else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            done()
        }
    }
}
