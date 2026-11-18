import ClasifyCore
import ClasifySkins
import SwiftUI

/// The app: only the device shows. The window has no frame and a clear background, and it
/// moves when you drag the device. Minimum macOS is 15 for this plain window style (CLA-81).
@main
struct PlainWindowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("myPod", id: DeviceWindow.id) {
            DeviceRoot { AppContent(model: model) }
                .containerBackground(.clear, for: .window)
                .gesture(WindowDragGesture())
                .background(WindowShadowOff())
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .commands { DebugCommands(model: model); HelpCommands() }
        HowToUseWindow()
    }
}

/// Help › How to Use Clasify (card BC, change 152): a small window with the wheel's actions
/// and their keys. One window: a second click brings it to the front.
struct HowToUseWindow: Scene {
    static let id = "how-to-use"

    var body: some Scene {
        Window(HowToUse.title, id: Self.id) { HowToUse() }
            .windowResizability(.contentSize)
    }
}

/// The Help menu: How to Use Clasify in place of the default item. macOS keeps its Search
/// field at the top.
struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button(HowToUse.title) { openWindow(id: HowToUseWindow.id) }
        }
    }
}

/// A Dock click brings the device window to the front, also when Clasify is active and the
/// window is behind another app's window (CLA-47). With no window, SwiftUI opens one.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Card AN.1, 347: the Dock icon also shows a myPod that the menu bar icon hid.
        if DeviceWindow.isHidden { DeviceWindow.show(); return false }
        if DeviceWindow.raise() { return false }
        // Only How to Use shows. SwiftUI opens a window by itself only when none shows.
        if flag, let open = DeviceWindow.open {
            open()
            return false
        }
        return true
    }
}

@MainActor
enum DeviceWindow {
    static let id = "device"
    /// Clear room around the device for its shadow: radius 20, 20 down (CLA-92). A smaller
    /// margin cuts the shadow off at the window's edge. The shadow falls down, so the top needs
    /// little room; a small top lets the device reach the menu bar when dragged (CLA-94).
    static let margin = EdgeInsets(top: 5, leading: 60, bottom: 90, trailing: 60)
    /// Opens a new device window. AppContent sets it, because only a view gets `openWindow`.
    static var open: (() -> Void)?

    /// The How to Use window (CLA-77) is not the device.
    private static func isHelp(_ window: NSWindow) -> Bool {
        window.title == HowToUse.title || window.identifier?.rawValue.hasPrefix(HowToUseWindow.id) == true
    }

    /// Card AN.1: the device window that the menu bar icon hid. It keeps its place and screen.
    /// A strong reference: off the screen, nothing else may keep the window.
    private static var hidden: NSWindow?
    static var isHidden: Bool { hidden != nil }
    /// The fade in and out (345).
    private static let fade = 0.15

    /// The device window shows: Clasify is in front, and the window is on screen, not in the
    /// Dock. A window behind other apps counts as not shown, so a click brings it forward.
    static var isShown: Bool {
        NSApp.isActive && hidden == nil && NSApp.windows.contains {
            !($0 is NSPanel) && $0.level == .normal && $0.isVisible && !$0.isMiniaturized && !isHelp($0)
        }
    }

    /// Card AN.1, 344-345: fades the device window out, then takes it off the screen. The music
    /// goes on.
    static func hide() {
        let windows = NSApp.windows.filter { !($0 is NSPanel) && $0.level == .normal && $0.isVisible && !isHelp($0) }
        guard let window = windows.first(where: { $0.canBecomeKey }) ?? windows.first else { return }
        hidden = window
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fade
            window.animator().alphaValue = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(fade))
            guard hidden === window else { return }  // a click showed it again during the fade
            window.orderOut(nil)
            window.alphaValue = 1
            // With no other myPod window on screen, the app gives up the front, so the app
            // under it becomes active. Not NSApp.hide: an unhide brings back only the windows
            // that were on screen at the hide, so the device window stayed away (build 308).
            let others = NSApp.windows.contains { !($0 is NSPanel) && $0.level == .normal && $0.isVisible }
            if !others { NSApp.deactivate() }
        }
    }

    /// Card AN.1, 344-345: fades the hidden device window in where it was. With none hidden, it
    /// brings the window to the front, or opens one.
    static func show() {
        guard let window = hidden else {
            // Already in front: do nothing, so a show at launch changes nothing. A window
            // behind other apps or in the Dock comes to the front.
            if !isShown && !raise() { open?() }
            return
        }
        hidden = nil
        if NSApp.isHidden { NSApp.unhide(nil) }  // after Cmd+H
        if !window.isVisible { window.alphaValue = 0 }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        guard window.isVisible else {
            // The window did not come back: show any device window, or open a new one.
            window.alphaValue = 1
            if !raise() { open?() }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fade
            window.animator().alphaValue = 1
        }
    }

    /// Puts the device window in front and makes Clasify active: back from the Dock when it
    /// is minimized. Returns false when there is no such window, for example after a close.
    @discardableResult static func raise() -> Bool {
        // Not a panel, the menu bar or a menu. The plain window may not say that it can be
        // key, so a window that can is only preferred.
        let windows = NSApp.windows.filter {
            !($0 is NSPanel) && $0.level == .normal && ($0.isVisible || $0.isMiniaturized) && !isHelp($0)
        }
        guard let window = windows.first(where: { $0.canBecomeKey }) ?? windows.first else { return false }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        return true
    }
}

