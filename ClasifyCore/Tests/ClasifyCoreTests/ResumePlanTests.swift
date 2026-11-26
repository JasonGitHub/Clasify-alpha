import Testing
@testable import ClasifyCore

/// What Play does with no control of playback (CLA-93): one test per step.
@Suite struct ResumePlanTests {
    func seen(
        device: String = "", track: String = "spotify:track:a", context: String = "spotify:playlist:p",
        position: Double = 30, duration: Double = 200, running: Bool = false, hasTrack: Bool = true, age: Double = 0
    ) -> ResumePlan.Seen {
        ResumePlan.Seen(
            activeDevice: device, track: track, context: context, position: position,
            duration: duration, running: running, hasTrack: hasTrack, age: age)
    }

    @Test func anotherDeviceIsTakenBack() {
        let plan = ResumePlan.pick(device: "mac", movedAway: true, seen: seen(device: "phone"), hasResumePoint: true)
        #expect(plan == .takeBack(from: "phone"))
    }

    @Test func theNewestStateIsLoadedAtItsPlace() {
        let plan = ResumePlan.pick(device: "mac", movedAway: true, seen: seen(), hasResumePoint: true)
        #expect(plan == .load(track: "spotify:track:a", playlist: "spotify:playlist:p", at: 30))
    }

    @Test func likedSongsMapToTheLikedSongsList() {
        let plan = ResumePlan.pick(
            device: "mac", movedAway: true, seen: seen(context: "spotify:user:u:collection"), hasResumePoint: false)
        #expect(plan == .load(track: "spotify:track:a", playlist: Playlist.likedSongsID, at: 30))
    }

    @Test func aContextThatCannotLoadFallsToTheResumePoint() {
        let plan = ResumePlan.pick(
            device: "mac", movedAway: true, seen: seen(context: "spotify:station:x"), hasResumePoint: true)
        #expect(plan == .resumePoint)
    }

    @Test func noMoveAwayUsesTheResumePoint() {
        // After a quit or stop, the Mac's own resume point is newer than the cluster.
        let plan = ResumePlan.pick(device: "mac", movedAway: false, seen: seen(device: "phone"), hasResumePoint: true)
        #expect(plan == .resumePoint)
    }

    @Test func nothingToGoOnAsksForAPick() {
        let none = ResumePlan.pick(device: "mac", movedAway: true, seen: nil, hasResumePoint: false)
        #expect(none == .pickASong)
        let empty = ResumePlan.pick(
            device: "mac", movedAway: true, seen: seen(track: "", hasTrack: false), hasResumePoint: false)
        #expect(empty == .pickASong)
    }

    @Test func placeAddsTheAgeWhileRunningAndRestartsPastTheEnd() {
        #expect(seen(position: 30, running: true, age: 5).place == 35)
        #expect(seen(position: 30, running: false, age: 5).place == 30)
        #expect(seen(position: 198, running: true, age: 5).place == 0)
        #expect(seen(position: -1).place == 0)
    }

    @Test func canLoadAcceptsPlaylistsAlbumsArtistsAndLikedSongs() {
        #expect(ResumePlan.canLoad("spotify:playlist:p"))
        #expect(ResumePlan.canLoad("spotify:album:a"))
        #expect(ResumePlan.canLoad("spotify:user:u:collection"))
        #expect(ResumePlan.canLoad("spotify:artist:x"))  // CLA-195: a song from Artists
        #expect(!ResumePlan.canLoad("spotify:station:x"))
    }
}
