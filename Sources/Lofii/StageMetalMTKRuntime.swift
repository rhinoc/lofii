import AppKit
import MetalKit

/// Shared MTKView runtime policy for every widget Metal stage (`StageMetalPlayerView`,
/// `BongoUnifiedMetalView`). Keeps display-link / pause behavior identical so performance
/// tuning happens in one place.
enum StageMetalMTKRuntime {
    /// Hard ceiling for `preferredFramesPerSecond` on in-app MTK stages.
    static let displayMaximumFramesPerSecond = 60

    /// Clamp user- or preset-driven refresh rates to what MTKView accepts on this platform.
    static func clampedPreferredFramesPerSecond(_ requested: Int) -> Int {
        min(max(requested, 1), displayMaximumFramesPerSecond)
    }

    /// Initial MTKView setup shared by standalone GIF/video stages and the Bongo unified stage.
    @MainActor
    static func applyBasePresentation(to view: MTKView, framebufferOnly: Bool) {
        view.preferredFramesPerSecond = displayMaximumFramesPerSecond
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.framebufferOnly = framebufferOnly
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.colorPixelFormat = .bgra8Unorm
        view.layer?.isOpaque = true
        view.layer?.backgroundColor = NSColor.black.cgColor
    }

    /// Tie MTKView’s display link to logical playback: when paused, stop continuous draws and
    /// paint one last frame (GIF decode quiesce, motion-blur history settle, etc.).
    @MainActor
    static func syncDrawLoopToPlayback(view: MTKView?, isPlaying: Bool) {
        view?.isPaused = !isPlaying
        view?.enableSetNeedsDisplay = !isPlaying
        if !isPlaying {
            view?.draw()
        }
    }
}
