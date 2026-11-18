import ClasifyCore
import ClasifySkins
import SwiftUI

/// CLA-101: the skin with the K.3D.8 flip, in every build. The 2D device draws card BL's
/// look. In About, Play/Pause turns the device over to its steel back and back again. While
/// the 3D body shows, Space or a click on it turns it back. Leaving About shows the front.
///
/// Card BR, change 288: at the first launch ever, the device arrives in 3D before Hello. Then
/// it sends `.arrived`, which the reducer saves, as the 2D device fades in. With Reduce Motion, or with no Metal device,
/// it sends `.arrived` at once and shows nothing. Input waits in the reducer until then.
///
/// Card BR, changes 289 and 290: a color change on Pick Your Color, or on the Settings Color
/// row, spins the device once in 3D, in place of the color fade. With Reduce Motion it fades.
///
/// CLA-117, a trial: at each later launch of the app (not a window reopen), the device arrives
/// in 3D too, as the UserDefaults string `arrive.cold` says. Missing or "short" is change 303,
/// a 1.0 s turn that input hurries. "full" is change 288 with no Hello, and input waits until it
/// lands. "off" or any other value: no arrival. Reduce Motion or no Metal: no arrival.
///
/// Card BT row 2 (CLA-118): on About, the case is a handle (`K3DShowroom`). A drag turns the
/// device, a click turns it over, and on the back MENU (Esc or Delete) turns it to the front.
/// The first time About opens, the device nudges once. The UserDefaults string `about.turn`
/// says how: missing or "drag", a plain drag; "option", an Option-drag (a plain drag moves the
/// window); "off" or any other value, build 224's About.
///
/// CLA-105 D, change 308 (the showroom trial): on the back, a press held 1.2 s with no move
/// takes the device apart. Apart, a drag turns and tilts it, and a click puts it together and
/// turns it to the front. While it opens or closes, input waits.
///
/// CLA-130 (card BT row 4, changes 351-354): on any screen, Cmd + a two-finger swipe turns the
/// device (`K3DTurn`, `K3DTurnInput`), and Cmd + a pinch takes it apart or puts it together.
/// Cmd up turns it to the front. Until it is back on its front, input does nothing
/// (`Action.deviceTurned`).
struct K3DSpikeSkin: View {
    let store: Store
    let artwork: Artwork
    @State private var flip: K3DFlip

    /// CLA-117: the cold-start arrival, read once at launch.
    static let cold = K3DArrival.Cold(UserDefaults.standard.string(forKey: "arrive.cold"))
    /// This launch's arrival has started, or was skipped. A window opened later shows at once.
    @MainActor private static var launched = false
    /// CLA-118: the About showroom's mode, read once at launch.
    static let aboutTurn = K3DShowroom.Mode(UserDefaults.standard.string(forKey: "about.turn"))
    /// Change 297: the nudge showed once. Saved, so it never shows again.
    static let nudgedKey = "about.nudged"
    /// The drag on the case, from the press to the release.
    @State private var drag: K3DShowroom?
    /// The Option key is down: in the "option" mode, the case takes the drag only then.
    @State private var optionDown = false
    /// CLA-105 D: the press-and-hold on the back that takes the device apart.
    @State private var hold: Task<Void, Never>?
    /// The hold opened the device: the rest of this press does nothing.
    @State private var holdOpened = false
    /// CLA-119: the window's room round today's margins while the 3D body may show:
    /// `K3DRoom.extra`, with the top cut to the room the screen has (`WindowRoom.fit`).
    @State private var room = EdgeInsets()
    /// This skin's own window.
    @State private var window = WindowRoom.WindowRef()
    /// CLA-122: the room's split, for the window's `K3DRoomAnchor`.
    @Environment(\.roomSplit) private var split
    /// CLA-119: the last change that input sent and `colorChanged` already handled.
    @State private var handledCue: ColorCue?
    /// CLA-130: the Cmd turn's pinch, and the landing that sends `.deviceTurned(false)`.
    @State private var cmdTurn = K3DTurn()
    @State private var landing: Task<Void, Never>?
    /// Build 308: applies the travel that waited at the turn's start, if no event comes after it.
    @State private var settling: Task<Void, Never>?

