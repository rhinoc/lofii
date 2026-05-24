import SwiftUI

/// Shared snow + dark-field timing for scene and media switches.
enum TransitionSnowStyle {
    // MARK: Snow opacity

    /// Opacity ramp when snow appears.
    static let fadeInDuration: TimeInterval = 0.18
    /// Time at ~full snow opacity after content is ready.
    static let plateauAfterContentChange: TimeInterval = 0.30

    // MARK: Dark field (brief blackout / projector-style dip)

    static let darkFieldPeakOpacity: Double = 0.92
    static let darkFieldFadeInDuration: TimeInterval = 0.15
    static let darkFieldHoldDuration: TimeInterval = 0.10
    static let darkFieldFadeOutDuration: TimeInterval = 0.22

    @MainActor
    static func fadeInSnowOpacity(_ setOpacity: @escaping (Double) -> Void) {
        setOpacity(0)
        withAnimation(.easeOut(duration: fadeInDuration)) {
            setOpacity(1)
        }
    }

    /// Black field rises over the snow, snow is removed while covered, then black lifts to reveal content.
    @MainActor
    static func darkFieldCoverThenClearSnow(
        setDarkField: @escaping (Double) -> Void,
        clearSnowURL: @escaping () -> Void,
        resetSnowOpacity: @escaping () -> Void
    ) async {
        withAnimation(.easeIn(duration: darkFieldFadeInDuration)) {
            setDarkField(darkFieldPeakOpacity)
        }
        try? await Task.sleep(nanoseconds: UInt64(darkFieldFadeInDuration * 1_000_000_000))
        try? await Task.sleep(nanoseconds: UInt64(darkFieldHoldDuration * 1_000_000_000))
        clearSnowURL()
        resetSnowOpacity()
        withAnimation(.easeOut(duration: darkFieldFadeOutDuration)) {
            setDarkField(0)
        }
        try? await Task.sleep(nanoseconds: UInt64(darkFieldFadeOutDuration * 1_000_000_000))
    }
}
