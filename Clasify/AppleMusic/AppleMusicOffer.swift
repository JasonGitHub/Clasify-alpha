@preconcurrency import MusicKit
import SwiftUI

/// "Get Apple Music" on the Not subscribed screen (card BM, change 259) shows Apple's own
/// sign-up sheet in the app, not a web page. Apple's Performance Partners program can pay for
/// a new member who signs up through this sheet. The affiliate token comes only after Apple
/// accepts Clasify, so it is nil for now: the sheet works the same, and nobody gets paid.
enum AppleMusicOffer {
    /// The Partnerize "Partner Token". Not a secret: it is in every public affiliate link.
    static let affiliateToken: String? = nil
    /// One value for this place in the app, never one per user: the program does not allow
    /// user or device identifiers. At most 40 characters, with no "?", "!" or "&".
    static let campaignToken = "not-subscribed"
    /// Apple's page, for when the sheet cannot show.
    static let page = URL(string: "https://www.apple.com/apple-music/")

    /// Made once and kept: a forum report says the sheet can crash when its options change
    /// while it shows.
    static func makeOptions() -> MusicSubscriptionOffer.Options {
        var options = MusicSubscriptionOffer.Options()
        options.affiliateToken = affiliateToken
        options.campaignToken = campaignToken
        return options
    }

    @MainActor static func openPage() {
        if let page { NSWorkspace.shared.open(page) }
    }
}

extension View {
    /// Shows Apple's sign-up sheet while `isPresented` is true. `onFail` runs when the sheet
    /// cannot load.
    func appleMusicOffer(
        isPresented: Binding<Bool>, options: MusicSubscriptionOffer.Options,
        onFail: @escaping @MainActor @Sendable () -> Void
    ) -> some View {
        // @Sendable, so the closure has no actor: MusicKit may call it off the main thread.
        musicSubscriptionOffer(isPresented: isPresented, options: options) { @Sendable error in
            guard error != nil else { return }
            Task { @MainActor in onFail() }
        }
    }
}