/// CLA-122: the device window's root. `K3DRoomAnchor` places the content (with the margin)
/// by the room's split, so the device stays put when the window and the content change size in
/// different frames. Each window has its own split.
struct DeviceRoot<Content: View>: View {
    let content: Content
    @State private var split = K3DRoomAnchor.Fraction()

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        K3DRoomAnchor(fraction: split) {
            content.padding(DeviceWindow.margin)
        }
        .environment(\.roomSplit, split)
    }
}

/// The skin, or the temporary test window while the skin is new.
struct AppContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        content.onAppear {
            let openWindow = openWindow
            DeviceWindow.open = { openWindow(id: DeviceWindow.id) }
        }
    }

    @ViewBuilder private var content: some View {
        if model.showsTestWindow || model.store == nil {
            TestWindow(store: model.store)
                .background(Color(nsColor: .windowBackgroundColor))
        } else if let store = model.store {
            K3DSpikeSkin(store: store, artwork: model.artwork.artwork)
        }
    }
}

/// TEMPORARY: a View menu item that switches to the test window. Remove it with TestWindow.swift.
struct DebugCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Toggle("Show Test Window", isOn: $model.showsTestWindow)
                .keyboardShortcut("t", modifiers: [.command, .option])
        }
    }
}

/// Builds the app's one store. The library and the player share one librespot client,
/// so they use one bridge and one Spotify session.
@MainActor @Observable
final class AppModel {
    let store: Store?
    /// TEMPORARY: shows TestWindow in place of the skin.
    var showsTestWindow = false
    /// The album covers that the skin draws.
    let artwork = ArtworkLoader()
    @ObservationIgnored private var ticker: Task<Void, Never>?
    /// TEST: trackpad ticks that follow the wheel.
    @ObservationIgnored private var haptics: Haptics?
    /// Logs in again in the background when the librespot session drops.
    @ObservationIgnored private var keeper: SessionKeeper?
    /// Sends the Mac's battery to the store, for the title bar.
    @ObservationIgnored private var battery: BatteryWatcher?
    /// Card AN.1 (CLA-43): the menu bar icon that shows and hides myPod.
    @ObservationIgnored private var menuBarIcon: MenuBarIcon?