    /// Change 288: at the first launch, the very first frame already waits for the arrival, so
    /// the 2D device does not flash before the turn. The cold-start arrival waits the same way.
    init(store: Store, artwork: Artwork) {
        self.store = store
        self.artwork = artwork
        let arrives = !store.state.arrived || (!Self.launched && Self.cold != .off)
        _flip = State(initialValue: arrives ? .waiting : K3DFlip())
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        K3DFlipView(
            flip: flip, black: store.state.shownColor == .black, margin: DeviceWindow.margin + room, onTap: showroom ? click : turn,
            onRoom: { needs in
                // CLA-124 (Jason 15:19 JST 11-17: the device moved right at each open): no room
                // before the window is on screen. Else SwiftUI makes the window with the room at
                // the restored top-left, and the device lands 190 pt right of its place. The
                // arrivals fit in the margins alone (`K3DRoomTests.theArrivalsFitWithNoRoom`).
                // The first turn after an arrival starts with the window on screen, so it gets its room.
                let shown = window.window?.isVisible == true
                let new = needs && shown ? WindowRoom.fit(K3DRoom.extra, in: window.window) : EdgeInsets()
                split?.set(new)  // before `room`, so no layout pass sees the new room with the old split
                room = new
            }
        ) {
            PocketSkin(state: store.state) { action in
                if store.state.deviceTurned { return }  // CLA-130: the screen faces away
                // CLA-117: the full arrival takes no input until it lands. The short one lands in
                // 0.25 s at most, and the input still does its job.
                if flip.holdsInput(at: .now) { return }
                flip.hurry(at: .now)
                // Change 301: while the device is not at rest on the front, MENU turns it to the
                // front and Play/Pause turns it over. Other input does nothing.
                if showroom, drag != nil || !flip.restsOnFront(at: .now) {
                    if flip.isApart(at: .now) { return }  // CLA-105 D: apart, the keys do nothing
                    if case .play = action, drag == nil {
                        turn()
                    } else if case .menu = action, drag == nil,
                              let front = K3DShowroom.front(flip: flip, reduceMotion: reduceMotion, at: .now) {
                        flip = front
                    }
                    return
                }
                if case .play = action, store.state.top.screen == .about, !flip.arriving {
                    turn()
                } else {
                    // CLA-119 (build 269: the centre black, or white, as a color spin started): a
                    // color step starts its spin in this same update. Started later, in
                    // `.onChange`, the step showed one frame first, and PocketSkin's 0.45 s
                    // color fade began; SwiftUI kept adding that fade over the spin's old color,
                    // so the 2D colors overshot past it for the spin's first frames.
                    let before = cue
                    store.send(action)
                    if cue != before {
                        colorChanged(from: before, to: cue)
                        handledCue = cue
                    }
                }
            }
            .environment(\.artwork, artwork)
            .background(K3DTurnInput(
                onSwipe: swiped, onPinch: pinched, onEnd: turnEnded, onPress: cmdPressed, onHold: cmdHeld, onClick: cmdClicked))
        }
        .overlay { if showroom { handle } }
        // CLA-119: the room goes round the device, and the window grows by the same amount on
        // each side in the same pass, so the device stays where it is on the screen.
        .padding(room)
        .background(WindowRoom(room: room, window: window))
        .onModifierKeysChanged(mask: .option) { _, keys in optionDown = keys.contains(.option) }
        .task(id: store.state.top.screen) { await nudge() }
        .onChange(of: store.state.top.screen) { _, screen in
            if screen != .about && !flip.arriving && !flip.isSpinning(at: .now) {
                flip = K3DFlip()
                drag = nil
                endHold()
                K3DFlip.releaseApart()
                if store.state.deviceTurned { backOnFront() }
            }
        }
        .onChange(of: cue) { old, new in
            // Input's own changes were handled as they were sent. Other changes come here.
            if new == handledCue {
                handledCue = nil
                return
            }
            colorChanged(from: old, to: new)
        }
        .task { await arrive() }
    }

