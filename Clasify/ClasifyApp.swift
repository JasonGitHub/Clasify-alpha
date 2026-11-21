import ClasifyCore
import ClasifySkins
import QuartzCore
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
        // CLA-142: the first place, with no saved frame: the device at the screen's center. A
        // saved frame (the place it was left) still wins.
        .defaultWindowPlacement { [margin = DeviceWindow.margin] content, context in
            let size = content.sizeThatFits(.unspecified)
            let origin = FirstWindowPlace.origin(visible: context.defaultDisplay.visibleRect, window: size, margin: margin)
            return WindowPlacement(x: origin.x, y: origin.y, width: size.width, height: size.height)
        }
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
        Window(HowToUse.title, id: Self.id) { HowToUse(menuBar: HintsTrial.on) }
            .windowResizability(.contentSize)
    }
}

/// CLA-166, card CG (381-385): Help › Report a Problem. An AppKit window
/// (`ReportProblemPanel`), exactly the size of the view; it opens next to the device. One
/// window: a second click brings it to the front.
@MainActor
enum ReportProblemWindow {
    private static var window: NSWindow?

    static func show() {
        if let window, window.isVisible || window.isMiniaturized {  // a minimized draft comes back (Codex on #370)
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        // CG.3 (396): the screen follows the activation now; an open window keeps its screen.
        let window = ReportProblemPanel.make(activated: ProblemReporter.shared.activated()) { text, writeBack in
            ProblemReporter.shared.send(text, writeBack: writeBack)
        }
        place(window)
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// 16 pt to the right of the device, top edges in line; with no room there, to its left.
    /// Always inside the screen's visible frame. With no device showing, the screen's center.
    private static func place(_ window: NSWindow) {
        guard let device = DeviceWindow.device, device.isVisible, let screen = device.screen ?? NSScreen.main else { return window.center() }
        let margin = DeviceWindow.margin, room = DeviceWindow.room
        let left = device.frame.minX + margin.leading + room.leading
        let right = device.frame.maxX - margin.trailing - room.trailing
        let top = device.frame.maxY - margin.top - room.top
        let size = window.frame.size, visible = screen.visibleFrame
        var x = right + 16
        if x + size.width > visible.maxX { x = left - 16 - size.width }
        x = min(max(x, visible.minX), visible.maxX - size.width)
        let y = min(max(top - size.height, visible.minY), visible.maxY - size.height)
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// The Help menu: How to Use Clasify in place of the default item. macOS keeps its Search
/// field at the top.
struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            // Card CG.1 (391, 392): a light bulb on How to Use, none on Report a Problem, a line between.
            Button(HowToUse.title, systemImage: "lightbulb") { openWindow(id: HowToUseWindow.id) }
            Divider()
            Button(ReportProblem.title + "…") { ReportProblemWindow.show() }  // card CG, 381
        }
    }
}

/// A Dock click brings the device window to the front, also when Clasify is active and the
/// window is behind another app's window (CLA-47). With no window, SwiftUI opens one.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Card AN.1, 345: the icon's hide leaves the device window at alpha 0 (no blink). Every
    /// other way back (Dock, Cmd+Tab, Settings row Off) shows it at full strength here.
    func applicationDidUnhide(_ notification: Notification) { DeviceWindow.unhidden() }

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

    /// The How to Use window (CLA-77) and the Report a Problem window (CLA-166) are not the device.
    private static func isHelp(_ window: NSWindow) -> Bool {
        window.title == HowToUse.title || window.identifier?.rawValue.hasPrefix(HowToUseWindow.id) == true
            || window.title == ReportProblem.title
    }

    /// Card AN.1: the device window. `WindowShadowOff`'s hook sets it, because only the device
    /// window has that hook. Weak: a closed window goes away.
    static weak var device: NSWindow?
    /// The fade in and out (345). CLA-163, card CE H.2 (a): with `hints.trial` on, a soft
    /// 0.45 s fade in place that also scales the device 98 to 100 %.
    private static var fade: Double { HintsTrial.on ? 0.45 : 0.15 }
    /// The window that is fading out now. A show during the fade cancels the hide.
    private static var hiding: NSWindow?
    /// The window that `show()` is fading in now. The unhide does not jump it to alpha 1.
    private static var showing: NSWindow?

    /// The device window, or with no hook report, the first normal window that is not a panel,
    /// the menu bar or How to Use.
    private static var deviceWindow: NSWindow? {
        device ?? NSApp.windows.first {
            !($0 is NSPanel) && $0.level == .normal && ($0.isVisible || $0.isMiniaturized) && !isHelp($0)
        }
    }

