import AppKit
import CoreGraphics

/// Logs every on-screen window of Music.app (or any process named like "Music"),
/// every app launch and activation, and Music's Dock and hidden state.
/// It polls every 50 ms, so a short flash shows in the log.
@MainActor final class FlashWatcher {
    static let shared = FlashWatcher()

    private var timer: Timer?
    private var lastWindows: Set<String> = []
    private var lastMusicState = ""
    private let musicIDs: Set<String> = ["com.apple.Music", "com.apple.iTunes"]
    private var log: SpikeLog { SpikeLog.shared }

    func start() {
        guard timer == nil else { return }
        log.add("watch", "watcher on: polls on-screen windows every 50 ms")
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let text = "launched \(app?.bundleIdentifier ?? "?") pid \(app?.processIdentifier ?? 0)"
            MainActor.assumeIsolated { SpikeLog.shared.add("watch", text) }
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let text = "quit \(app?.bundleIdentifier ?? "?")"
            MainActor.assumeIsolated { SpikeLog.shared.add("watch", text) }
        }
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let id = app?.bundleIdentifier ?? "?"
            let own = app?.processIdentifier == getpid()
            MainActor.assumeIsolated {
                SpikeLog.shared.add(own ? "watch" : "FLASH?", "frontmost app is now \(id)")
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated { FlashWatcher.shared.poll() }
        }
    }

    private func poll() {
        let musicApps = NSWorkspace.shared.runningApplications.filter { musicIDs.contains($0.bundleIdentifier ?? "") }
        let musicPIDs = Set(musicApps.map(\.processIdentifier))

        let state = musicApps.map { app in
            let dock = app.activationPolicy == .regular ? "yes" : "no"
            return "Music running: hidden=\(app.isHidden) active=\(app.isActive) Dock icon=\(dock)"
        }.joined(separator: "; ")
        let shown = state.isEmpty ? "Music not running" : state
        if shown != lastMusicState {
            log.add("watch", shown)
            lastMusicState = shown
        }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return }
        var now = Set<String>()
        for window in info {
            let pid = window[kCGWindowOwnerPID as String] as? Int32 ?? 0
            if pid == getpid() { continue }
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            guard musicPIDs.contains(pid) || owner.localizedCaseInsensitiveContains("music") else { continue }
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
            let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
            let number = window[kCGWindowNumber as String] as? Int ?? 0
            let size = "\(Int(bounds["Width"] ?? 0))x\(Int(bounds["Height"] ?? 0))"
            let origin = "\(Int(bounds["X"] ?? 0)),\(Int(bounds["Y"] ?? 0))"
            now.insert("#\(number) \(owner) layer \(layer) alpha \(alpha) \(size) at \(origin)")
        }
        for item in now.subtracting(lastWindows).sorted() { log.add("FLASH?", "window on screen: \(item)") }
        for item in lastWindows.subtracting(now).sorted() { log.add("watch", "window gone: \(item)") }
        lastWindows = now
    }
}