    /// The first launch ever has its arrival with Hello (change 288). A later launch has the
    /// cold-start trial (CLA-117), once per launch.
    private func arrive() async {
        let arrival = K3DArrival.pick(
            arrived: store.state.arrived, launched: Self.launched, cold: Self.cold, canTurn: !reduceMotion && K3DFlip.canDraw)
        Self.launched = true
        let state = store.state
        switch arrival {
        case .first:
            await arriveFirst(state)
        case .short:
            flip = K3DFlip.arriveShort { K3DSpike.snapshot(state, artwork: artwork) }
            // Input can hurry the turn (CLA-117): check its end often, so the device is at rest
            // as soon as it lands.
            while flip.arriving, flip.ends > .now {
                do { try await Task.sleep(for: .seconds(min(0.05, flip.ends.timeIntervalSinceNow))) } catch { break }
            }
            flip = K3DFlip()  // at rest on the front
        case .full:
            // CLA-117: change 288 on the screen the app opens on, with no Hello.
            flip = K3DFlip.arrive { K3DSpike.snapshot(state, artwork: artwork) }
            try? await Task.sleep(for: .seconds(K3DFlip.arriveTurn + K3DFlip.arriveFade))
            flip = K3DFlip()
        case .still:
            // Reduce Motion, no Metal, a window opened again, or "off": the 2D device shows at once.
            flip = K3DFlip()
            if !state.arrived { store.send(.arrived) }
        }
    }

    /// Change 288: the arrival, once ever. The 3D front shows the screen as it is at the start,
    /// Hello's first frame, with nothing written. Hello waits until `.arrived`, which goes 0.2 s
    /// (Hello's own wait) before the turn ends: so the first stroke lands as the turn ends and
    /// the 2D device starts to fade in. Nothing is written before that.
    private func arriveFirst(_ state: AppState) async {
        // Hello's clock is pinned to its start: a slow launch must not show a half-written word.
        let time = state.top.screen == .hello ? state.helloAt : nil
        flip = K3DFlip.arrive { K3DSpike.snapshot(state, artwork: artwork, time: time) }
        try? await Task.sleep(for: .seconds(K3DFlip.arriveTurn - K3DFlip.arriveHelloLead))
        store.send(.arrived)
        try? await Task.sleep(for: .seconds(K3DFlip.arriveHelloLead + K3DFlip.arriveFade))
        flip = K3DFlip()  // at rest on the front, as before
    }

    /// Changes 289 and 290: a new color on the same screen spins the device. During a spin the
    /// 3D screen stays live, and the spin lands on the last color: there is no second spin.
    private func colorChanged(from old: ColorCue, to new: ColorCue) {
        // During a spin or the short arrival (CLA-117), any new row, color or screen shows on the 3D front.
        if flip.takesInput(at: .now) {
            // CLA-119: with no key pressed: the press that made the change lets go a moment later.
            let wheel = WheelLook.released
            flip.show(screen: K3DSpike.snapshot(store.state, artwork: artwork, wheel: wheel))
            // CLA-119: to 180° the 3D front shows the old color's picture.
            if let old = flip.oldColor(at: .now) {
                flip.show(old: K3DSpike.snapshot(store.state, artwork: artwork, wheel: wheel, black: old))
            }
            return
        }
        guard old.black != new.black, old.top.screen == new.top.screen else { return }
        let turn: Double
        switch new.top.screen {
        case .color: turn = K3DFlip.spinPick
        case .settings: turn = K3DFlip.spinSettings
        default: return
        }
        guard !reduceMotion, K3DFlip.canDraw, flip.restsOnFront(at: .now) else { return }
        let state = store.state, wheel = WheelLook.released  // CLA-119: the centre button let go
        flip = K3DFlip.spin(
            turn: turn, fromBlack: old.black, screen: { K3DSpike.snapshot(state, artwork: artwork, wheel: wheel) },
            old: { K3DSpike.snapshot(state, artwork: artwork, wheel: wheel, black: old.black) })
    }

    /// The screen, its row and the device's color, for `colorChanged`.
    private var cue: ColorCue { ColorCue(top: store.state.top, black: store.state.shownColor == .black) }

    /// CLA-118: the About showroom is on.
    private var showroom: Bool {
        Self.aboutTurn != .off && store.state.top.screen == .about && !flip.arriving && K3DFlip.canDraw
    }

