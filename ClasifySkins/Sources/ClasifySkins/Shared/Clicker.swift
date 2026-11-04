import AppKit

/// The click that the wheel and the buttons make when the Clicker setting is on.
/// It is the mockup's 4 ms synthetic click, made in memory. Nothing is written to disk.
@MainActor
final class Clicker {
    static let shared = Clicker()

    private let sound = NSSound(data: Clicker.wav())

    func click() {
        // A copy, so a fast turn of the wheel can play clicks that overlap.
        (sound?.copy() as? NSSound)?.play()
    }

    nonisolated static let sampleRate = 44_100

    /// The mockup's click: a short impulse with two decaying tones, a 1400 Hz high-pass filter
    /// and a gain of 0.5. Returns 16-bit mono samples.
    nonisolated static func samples() -> [Int16] {
        let rate = Double(sampleRate)
        let count = Int(rate * 0.004)
        let rc = 1 / (2 * Double.pi * 1400), dt = 1 / rate
        let a = rc / (rc + dt)
        var out: [Int16] = []
        var lastIn = 0.0, lastOut = 0.0
        for i in 0..<count {
            let t = Double(i) / rate
            let impulse = i < 2 ? 0.9 : 0
            let high = sin(2 * .pi * 4300 * t) * exp(-t / 0.00055) * 0.75
            let low = sin(2 * .pi * 1850 * t) * exp(-t / 0.00025) * 0.35
            let x = min(max(impulse + high + low, -1), 1)
            let y = a * (lastOut + x - lastIn)  // one-pole high-pass
            lastIn = x; lastOut = y
            out.append(Int16(min(max(y * 0.5, -1), 1) * Double(Int16.max)))
        }
        return out
    }

    /// The samples as a WAV file in memory, for NSSound.
    nonisolated static func wav() -> Data {
        let pcm = samples()
        var data = Data()
        func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(pcm.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); put(36 + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); put(UInt32(16))
        put(UInt16(1)); put(UInt16(1))  // PCM, mono
        put(UInt32(sampleRate)); put(UInt32(sampleRate * 2))  // sample rate, bytes per second
        put(UInt16(2)); put(UInt16(16))  // bytes per frame, bits per sample
        data.append(contentsOf: Array("data".utf8)); put(bytes)
        for sample in pcm { put(sample) }
        return data
    }
}
