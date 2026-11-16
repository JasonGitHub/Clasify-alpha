import ClasifyCore
import SwiftUI
import Testing

@testable import ClasifySkins

/// CLA-119 (build 269: the centre black, or white, as a color spin started): during a spin the
/// 2D device shows the old color, exactly, though the state already has the new one. Both ways.
/// (The fix itself is that the spin starts in the same update as the color step, in the app's
/// `K3DSpikeSkin`; this checks the frame that update draws.)
@Suite @MainActor struct K3DSpinColorTests {
    func picture(_ color: DeviceColor, spinOld: Bool?) throws -> [UInt8] {
        var state = AppState()
        state.deviceColor = color
        let image = try #require(K3DSpike.snapshot(state, wheel: WheelLook(), black: spinOld))
        return try #require(K3DTextures.picture(image))
    }

    @Test(arguments: [(DeviceColor.silver, DeviceColor.black), (.black, .silver)])
    func theFirstSpinFrameHasTheOldColor(_ colors: (DeviceColor, DeviceColor)) throws {
        let (old, new) = colors
        let spin = try picture(new, spinOld: old == .black)
        let still = try picture(old, spinOld: nil)
        #expect(spin.count == still.count)
        // The centre button (the wheel's center, about 467 pt down, 2 px per pt) and the body.
        for (x, y) in [(366, 867), (366, 890), (20, 700), (20, 1200)] {
            let i = (y * 732 + x) * 4
            #expect(Array(spin[i..<(i + 4)]) == Array(still[i..<(i + 4)]), "\(old) to \(new) at \(x), \(y)")
        }
    }
}