    /// Build 323: true from the icon's hide until a show or an unhide by any other way. Then
    /// a click always shows, whatever AppKit reports about the hidden window.
    static private(set) var iconHid = false

    /// The menu bar icon hid myPod, the same way as Cmd+H.
    static var isHidden: Bool { NSApp.isHidden || iconHid }

    /// The person can see myPod now: the app is not hidden, and the device window is on this
    /// Space, not in the Dock, and not fully covered by other windows. Whether myPod is the
    /// active app does not count: a status item click does not activate it.
    static var isShown: Bool {
        guard !NSApp.isHidden, hiding == nil, let window = deviceWindow else { return false }
        return window.isVisible && !window.isMiniaturized && window.isOnActiveSpace && isSeen(window)
    }

    /// CLA-119: the 3D room the skin adds round the margin now (Codex on #360).
    static var room = EdgeInsets()

    /// CLA-162: where the device is now, for `day_active`, or nil when the person cannot see it:
    /// hidden, in the Dock, on another Space, faded out or fully covered. A partly covered
    /// device counts as seen here. The area is that of the device's center (not the clear
    /// margin), on the screen that holds the center, so a window across 2 screens counts once.
    /// Only myPod's own window: nothing about other apps or the screen's content.
    static var spot: WindowSpot? {
        guard !NSApp.isHidden, hiding == nil, let window = deviceWindow, window.isVisible, !window.isMiniaturized,
              window.isOnActiveSpace, window.alphaValue > 0, window.occlusionState.contains(.visible) else { return nil }
        let f = window.frame, m = margin + room
        let center = CGPoint(x: f.minX + m.leading + (f.width - m.leading - m.trailing) / 2,
                             y: f.minY + m.bottom + (f.height - m.top - m.bottom) / 2)
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { $0.frame.contains(center) }) ?? window.screen else { return nil }
        let s = screen.frame
        let column = Int((center.x - s.minX) / s.width * 3), row = Int((s.maxY - center.y) / s.height * 3)
        // The main screen (with the menu bar) is the one at origin zero. Not by NSScreen object
        // identity: AppKit can give new objects after a screen change.
        return WindowSpot(area: min(2, max(0, row)) * 3 + min(2, max(0, column)), mainScreen: s.origin == .zero,
                          screens: screens.count, width: Int(s.width), height: Int(s.height),
                          display: (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0)
    }

    /// The one rule for a partly covered myPod (Jason, 13:10 JST 11-19): it counts as shown
    /// only when no other window covers any part of the device, so the first click brings a
    /// partly covered myPod to the front. A window over only the clear margin does not count.
    /// The window list gives bounds and layers with no Screen Recording permission.
    private static func isSeen(_ window: NSWindow) -> Bool {
        window.occlusionState.contains(.visible) && !isCovered(window)
    }

