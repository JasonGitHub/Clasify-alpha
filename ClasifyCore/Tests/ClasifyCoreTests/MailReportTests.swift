import Testing
@testable import ClasifyCore

/// Card CX: on the phone, About's row at step 1 is Report a Problem. A press opens a new mail;
/// with no mail, the No Mail Account message shows, and MENU goes back to About.
@Suite struct MailReportTests {
    /// About on the phone, on the Report a Problem row.
    func phoneAbout() -> AppState {
        var s = ReducerTests().openAbout()
        s.platform = .phone
        send(&s, .wheel(1), now: 1005)
        return s
    }

    @Test func onlyThePhoneHasTheMailRow() {
        #expect(Features(.phone).mailReport && !Features(.mac).mailReport)
        #expect(phoneAbout().aboutStatusOpens)
        var mac = ReducerTests().openAbout()
        mac.activated = false
        #expect(!mac.aboutStatusOpens)
    }

    @Test func aPressOpensAMailAndAboutStays() {
        var s = phoneAbout()
        #expect(s.top.off == AppState.aboutStatusStep)
        let stack = s.stack
        #expect(send(&s, .select, now: 1006) == [.openMail])
        #expect(s.stack == stack)
    }

    /// The Mac keeps its Status row: no mail, as before.
    @Test func theMacStatusRowSendsNoMail() {
        var s = ReducerTests().openAbout()
        s.activated = false
        send(&s, .wheel(1), now: 1005)
        #expect(!send(&s, .select, now: 1006).contains(.openMail))
    }

    @Test func mailFailedShowsTheMessageAndMenuGoesBack() {
        var s = phoneAbout()
        send(&s, .select, now: 1006)
        send(&s, .mailFailed, now: 1007)
        #expect(s.top.screen == .noMail && !s.top.screen.isList && s.rows(for: s.top).isEmpty)
        send(&s, .menu, now: 1100)
        #expect(s.top.screen == .about && s.top.off == AppState.aboutStatusStep)
    }

    /// A late answer, after the person left About, shows nothing.
    @Test func mailFailedAwayFromAboutDoesNothing() {
        var s = phoneAbout()
        send(&s, .select, now: 1006)
        send(&s, .menu, now: 1007)
        let before = s
        send(&s, .mailFailed, now: 1008)
        #expect(s == before)
    }
}
