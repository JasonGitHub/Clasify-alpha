import AVFoundation
import Foundation

/// Bounded buffer between the librespot audio callback and AVAudioEngine.
/// `write` blocks while the buffer is full. This blocking paces librespot.
/// `read` never blocks: it fills silence when the buffer is short.
///
/// `@unchecked Sendable` is safe here: every access to `storage`, `head`, `count`
/// and `isClosed` happens while `condition` is locked.
final class AudioRing: @unchecked Sendable {
    /// Interleaved stereo floats. 0.5 s at 44.1 kHz, so Pause stops quickly.
    private let capacity = 44_100
    private let storage: UnsafeMutablePointer<Float>
    private var head = 0
    private var count = 0
    private var isClosed = false
    private let condition = NSCondition()

    init() {
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit { storage.deallocate() }

    /// Called on the librespot playback thread.
    func write(_ samples: UnsafePointer<Float>, count total: Int) {
        var offset = 0
        condition.lock()
        defer { condition.unlock() }
        while offset < total {
            while count == capacity && !isClosed { condition.wait() }
            if isClosed { return }
            let chunk = min(total - offset, capacity - count)
            for index in 0..<chunk {
                storage[(head + count + index) % capacity] = samples[offset + index]
            }
            count += chunk
            offset += chunk
        }
    }

    /// Called on the audio render thread. Fills two non-interleaved channels.
    func read(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        condition.lock()
        let available = min(frames, count / 2)
        for frame in 0..<available {
            left[frame] = storage[(head + frame * 2) % capacity]
            right[frame] = storage[(head + frame * 2 + 1) % capacity]
        }
        head = (head + available * 2) % capacity
        count -= available * 2
        condition.broadcast()
        condition.unlock()
        for frame in available..<frames {
            left[frame] = 0
            right[frame] = 0
        }
    }

    /// Drops buffered audio, for example on Pause.
    func clear() {
        condition.lock()
        head = 0
        count = 0
        condition.broadcast()
        condition.unlock()
    }

    /// After this, `write` returns at once. Use it when no engine drains the buffer.
    func close() {
        condition.lock()
        isClosed = true
        condition.broadcast()
        condition.unlock()
    }
}

/// Plays the ring buffer through AVAudioEngine.
@MainActor
final class AudioOutput {
    let ring = AudioRing()
    private let engine = AVAudioEngine()

    /// Returns nil on success, else the error text.
    func start() -> String? {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let source = Self.makeSource(format: format, ring: ring)
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
            return nil
        } catch {
            ring.close()
            return error.localizedDescription
        }
    }

    /// Nonisolated, so the render block is not main-actor isolated. Swift 6 would
    /// otherwise check for the main thread inside it, and it runs on the audio thread.
    nonisolated private static func makeSource(format: AVAudioFormat, ring: AudioRing) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count == 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }
            ring.read(left: left, right: right, frames: Int(frameCount))
            return noErr
        }
    }
}
