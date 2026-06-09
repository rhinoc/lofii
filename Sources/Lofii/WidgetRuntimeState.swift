import Foundation

struct WidgetVisibilitySnapshot: Equatable {
    var isOrderedVisible: Bool
    var isMiniaturized: Bool
    var isOcclusionVisible: Bool
    var isFullscreen: Bool
    var isFullscreenTransitioning: Bool

    static let visible = WidgetVisibilitySnapshot(
        isOrderedVisible: true,
        isMiniaturized: false,
        isOcclusionVisible: true,
        isFullscreen: false,
        isFullscreenTransitioning: false
    )

    var isWindowPresent: Bool {
        isOrderedVisible && !isMiniaturized
    }

    var allowsFullRateVisualRendering: Bool {
        isWindowPresent && (isOcclusionVisible || isFullscreen || isFullscreenTransitioning)
    }

    var diagnosticSummary: String {
        "ordered=\(isOrderedVisible) mini=\(isMiniaturized) occlusion=\(isOcclusionVisible) fullscreen=\(isFullscreen) transitioning=\(isFullscreenTransitioning)"
    }
}

enum BongoRenderLoopIntent: Equatable {
    case stopped
    case throttled(framesPerSecond: Int)
    case continuous

    var isActive: Bool {
        switch self {
        case .stopped:
            return false
        case .throttled, .continuous:
            return true
        }
    }

    func resolvedFramesPerSecond(default defaultFramesPerSecond: Int) -> Int {
        switch self {
        case .stopped, .continuous:
            return defaultFramesPerSecond
        case .throttled(let framesPerSecond):
            return framesPerSecond
        }
    }
}

enum BongoAnimationIntent: Equatable {
    case paused
    case fullMotion

    var advancesClock: Bool {
        self == .fullMotion
    }
}

enum BongoInputIntent: Equatable {
    case disabled
    case fullKeyboardMouse

    var monitorEnabled: Bool {
        self == .fullKeyboardMouse
    }
}

struct BongoRuntimeIntent: Equatable {
    var renderLoop: BongoRenderLoopIntent
    var animation: BongoAnimationIntent
    var input: BongoInputIntent

    static let active = BongoRuntimeIntent(
        renderLoop: .continuous,
        animation: .fullMotion,
        input: .fullKeyboardMouse
    )

    init(visibility: WidgetVisibilitySnapshot) {
        if visibility.isWindowPresent {
            renderLoop = visibility.allowsFullRateVisualRendering
                ? .continuous
                : .throttled(framesPerSecond: 12)
            animation = .fullMotion
            input = .fullKeyboardMouse
        } else {
            renderLoop = .stopped
            animation = .paused
            input = .disabled
        }
    }

    init(
        renderLoop: BongoRenderLoopIntent,
        animation: BongoAnimationIntent,
        input: BongoInputIntent
    ) {
        self.renderLoop = renderLoop
        self.animation = animation
        self.input = input
    }
}