    init() {
        guard let client = LibrespotClient() else {
            store = nil
            return
        }
        let library = LibrespotLibrary(client: client)
        let player = SpotifyConnectPlayer(client: client, library: library)
        let appleMusic = AppleMusicPlayer()
        let service = ClasifyCore.Settings(from: UserDefaults.standard).service
        let services = ServicePlayer(spotify: player, appleMusic: appleMusic, service: service)
        let libraries = ServiceLibrary(spotify: library, appleMusic: AppleMusicLibrary(), service: service)
        let activator = ServerActivator()
        let store = Store(player: services, library: libraries, settings: UserDefaults.standard, betaFeed: BetaFeedLive(), activator: activator)
        // CLA-128: behind the activate.on switch (off by default). A Mac that has activated
        // before skips the step.
        if store.state.activateOn && DeviceIDStore.read() != nil { store.checkActivationAtLaunch() }
        // Card BW: the page with its one-time code opens in the browser.
        store.onOpenActivatePage = { page in
            if let url = URL(string: page) { NSWorkspace.shared.open(url) }
        }
        // Leaving Settings with another service (card BM, change 260). The reducer sends this
        // before the new service logs in, so every later call goes to the new one.
        store.onSetService = { [weak services, weak libraries, weak player, weak store] service in
            services?.service = service
            libraries?.service = service
            // The hidden Spotify app does not run while Apple Music is active (CLA-103).
            if service == .appleMusic { player?.quitApp() }
            // The real check, for both services: Pick Your Music orders its rows from it
            // (CLA-103). The reducer opens the Spotify App screen (card BB) only on Spotify.
            store?.send(.spotifyAppFound(Self.spotifyAppInstalled))
        }
        player.send = { [weak store] action in store?.send(action) }
        appleMusic.send = { [weak store] action in store?.send(action) }
        self.store = store
        let haptics = Haptics(store: store)
        store.onWheelStep = { [weak haptics] in haptics?.step() }
        // Card BB: "Get Spotify App" opens Spotify's download page in the browser.
        store.onGetSpotifyApp = {
            if let url = URL(string: "https://www.spotify.com/download/mac/") { NSWorkspace.shared.open(url) }
        }
        // Card AX, screen 135: "Get Premium" opens Spotify's Premium page in the browser. On
        // Apple Music, "Get Apple Music" opens Apple's page (card BM, change 259).
        store.onGetPremium = { [weak store] in
            let page = store?.state.service == .appleMusic ? "https://www.apple.com/apple-music/" : "https://www.spotify.com/premium/"
            if let url = URL(string: page) { NSWorkspace.shared.open(url) }
        }
        // Card BM, change 258: "Open Settings" opens Privacy & Security > Media & Apple Music.
        store.onOpenPrivacy = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media") {
                NSWorkspace.shared.open(url)
            }
        }
        // Card BI v2: "Get New Beta" opens the download page; "Quit" on the ended beta quits.
        store.onGetNewBeta = { NSWorkspace.shared.open(BetaSignature.downloadPage) }
        store.onQuit = { NSApplication.shared.terminate(nil) }
        // Card AN.1 (CLA-43): the menu bar icon, and the window's fade in and out.
        store.onShowWindow = { DeviceWindow.show() }
        store.onHideWindow = { DeviceWindow.hide() }
        menuBarIcon = MenuBarIcon(store: store)
        self.haptics = haptics
        let keeper = SessionKeeper(client: client, library: library, player: player, store: store)
        player.reconnect = { [weak keeper] force in await keeper?.reconnect(force: force) ?? false }
        self.keeper = keeper
        battery = BatteryWatcher(store: store)
        // A change made in the Spotify app shows when the user comes back to Clasify.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak store] _ in
            // The queue is .main, so this runs on the main actor.
            MainActor.assumeIsolated { store?.send(.activated) }
        }
        // Setup shows the Spotify App screen (card BB) only when the app is missing and Spotify
        // is the service. Pick Your Music puts Spotify on top only when it is found (CLA-103).
        store.send(.spotifyAppFound(Self.spotifyAppInstalled))
        store.send(.betaBuild(BetaSignature.read()))  // card BI v2: before the login, so an ended beta shows only its end
        store.send(.launch)  // restores the stored login
        // The reducer's toast, overlay, scroll bar, cover and Cover Flow letter timers run on .tick. Each .tick redraws the skin,
        // so send it only when a timer has run out.
        // The same loop starts the player's pre-warm when a sign-in or a restore succeeds,
        // and resets the player when the session signs out.
        ticker = Task { [weak store, weak player, artwork] in
            var spotifySignedIn = false
            var spotifyCheck = 0.0  // when the Spotify App screen last looked for the app
            var beat = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let state = store?.state else { return }
                // Only Spotify needs the pre-warm: it starts the hidden Spotify app.
                let spotify = state.signedIn && state.service == .spotify
                if spotify && !spotifySignedIn { player?.prewarm() }
                if !spotify && spotifySignedIn { player?.reset() }
                spotifySignedIn = spotify
                artwork.prefetchNext(in: state)
                let now = Dependencies.live.now()
                // While the Spotify App screen shows, look for the app every 3 s, quietly (change 174).
                if state.top.screen == .spotifyApp, now - spotifyCheck >= 3 {
                    spotifyCheck = now
                    store?.send(.spotifyAppFound(Self.spotifyAppInstalled))
                }
                let toastDone = state.toastUntil > 0 && now > state.toastUntil
                let overlayDone = state.overlayUntil > 0 && now > state.overlayUntil
                let scrollDone = state.scrollUntil > 0 && now > state.scrollUntil
                let artDone = state.artUntil > 0 && now > state.artUntil
                let letterDone = state.letterUntil > 0 && now > state.letterUntil
                // "You’re in" (card AX, change 175) goes on after its beat.
                let beatDone = state.beatUntil > 0 && now >= state.beatUntil
                // The first read waits until every playlist name has shown (card AY, change 191).
                let namesDone = state.namesHold > 0 && now >= state.namesHold
                // A first-time hint's tip shows, or the hint ends (card BA, BA.1).
                let hintDue = state.hintDue > 0 && now >= state.hintDue
                // A beta's warning on day 27, or its end on day 30 (card BI v2).
                let betaDue = state.betaDue > 0 && now >= state.betaDue
                // Card BW: the Activate screen's 30 s checks, their 15-minute end, and the 1.5 s beat.
                let activateDue = state.activateDue(at: now)
                if toastDone || overlayDone || scrollDone || artDone || letterDone || beatDone || namesDone || hintDue || betaDue || activateDue {
                    store?.send(.tick)
                }
                // When the browser login works (change 170) or the Spotify app is found (174),
                // Clasify comes to the front.
                // Not for "You’re all set": the library read may take long, and the person may work elsewhere.
                let raises = state.beatUntil > 0 && state.top.screen != .yourMusic
                if raises && !beat { DeviceWindow.raise() }
                beat = raises
            }
        }
    }

    /// The Spotify desktop app is on this Mac. Launch Services finds it by its bundle ID; this
    /// does not start it.
    static var spotifyAppInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: SpotifyConnectPlayer.bundleID) != nil
    }
}
