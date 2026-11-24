import AppKit

/// CLA-185: the end of the app's launch. Before it, AppKit has no window server connection,
/// and a call such as `NSStatusBar.system.statusItem` aborts the app (SkyLight, macOS 15).
/// `AppModel.init` runs inside the SwiftUI `App.init`, before the launch ends, so the code it
/// starts waits here for anything that needs the window server.
@MainActor
enum AppLaunch {
    /// True once `NSApplication.didFinishLaunchingNotification` came (or the app delegate's
    /// `applicationDidFinishLaunching`, whichever is first).
    static private(set) var done = false
    private static var waiting: [@MainActor () -> Void] = []
    private static var observer: NSObjectProtocol?

    /// Runs `work` at the end of the launch, in the order of the calls; at once when it ended.
    static func whenDone(_ work: @escaping @MainActor () -> Void) {
        if done { return work() }
        waiting.append(work)
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
        ) { _ in
            // The queue is .main, so this runs on the main actor.
            MainActor.assumeIsolated { finished() }
        }
    }

    /// The launch ended. A second call does nothing.
    static func finished() {
        guard !done else { return }
        done = true
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        let work = waiting
        waiting = []
        for run in work { run() }
    }
}
