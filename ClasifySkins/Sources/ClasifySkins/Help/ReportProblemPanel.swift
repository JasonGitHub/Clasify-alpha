import AppKit
import SwiftUI

/// CLA-166, card CG: the Report a Problem window, an AppKit window round `ReportProblem`. The
/// SwiftUI `Window` scene with a hidden title bar made the window taller than the view: it
/// added the title bar's height under the Cancel and Send row (Jason's build 382). Here the
/// window is exactly the view: 380 x 262, then 380 x 246 on Thanks. macOS draws its close and
/// minimize buttons over the device title bar's left end.
@MainActor
public enum ReportProblemPanel {
    /// A new window, not shown yet. It closes itself on Cancel and Done.
    public static func make(onSend: @escaping (String, Bool) -> Void) -> NSWindow {
        let window = TopFixedWindow(contentRect: NSRect(x: 0, y: 0, width: ReportProblem.width, height: ReportProblem.formHeight),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        let content = ReportProblem(onSend: onSend, onClose: { [weak window] in window?.close() })
        configure(window, content)
        return window
    }

    /// The snapshot tests use it with a fixed text, screen and time.
    static func configure(_ window: NSWindow, _ content: some View) {
        window.title = ReportProblem.title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        let host = FittingHost(rootView: AnyView(content))
        // No safe area: the view starts at the window's top, under the transparent title bar,
        // so the window's size is the view's size and nothing more.
        host.safeAreaRegions = []
        host.sizingOptions = [.minSize, .intrinsicContentSize, .maxSize]
        window.contentView = host
        window.setContentSize(host.fittingSize)
    }
}

/// When the form turns into Thanks (262 to 246 pt), the top edge stays still and the bottom
/// moves up. AppKit keeps the bottom-left corner when the content's size changes; a move keeps
/// its size and is left as it is.
final class TopFixedWindow: NSWindow {
    override func setFrame(_ frameRect: NSRect, display flag: Bool) { super.setFrame(topFixed(frameRect), display: flag) }
    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate: Bool) {
        super.setFrame(topFixed(frameRect), display: flag, animate: animate)
    }

    private func topFixed(_ rect: NSRect) -> NSRect {
        guard rect.origin == frame.origin, rect.height != frame.height, frame.height > 0 else { return rect }
        var fixed = rect
        fixed.origin.y = frame.maxY - rect.height
        return fixed
    }
}

/// The window follows the view's size: when the form turns into Thanks, the view gets smaller
/// and the window fits it (CI showed AppKit does not do it by itself).
final class FittingHost: NSHostingView<AnyView> {
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        Task { @MainActor [weak self] in self?.fit() }
    }

    func fit() {
        let size = intrinsicContentSize
        guard let window, size.width > 0, size.height > 0, window.contentRect(forFrameRect: window.frame).size != size else { return }
        window.setContentSize(size)
    }
}