    /// Another app's window covers some part of the device.
    private static func isCovered(_ window: NSWindow) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow, .excludeDesktopElements],
                                                    CGWindowID(window.windowNumber)) as? [[String: Any]] else { return false }
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        let above = list.compactMap { info -> WindowCover.Window? in
            // myPod's own windows (How to Use, the menu bar icon) never cover the device.
            guard info[kCGWindowOwnerPID as String] as? Int != ownPID,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return nil }
            return WindowCover.Window(bounds: box(rect), layer: info[kCGWindowLayer as String] as? Int ?? 0,
                                      alpha: info[kCGWindowAlpha as String] as? Double ?? 1)
        }
        let mainHeight = Double(NSScreen.screens.first?.frame.height ?? 0)
        let device = WindowCover.device(frame: box(window.frame), mainHeight: mainHeight,
                                        top: Double(margin.top), leading: Double(margin.leading),
                                        bottom: Double(margin.bottom), trailing: Double(margin.trailing))
        return WindowCover.isCovered(device, by: above)
    }

    private static func box(_ r: CGRect) -> WindowCover.Box {
        WindowCover.Box(x: Double(r.minX), y: Double(r.minY), width: Double(r.width), height: Double(r.height))
    }

    /// Card AN.1, 344-345: fades the device window out, then hides the app as Cmd+H does. The
    /// system keeps every window and gives the front to the app under myPod. The music goes on.
    static func hide() {
        guard !NSApp.isHidden, let window = deviceWindow, window.isVisible else { return }
        hiding = window
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fade
            if HintsTrial.on { context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut) }
            window.animator().alphaValue = 0
        }
        if HintsTrial.on { scale(window, from: 1, to: 0.98) }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(fade))
            guard hiding === window else { return }  // a click showed it again during the fade
            hiding = nil
            // Build 321 (Jason, Finder active): alpha 1 here drew one frame before the hide took
            // effect. The window stays at alpha 0; `show()` or `unhidden()` brings it back.
            iconHid = true
            NSApp.hide(nil)
            window.contentView?.layer?.transform = CATransform3DIdentity  // CLA-163: hidden at alpha 0, so no jump shows
            // The hide did not happen: do not leave an invisible window.
            try? await Task.sleep(for: .seconds(0.5))
            // `iconHid` stays: AppKit may report not hidden after a hide that did happen.
            if !NSApp.isHidden, hiding == nil, showing == nil, window.alphaValue == 0 { window.alphaValue = 1 }
        }
    }

    /// CLA-163, card CE H.2 (a): scales the device window's content about its center, in step
    /// with the fade. It ends at `to`; a scale of 1 leaves no transform behind.
    private static func scale(_ window: NSWindow, from: CGFloat, to: CGFloat) {
        guard let view = window.contentView else { return }
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let mid = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)
        func transform(_ s: CGFloat) -> CATransform3D {
            CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(mid.x, mid.y, 0), s, s, 1), -mid.x, -mid.y, 0)
        }
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = transform(from)
        animation.toValue = transform(to)
        animation.duration = fade
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.transform = to == 1 ? CATransform3DIdentity : transform(to)
        layer.add(animation, forKey: "hintsTrialScale")
    }

    /// The app came back by any way: a device window that the icon faded out shows at full
    /// strength. Not while `show()` fades it in: that fade ends at alpha 1 itself.
    static func unhidden() {
        if showing == nil { iconHid = false }
        guard let window = deviceWindow, showing !== window, hiding == nil else { return }
        window.alphaValue = 1
    }

    /// Card AN.1, 344-345: unhides myPod and fades the device window in where it was. A
    /// window that is already in front stays as it is, so a show at launch changes nothing.
    /// A window behind other apps, in the Dock or on another Space (356) comes here.
    static func show() {
        let fading = hiding
        hiding = nil  // cancels a hide that is still fading
        let wasHidden = NSApp.isHidden || iconHid
        iconHid = false
        if wasHidden {
            deviceWindow?.alphaValue = 0
            showing = deviceWindow
            // Build 321 (Chrome active): `unhide(_:)` also activates myPod. macOS refuses that
            // from a status item click, and the windows stayed off the screen for one click.
            NSApp.unhideWithoutActivation()
            if deviceWindow?.isMiniaturized == true { deviceWindow?.deminiaturize(nil) }  // back from the Dock too
            deviceWindow?.orderFrontRegardless()  // in front even if macOS does not activate myPod
            NSApp.activate()
        } else if fading == nil && isShown {
            return
        } else if !raise() {
            open?()  // the device window was closed: open a new one
            return
        }
        // A device window is there, so always fade it in, also if `unhide` has not put it on
        // the screen yet. Only with no device window at all, open one.
        guard let window = deviceWindow else { showing = nil; open?(); return }
        showing = window
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fade
            if HintsTrial.on { context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut) }
            window.animator().alphaValue = 1
        }
        if HintsTrial.on { scale(window, from: 0.98, to: 1) }
        // The fade's end: the window is fully on, even when the animation did not run.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(fade))
            if showing === window { showing = nil }
            guard hiding !== window else { return }  // a click hid it again during the fade
            window.alphaValue = 1
            // The unhide may end late, and AppKit's window state may not tell. After every show
            // from hidden, do what the person's second click did in build 321 (the calls of
            // `raise()`): unhide again if needed, then put the device window in front.
            if wasHidden {
                if NSApp.isHidden { NSApp.unhideWithoutActivation() }
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                // Last step: no device window at all. `open` is a WindowGroup `openWindow`, which
                // always makes a new window, so never while the device window still exists.
                if !window.isVisible && device == nil { open?() }
            }
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
        let shown = device.flatMap { $0.isVisible || $0.isMiniaturized ? $0 : nil }  // card AN.1: the device first
        guard let window = shown ?? windows.first(where: { $0.canBecomeKey }) ?? windows.first else { return false }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        // A menu bar icon click does not make myPod active, and macOS may refuse the request
        // below. Without this, the window stays behind the other app's windows.
        window.orderFrontRegardless()
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
    /// CLA-162: where the device window is, for `day_active`.
    @ObservationIgnored private var windowWatcher: WindowWatcher?
    /// CLA-97: the beta events to PostHog.
    @ObservationIgnored private var sender: BetaSender?
    @ObservationIgnored private var diagnostics: BetaDiagnostics?
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
        let betaLink = BetaDownloadLink()  // CLA-171: the newest DMG, from the beta feed
        let store = Store(player: services, library: libraries, settings: UserDefaults.standard, betaFeed: BetaFeedLive(link: betaLink), activator: activator)
        // CLA-97: the beta events go to the sender, before the first action. The person is the
        // account ID from the activation answer, in memory only.
        let sender = BetaSender(person: { [weak store] in store?.state.activation.account })
        store.onBetaEvent = { [weak sender] event in sender?.take(event) }
        store.send(.analyticsOn(sender.on))
        store.send(.hintsTrial(HintsTrial.on))  // CLA-163, card CE.1: the menu bar step of the tour
        sender.start()
        // CLA-140: every launch asks the server, also with no device ID yet, so a Mac that was
        // turned off locks again. CLA-156: always, in every build (no switch).
        store.checkActivationAtLaunch()
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
        self.sender = sender
        diagnostics = BetaDiagnostics { [weak store] in store?.send($0) }  // CLA-97 (A4): crash and hang reports
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
        // CLA-171: it downloads the newest DMG directly when the beta feed named a good one.
        store.onGetNewBeta = { NSWorkspace.shared.open(betaLink.target) }
        store.onQuit = { NSApplication.shared.terminate(nil) }
        // Card AN.1 (CLA-43): the menu bar icon, and the window's fade in and out.
        store.onShowWindow = { DeviceWindow.show() }
        store.onHideWindow = { DeviceWindow.hide() }
        menuBarIcon = MenuBarIcon(store: store)
        self.haptics = haptics
        let keeper = SessionKeeper(client: client, library: library, player: player, store: store)
        player.reconnect = { [weak keeper] force in await keeper?.reconnect(force: force) ?? false }
        player.mayRaise = { [weak store] in store?.state.browserLeads != true }  // CLA-153
        self.keeper = keeper
        battery = BatteryWatcher(store: store)
        windowWatcher = WindowWatcher(store: store)  // CLA-162
        ProblemReporter.shared.service = { [weak store] in store?.state.service.rawValue ?? "" }  // CLA-166
        ProblemReporter.shared.activated = { [weak store] in store?.state.activated ?? false }  // CG.3
        // A change made in the Spotify app shows when the user comes back to Clasify.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak store] _ in
            // The queue is .main, so this runs on the main actor.
            MainActor.assumeIsolated {
                store?.send(.activated)
                store?.send(.checkActivation)  // CLA-146: back from the mail, the Activate screen asks at once
            }
        }
        // Setup shows the Spotify App screen (card BB) only when the app is missing and Spotify
        // is the service. Pick Your Music puts Spotify on top only when it is found (CLA-103).
        store.send(.spotifyAppFound(Self.spotifyAppInstalled))
        store.send(.betaBuild(BetaSignature.read()))  // card BI v2: before the login, so an ended beta shows only its end
        if let ms = BetaSender.msSinceProcessStart() { store.send(.appStarted(ms: ms)) }  // CLA-97: the window shows now
        store.send(.launch)  // restores the stored login
        // CLA-97: a normal quit saves the exact day count and ends open 3D views.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak store] _ in
            // The queue is .main, so this runs on the main actor.
            MainActor.assumeIsolated { store?.send(.willQuit) }
        }
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
                // Card BW, CLA-146: the Activate screen's timer checks, their 3-minute end, and the 1.5 s beat.
                let activateDue = state.activateDue(at: now)
                // CLA-170: a song's read with no answer in 3 s; Now Playing shows the service name.
                let readDue = state.readOverdue(at: now)
                if toastDone || overlayDone || scrollDone || artDone || letterDone || beatDone || namesDone || hintDue || betaDue || activateDue
                    || readDue {
                    store?.send(.tick)
                }
                // When the browser login works (change 170) or the Spotify app is found (174),
                // Clasify comes to the front.
                // Not for "You’re all set": the library read may take long, and the person may work elsewhere.
                // CLA-153: not when the login took the tab on to the activate page.
                let raises = state.beatUntil > 0 && state.top.screen != .yourMusic && !state.browserLeads
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
