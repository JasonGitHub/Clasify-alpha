extension AppState {
    /// The reducer's toast, overlay, scroll bar, cover and Cover Flow letter timers run on
    /// `.tick`. Each `.tick` redraws the skin, so the app's timer loop sends it only when this is
    /// true: a timer has run out. CLA-202: in the core, so the Mac and the iPhone shells share it.
    public func tickDue(at now: Double) -> Bool {
        let toastDone = toastUntil > 0 && now > toastUntil
        let overlayDone = overlayUntil > 0 && now > overlayUntil
        let scrollDone = scrollUntil > 0 && now > scrollUntil
        let artDone = artUntil > 0 && now > artUntil
        let letterDone = letterUntil > 0 && now > letterUntil
        // "You’re in" (card AX, change 175) goes on after its beat.
        let beatDone = beatUntil > 0 && now >= beatUntil
        // The first read waits until every playlist name has shown (card AY, change 191).
        let namesDone = namesHold > 0 && now >= namesHold
        // A first-time hint's tip shows, or the hint ends (card BA, BA.1).
        let hintDone = hintDue > 0 && now >= hintDue
        // A beta's warning on day 27, or its end on day 30 (card BI v2).
        let betaDone = betaDue > 0 && now >= betaDue
        // Card BW, CLA-146: the Activate screen's timer checks, their 3-minute end, and the 1.5 s beat.
        let activateDone = activateDue(at: now)
        // CLA-170: a song's read with no answer in 3 s; Now Playing shows the service name.
        let readDone = readOverdue(at: now)
        // CLA-183: library data arrived while Search is open; its index is made again.
        let searchDone = searchIndexDue(at: now)
        // CLA-186: a play press brought no music in 20 s, for `first_step`.
        let firstStepDone = firstStepDue(at: now)
        return toastDone || overlayDone || scrollDone || artDone || letterDone || beatDone || namesDone || hintDone
            || betaDone || activateDone || readDone || searchDone || firstStepDone
    }
}