    /// Change 296: the handle over the device. On the front it is the case only, so the screen
    /// and the wheel keep their jobs. During a drag and on the back it is the whole device.
    private var handle: some View {
        let size = PocketSkin.size
        let whole = drag != nil || flip.toBack || flip.isApart(at: .now)
        let shape = whole ? Path(CGRect(origin: .zero, size: size)) : K3DShowroom.casePath
        return Color.clear
            .frame(width: size.width, height: size.height)
            .contentShape(shape, eoFill: true)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragged($0.translation) }
                    .onEnded { _ in released() })
            .pointerStyle(drag == nil ? .grabIdle : .grabActive)
            .allowsHitTesting(Self.aboutTurn == .drag || optionDown || drag != nil)
    }

    /// Change 305 and 307: the device follows the drag once it passes 4 points. A turn that runs
    /// stops where it is at the press.
    private func dragged(_ translation: CGSize) {
        let now = Date.now
        if holdOpened || store.state.deviceTurned || (self.drag == nil && flip.apartRuns(at: now)) { return }
        if self.drag == nil, K3DShowroom.canHold(flip: flip, at: now) { startHold() }
        var drag = self.drag ?? K3DShowroom(flip: flip, at: now)
        if self.drag == nil, !flip.isResting(at: now) {
            flip = flip.held(angle: flip.angle(at: now), tilt: flip.tilt(at: now))
        }
        if drag.moved || abs(translation.width) + abs(translation.height) > K3DShowroom.slop {
            // The 3D front shows the screen as it is now: the picture is made before the turn.
            if flip.restsOnFront(at: now) { flip.show(screen: K3DSpike.snapshot(store.state, artwork: artwork)) }
            flip = drag.changed(translation, flip: flip)
            if hold != nil, !drag.apart { endHold(release: true) }  // a move is not a hold
        }
        self.drag = drag
    }

    /// CLA-105 D: the hold starts. The prints and the parts' first frame are made now, so the
    /// device opens with no wait. After 1.2 s with no move, the device opens.
    private func startHold() {
        K3DFlip.prepareApart()
        hold = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(K3DShowroom.holdTime)) } catch { return }
            hold = nil
            guard let drag, !drag.moved, showroom else { return }
            self.drag = nil
            holdOpened = true
            flip = flip.apart(at: .now)
        }
    }

    /// Stops a hold that has not opened the device. `release`: it frees the prints too.
    private func endHold(release: Bool = false) {
        guard let task = hold else { return }
        task.cancel()
        hold = nil
        if release, !flip.isApart(at: .now) { K3DFlip.releaseApart() }
    }

    /// Changes 304 and 305: a click turns the device over; a drag goes on or comes back.
    private func released() {
        if holdOpened {
            holdOpened = false
            return
        }
        endHold(release: true)
        guard let drag else { return }
        self.drag = nil
        if !drag.moved, flip.restsOnFront(at: .now) { flip.show(screen: K3DSpike.snapshot(store.state, artwork: artwork)) }
        flip = drag.ended(flip: flip, reduceMotion: reduceMotion, at: .now)
    }

    /// Change 304: a click on the 3D body where the handle is not (the screen or the wheel during
    /// a turn to the front) turns it over too.
    private func click() {
        guard drag == nil, !store.state.deviceTurned, !flip.apartRuns(at: .now) else { return }
        flip = K3DShowroom(flip: flip, at: .now).ended(flip: flip, reduceMotion: reduceMotion, at: .now)
    }

    /// Change 297: 1.4 s after About opens for the first time ever, the device turns 16° and back.
    /// Not with Reduce Motion, and only when the device rests on the front.
    private func nudge() async {
        let defaults = UserDefaults.standard
        guard showroom, !reduceMotion, !defaults.bool(forKey: Self.nudgedKey) else { return }
        do { try await Task.sleep(for: .seconds(K3DShowroom.nudgeDelay)) } catch { return }
        guard showroom, drag == nil, flip.restsOnFront(at: .now) else { return }
        defaults.set(true, forKey: Self.nudgedKey)
        flip.show(screen: K3DSpike.snapshot(store.state, artwork: artwork))
        flip = flip.nudge(at: .now)
    }

    /// Change 351: the swipe turns and tilts the device. A turn that runs stops where it is.
    private func swiped(_ dx: Double, _ dy: Double) {
        guard startTurn() else { return }
        flip = cmdTurn.swipe(dx: dx, dy: dy, flip: flip, at: .now)
        // Build 308: a single wheel line or a short drag sends no more events, so the travel
        // that waits for `K3DTurn.settle` is applied once it ends.
        guard cmdTurn.waitingX != 0 || cmdTurn.waitingY != 0, settling == nil else { return }
        settling = Task { @MainActor in
            try? await Task.sleep(for: .seconds(K3DTurn.settle + 0.01))
            settling = nil
            guard cmdTurn.waitingX != 0 || cmdTurn.waitingY != 0 else { return }
            flip = cmdTurn.swipe(dx: 0, dy: 0, flip: flip, at: .now)
        }
    }

    /// Change 354: the pinch takes the device apart or puts it together.
    private func pinched(_ amount: Double, began: Bool) {
        if began, !flip.isApart(at: .now) { K3DFlip.prepareApart() }
        guard startTurn() else { return }
        flip = cmdTurn.pinched(amount, flip: flip, at: .now)
    }

    /// Change 355: a Cmd press with the mouse. The prints get ready, so a hold opens with no wait.
    private func cmdPressed() {
        if !flip.isApart(at: .now) { K3DFlip.prepareApart() }
    }

    /// Change 355: a Cmd hold of 1.2 s with no move takes the device apart (the 308 motion).
    private func cmdHeld() {
        guard !flip.isApart(at: .now), startTurn() else { return }
        flip = flip.apart(at: .now)
    }

    /// Change 355: a Cmd click puts the open device together where it is. Only Cmd up turns it
    /// to the front (353). A click on the closed device does nothing.
    private func cmdClicked() {
        guard flip.isApart(at: .now), !flip.apartRuns(at: .now) else {
            if !store.state.deviceTurned, !flip.isApart(at: .now) { K3DFlip.releaseApart() }
            return
        }
        guard startTurn() else { return }
        flip = flip.apart(at: .now, staysTurned: true)
    }

    /// The turn takes the device: the 3D front shows the screen as it is now, and input stops.
    private func startTurn() -> Bool {
        let now = Date.now
        guard K3DFlip.canDraw, drag == nil, K3DTurn.canTurn(flip, at: now) else { return false }
        landing?.cancel()
        landing = nil
        // Once per turn: a slow pinch sends many events before the device moves.
        guard !store.state.deviceTurned else { return true }
        if flip.restsOnFront(at: now) { flip.show(screen: K3DSpike.snapshot(store.state, artwork: artwork)) }
        store.send(.deviceTurned(true))
        return true
    }

    /// Change 353: Cmd up, or the app went to the back. The device goes to its front, once a
    /// take-apart that runs has ended, and input works again when it is there.
    private func turnEnded() {
        cmdTurn = K3DTurn()
        guard store.state.deviceTurned, landing == nil else { return }
        flip = K3DTurn.ended(flip: flip, reduceMotion: reduceMotion, at: .now)
        landing = Task { @MainActor in
            // A guard so input can never stay dead: a take-apart and the close take 4.5 s at most.
            let deadline = Date.now.addingTimeInterval(6)
            while !flip.restsOnFront(at: .now), Date.now < deadline {
                do { try await Task.sleep(for: .seconds(max(0.02, flip.ends.timeIntervalSinceNow))) } catch { return }
                // The take-apart that ran at Cmd up has ended: now the device closes.
                if flip.isResting(at: .now) { flip = K3DTurn.ended(flip: flip, reduceMotion: reduceMotion, at: .now) }
            }
            if !flip.restsOnFront(at: .now) { flip = K3DFlip() }
            backOnFront()
        }
    }

    /// The device is on its front again: all input works.
    private func backOnFront() {
        landing?.cancel()
        landing = nil
        cmdTurn = K3DTurn()
        if store.state.top.screen != .about { K3DFlip.releaseApart() }
        store.send(.deviceTurned(false))
    }

    private func turn() {
        guard !flip.arriving, !flip.isSpinning(at: .now), !store.state.deviceTurned else { return }  // no flip during an arrival or a spin
        // The 3D front shows the screen as it is now. The snapshot is made before the turn starts.
        flip.turn { K3DSpike.snapshot(store.state, artwork: artwork) }
    }
}

/// What a color spin starts from: the screen, its rows, and the device's color (changes 289
/// and 290). During a spin, any change of it takes a new picture for the 3D front.
private struct ColorCue: Equatable {
    let top: Frame
    let black: Bool
}
