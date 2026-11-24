import Foundation
import Testing
@testable import ClasifyCore

/// A fixed random source, so a shuffled order is the same in each run.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {  // SplitMix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// CLA-179: the play order of local songs.
@Suite struct LocalQueueTests {
    func queue(_ count: Int, start: Int?, shuffle: Bool = false, repeat mode: RepeatMode = .off, seed: UInt64 = 1) -> LocalQueue {
        var random = SeededRandom(state: seed)
        return LocalQueue(count: count, start: start, shuffle: shuffle, repeatMode: mode, using: &random)
    }

    /// Every index the queue gives with `step` until it ends, at most `limit`.
    func walk(_ q: inout LocalQueue, limit: Int = 20, _ step: (inout LocalQueue) -> Int?) -> [Int] {
        var seen: [Int] = []
        while seen.count < limit, let i = step(&q) { seen.append(i) }
        return seen
    }

    @Test func startsAtThePickedSongAndPlaysInOrderToTheEnd() {
        var q = queue(4, start: 1)
        #expect(q.current == 1)
        #expect(walk(&q) { $0.next() } == [2, 3])
        #expect(q.current == 3)  // the end keeps the last song
        #expect(q.next() == nil)
    }

    @Test func noStartIsTheFirstSongInOrder() {
        #expect(queue(3, start: nil).current == 0)
        #expect(queue(3, start: 7).current == 0)  // a start out of range is no start
    }

    @Test func noStartInShuffleIsARandomSong() {
        let firsts = Set((1...40).map { queue(5, start: nil, shuffle: true, seed: $0).current })
        #expect(firsts.count > 1)
        #expect(firsts.allSatisfy { first in first.map { (0..<5).contains($0) } ?? false })
    }

    @Test func anEmptyContextGivesNothing() {
        var q = queue(0, start: 0, shuffle: true, repeat: .all)
        #expect(q.current == nil)
        #expect(q.next() == nil)
        #expect(q.prev() == nil)
        #expect(q.trackEnded() == nil)
        q.setShuffle(false)
        #expect(q.current == nil)
    }

    @Test func prevGoesBackAndStaysOnTheFirstSong() {
        var q = queue(3, start: 2)
        #expect(q.prev() == 1)
        #expect(q.prev() == 0)
        #expect(q.prev() == 0)
    }

    @Test func repeatAllWrapsBothWays() {
        var q = queue(3, start: 2, repeat: .all)
        #expect(q.next() == 0)
        #expect(q.prev() == 2)
        #expect(walk(&q, limit: 7) { $0.next() } == [0, 1, 2, 0, 1, 2, 0])
    }

    @Test func repeatOneRepeatsAtTheEndOfASongButNextMovesOn() {
        var q = queue(3, start: 2, repeat: .one)
        #expect(q.trackEnded() == 2)
        #expect(q.trackEnded() == 2)
        #expect(q.prev() == 1)
        #expect(q.next() == 2)
        #expect(q.next() == nil)  // Repeat One does not wrap on Next
    }

    @Test func aSongEndingPlaysTheNextAndEndsAfterTheLast() {
        var q = queue(3, start: 0)
        #expect(walk(&q) { $0.trackEnded() } == [1, 2])
        q.repeatMode = .all
        #expect(q.trackEnded() == 0)
    }

    @Test func shuffleFromAStartPlaysItFirstThenEverySongOnce() {
        var q = queue(6, start: 4, shuffle: true)
        #expect(q.current == 4)
        let rest = walk(&q) { $0.next() }
        #expect(rest.count == 5)
        #expect(Set(rest + [4]) == Set(0..<6))
    }

    @Test func shuffleOnKeepsTheCurrentSongAndPutsItFirst() {
        var q = queue(6, start: 3)
        var random = SeededRandom(state: 9)
        q.setShuffle(true, using: &random)
        #expect(q.shuffle)
        #expect(q.current == 3)
        #expect(q.order.first == 3)
        #expect(q.order.sorted() == Array(0..<6))
        #expect(q.prev() == 3)  // nothing before it in the new order
    }

    @Test func shuffleOffKeepsTheCurrentSongAndGoesBackToTheContextsOrder() {
        var q = queue(6, start: 2, shuffle: true, seed: 5)
        _ = q.next()
        let now = q.current
        q.setShuffle(false)
        #expect(!q.shuffle)
        #expect(q.current == now)
        #expect(q.order == Array(0..<6))
        if let now { #expect(q.next() == (now + 1 < 6 ? now + 1 : nil)) }
    }

    @Test func shuffleSetTwiceChangesNothing() {
        var q = queue(5, start: 1, shuffle: true, seed: 3)
        let before = q
        q.setShuffle(true)
        #expect(q == before)
    }

    @Test func repeatAllInShuffleWrapsToTheSameOrder() {
        var q = queue(4, start: 0, shuffle: true, repeat: .all, seed: 2)
        let order = q.order
        #expect(walk(&q, limit: 8) { $0.next() } == Array(order[1...]) + order + [order[0]])
    }

    @Test func itemsCarryTheIDAndTheFile() {
        let item = LocalItem(id: "local:track:00A1B2C3D4E5F607", url: URL(fileURLWithPath: "/Music/a.m4a"))
        #expect(item == LocalItem(id: "local:track:00A1B2C3D4E5F607", url: URL(fileURLWithPath: "/Music/a.m4a")))
        #expect(item != LocalItem(id: "local:track:1", url: item.url))
    }
}
