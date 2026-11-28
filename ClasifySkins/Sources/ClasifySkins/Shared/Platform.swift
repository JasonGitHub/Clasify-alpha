import SwiftUI
#if os(macOS)
import AppKit

/// CLA-202: the image and font types of the platform. On the Mac they are AppKit's, so the Mac
/// code makes the same calls as before.
typealias PlatformImage = NSImage
typealias PlatformFont = NSFont

extension Image {
    init(platformImage: PlatformImage) { self.init(nsImage: platformImage) }
}

extension PlatformImage {
    /// A bundled PNG.
    static func png(at url: URL) -> PlatformImage? { NSImage(contentsOf: url) }
}
#else
import UIKit

typealias PlatformImage = UIImage
typealias PlatformFont = UIFont

extension Image {
    init(platformImage: PlatformImage) { self.init(uiImage: platformImage) }
}

extension PlatformImage {
    /// A bundled PNG.
    static func png(at url: URL) -> PlatformImage? { UIImage(contentsOfFile: url.path) }
}
#endif

extension View {
    /// The device's keys, taken at the window level (`KeyCatcher`). CLA-202: Mac only; on iOS
    /// it does nothing.
    func catchesKeys(_ on: Bool, _ onKey: @escaping @MainActor (KeyEquivalent, _ repeated: Bool) -> Bool) -> some View {
        #if os(macOS)
        return background { if on { KeyCatcher(onKey: onKey) } }
        #else
        return self
        #endif
    }

    /// Trackpad and mouse-wheel scrolling as wheel detents (`ScrollCatcher`). CLA-202: Mac only;
    /// on iOS it does nothing.
    func catchesScroll(_ on: Bool, _ onDetent: @escaping @MainActor (Int) -> Void) -> some View {
        #if os(macOS)
        return background { if on { ScrollCatcher(onDetent: onDetent) } }
        #else
        return self
        #endif
    }
}
