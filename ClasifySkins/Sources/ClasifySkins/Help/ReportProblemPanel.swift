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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: ReportProblem.width, height: ReportProblem.formHeight),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        let content = ReportProblem(onSend: onSend, onClose: { [weak window] in window?.close() })
        configure(window, content)
        return window
    }

    /// The snapshot tests use it with a fixed text, screen and time.
    static func configure(_ window: NSWindow, _ content: ReportProblem) {
        window.title = ReportProblem.title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        let host = NSHostingView(rootView: content)
        // No safe area: the view starts at the window's top, under the transparent title bar,
        // so the window's size is the view's size and nothing more.
        host.safeAreaRegions = []
        host.sizingOptions = [.minSize, .intrinsicContentSize, .maxSize]
        window.contentView = host
        window.setContentSize(host.fittingSize)
    }
}
