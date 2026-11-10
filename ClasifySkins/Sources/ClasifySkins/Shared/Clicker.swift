import AppKit

/// The click that the wheel and the buttons make when the Clicker setting is on.
/// It is the N24 click, made in memory from a table of numbers. Nothing is written to disk.
@MainActor
public final class Clicker {
    public static let shared = Clicker()

    private let sound = NSSound(data: Clicker.wav())

    public func click() {
        // A copy, so a fast turn of the wheel can play clicks that overlap.
        (sound?.copy() as? NSSound)?.play()
    }

    nonisolated static let sampleRate = 44_100

    /// The N24 click (CLA-87, Jason approved 2026-11-10 21:52 JST): 24 damped sine modes, fitted
    /// to a recording of a real click wheel. Each mode is
    /// (sin · sin 2πfτ + cos · cos 2πfτ) · e^(−τ / decay), with τ = t − start, and 0 before start.
    /// Times in the table are in milliseconds. The fit was made at 48 kHz, but t is in seconds,
    /// so the sum works at any sample rate.
    nonisolated static let modes: [(freq: Double, decay: Double, start: Double, sin: Double, cos: Double)] = [
        (5466.094, 2.0, 0.0, -0.034104926, 0.012543953),
        (4843.477, 0.5, 1.0833, 0.082100485, 0.23688523),
        (5579.648, 2.0, 0.5417, -0.12120239, 0.11858789),
        (3978.398, 0.5, 0.5417, 0.42106389, 0.094172305),
        (5266.875, 2.0, 0.0, -0.3187809, 0.013414332),
        (7094.297, 0.8, 0.5417, -0.090198074, -0.00094888167),
        (5581.758, 3.0, 0.0, 0.037737431, -0.050732058),
        (1850.742, 1.2, 0.0, 0.020342489, -0.023383024),
        (3995.977, 0.8, 1.0833, -0.031467745, -0.11416756),
        (2970.586, 0.2, 0.5417, -0.14526883, -0.1614728),
        (5263.945, 3.0, 1.0833, -0.057661, -0.098248513),
        (3541.992, 2.0, 0.0, -0.013889274, -0.023649778),
        (5534.883, 1.2, 0.0, 0.30049462, 0.10773596),
        (58.711, 2.0, 0.0, 0.022151353, -0.0074022469),
        (4817.109, 3.0, 0.5417, -0.011179509, -0.0075742991),
        (7136.719, 2.0, 0.0, 0.021955387, 0.0011786142),
        (5352.539, 5.0, 0.5417, -0.0056676113, -0.0088210317),
        (2616.211, 0.8, 0.5417, 0.036331536, -0.022587552),
        (9839.297, 0.8, 0.5417, -0.0045209919, -0.018289717),
        (5940.586, 2.0, 1.0833, -0.0007974394, -0.010551631),
        (6618.047, 0.8, 1.0833, 0.016739293, -0.010460895),
        (4491.211, 2.0, 0.0, -0.015288144, 0.011633289),
        (5260.195, 12.0, 1.0833, 0.0054601935, 0.0051602339),
        (1758.516, 3.0, 1.0833, -0.001542385, -0.0039482167),
    ]

    /// The click is 11.979 ms long.
    nonisolated static let length = 0.011979
    /// A linear fade to 0 over the last 2 ms.
    nonisolated static let fade = 0.002

    /// The sum of the modes at t seconds, before the fade and the gain.
    nonisolated static func wave(at t: Double) -> Double {
        modes.reduce(0.0) { sum, mode in
            let tau = t - mode.start / 1000
            guard tau >= 0 else { return sum }
            let phase = 2 * Double.pi * mode.freq * tau
            return sum + (mode.sin * sin(phase) + mode.cos * cos(phase)) * exp(-tau / (mode.decay / 1000))
        }
    }

    /// The click with the fade, scaled so the peak is 0.5, as the old click's gain. Returns 16-bit
    /// mono samples.
    nonisolated static func samples() -> [Int16] {
        let rate = Double(sampleRate)
        let count = Int(rate * length), fadeCount = Double(Int(rate * fade))
        let levels = (0..<count).map { i in
            wave(at: Double(i) / rate) * min(1, Double(count - 1 - i) / fadeCount)
        }
        let gain = 0.5 / (levels.map { abs($0) }.max() ?? 1)
        return levels.map { Int16(($0 * gain * Double(Int16.max)).rounded()) }
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
