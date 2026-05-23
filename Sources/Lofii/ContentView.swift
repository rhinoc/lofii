import SwiftUI
import AppKit
import CoreGraphics

/// Compute the padding the readout badge needs at each of the nine
/// anchor positions. We center-anchored positions get a small uniform
/// breathing margin; edge-anchored positions get a chrome-aware bottom/
/// top inset so they never collide with the transport dock or the close
/// row when those reveal on hover.
@MainActor
private func badgeEdgeInsets(
    position: BadgePosition,
    compact: Bool,
    chromeVisible: Bool
) -> EdgeInsets {
    // Reserved heights for the chrome strips at the top and bottom of
    // the widget. Bottom dock is roughly 30pt tall + its own padding;
    // top chrome is roughly TopChrome.rowHeight tall + its own padding.
    // We leave a small extra gap so the badge's bloom doesn't bleed
    // into the chrome glyphs when both are visible.
    //
    // Side padding stays at the original 12/18pt regardless of
    // anchor, so a centered or edge-anchored readout never touches
    // the rounded card corners on small windows.
    let bottomReserved: CGFloat = chromeVisible
        ? (compact ? 10 : 14) + 30 + 14
        : (compact ? 14 : 20)
    let topReserved: CGFloat = chromeVisible
        ? (compact ? 10 : 14) + TopChrome.rowHeight + 14
        : (compact ? 14 : 20)
    let side: CGFloat = compact ? 12 : 18

    switch position {
    case .topLeading, .top, .topTrailing:
        return EdgeInsets(top: topReserved, leading: side, bottom: 0, trailing: side)
    case .bottomLeading, .bottom, .bottomTrailing:
        return EdgeInsets(top: 0, leading: side, bottom: bottomReserved, trailing: side)
    case .leading, .center, .trailing:
        // Middle row: small symmetric vertical margin so a tall
        // readout doesn't kiss the chrome row when it reveals.
        let v: CGFloat = compact ? 14 : 20
        return EdgeInsets(top: v, leading: side, bottom: v, trailing: side)
    }
}

/// Keep the readout narrower than the full widget so `.leading` /
/// `.trailing` anchors have real horizontal travel. When the badge
/// itself spans the full width, the position picker can only appear to
/// move vertically because every horizontal anchor collapses into the
/// same centered layout.
@MainActor
private func badgeContentWidth(
    containerWidth: CGFloat,
    scale: CGFloat
) -> CGFloat {
    // `TrackBadge` adds glow bleed outside this content width, and the
    // top-level badge placement adds edge padding again. Account for both
    // here so the readout can shrink inside the AppKit minimum window width.
    let horizontalOutsets = (ReadoutGlowBleed.horizontal * 2) + 36
    let available = max(96, containerWidth - horizontalOutsets)
    let target = max(200, 250 * scale)
    return min(available, target)
}

@MainActor
private func badgeInnerInsets(
    compact: Bool,
    placement: BadgeHorizontalPlacement
) -> EdgeInsets {
    let centeredSide: CGFloat = 12
    let edgeDelta: CGFloat = 2

    switch placement {
    case .leading:
        return EdgeInsets(top: 0, leading: edgeDelta, bottom: 0, trailing: centeredSide)
    case .center:
        return EdgeInsets(top: 0, leading: centeredSide, bottom: 0, trailing: centeredSide)
    case .trailing:
        return EdgeInsets(top: 0, leading: centeredSide, bottom: 0, trailing: edgeDelta)
    }
}

private enum BadgeHorizontalPlacement {
    case leading
    case center
    case trailing

    var frameAlignment: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

private extension BadgePosition {
    var horizontalPlacement: BadgeHorizontalPlacement {
        switch self {
        case .topLeading, .leading, .bottomLeading:
            return .leading
        case .topTrailing, .trailing, .bottomTrailing:
            return .trailing
        case .top, .center, .bottom:
            return .center
        }
    }
}

struct WidgetRootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var hovering = false
    @State private var isFullscreen = false
    /// Drives the volume HUD's visibility directly. Earlier this was
    /// computed at render time as `Date() < volumeOverlayUntil`, but
    /// SwiftUI only re-evaluates `body` when an observed value changes
    /// — `Date()` reading the wall clock doesn't count — so once the
    /// HUD appeared it would stay on forever (or until the next hover
    /// / scroll forced an unrelated rerender). A boolean toggled by a
    /// scheduled `Task` is unambiguous and cheap.
    @State private var showVolume = false
    /// In-flight "hide HUD after delay" task. We cancel it on every new
    /// scroll tick so a quick burst of wheel events extends the
    /// dismissal window instead of stacking N independent timers that
    /// would each try to flip `showVolume` back on/off.
    @State private var volumeHideTask: Task<Void, Never>? = nil
    @State private var stationPickerOpen = false
    @State private var settingsOpen = false
    /// Snow overlay while swapping GIF stack → `SceneView` (matches other channel-flip holds).
    @State private var gifToVideoSnowURL: URL?
    @State private var gifToVideoSnowOpacity: Double = 1
    @State private var gifToVideoDarkFieldOpacity: Double = 0
    @State private var gifToVideoSnowTask: Task<Void, Never>?

    /// Shared by the top-level wheel catcher so cinematic / GIF mode can
    /// adjust volume without dedicating visible UI to it.
    private func handleVolumeScrollWheel(delta: Double) {
        let next = (model.volume + delta * 0.04).clamped(to: 0...1)
        if abs(next - model.volume) > 0.0001 {
            model.volume = next
            settingsOpen = false
            showVolume = true
            volumeHideTask?.cancel()
            volumeHideTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                if !Task.isCancelled {
                    showVolume = false
                }
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let compact = size < 520
            let badgeWidth = badgeContentWidth(
                containerWidth: geo.size.width,
                scale: model.badgeSize.scale
            )
            // While the volume HUD is up we want the screen visually clean —
            // hide the hover chrome entirely so the larger HUD pill can sit
            // wherever it wants without colliding with the dock. (Hover
            // state itself is preserved so chrome reappears the moment the
            // HUD times out.)
            //
            // We also keep chrome visible while the station picker is open:
            // the popover anchors to the grid icon inside TopChrome — if
            // we tear the chrome down the moment the user clicks, the
            // popover loses its anchor (so it never appears) AND AppKit
            // ends up stuck on the now-detached button, swallowing every
            // subsequent click.
            let chromeVisible = (hovering || stationPickerOpen) && !showVolume
            let topChromeVisible = chromeVisible && !settingsOpen && !isFullscreen
            let shouldRenderMotion = model.shouldRenderStageMotion
            // Bongo mode owns its own single Metal stage so the GIF, Live2D
            // model, key overlays, and final post pass are processed together.
            let bongoVisible = model.bongoOverlayVisible
            let backgroundCRTEnabled = model.crt.enabled && !bongoVisible
            let backgroundShatteredGlass = model.shatteredGlass.resolvedForDisplayPipeline(
                crtMasterEnabled: backgroundCRTEnabled
            )
            let backgroundCurvationActive = backgroundCRTEnabled && model.crt.curvation
            let backgroundVignetteActive = backgroundCRTEnabled && model.crt.vignette
            let backgroundCurvationUniforms = model.crt.resolvedCurvationUniforms(active: backgroundCurvationActive)
            let backgroundVignetteAlpha = model.crt.resolvedVignetteAlpha(active: backgroundVignetteActive)
            let backgroundMotionBlurEnabled = backgroundCRTEnabled && model.crt.motionBlur
            let backgroundChromaticAberrationEnabled = backgroundCRTEnabled && model.crt.chromaticAberration
            let backgroundScanlinesEnabled = backgroundCRTEnabled && model.crt.scanlines

            ZStack {
                ZStack {
                        Group {
                            switch model.visualMode {
                            case .cinematic:
                                if !bongoVisible {
                                    SceneView(
                                        asset: model.currentScene,
                                        variant: model.currentVariant,
                                        isPlaying: shouldRenderMotion,
                                        curvationFactor: backgroundCurvationUniforms.factor,
                                        curvationOverscan: backgroundCurvationUniforms.overscan,
                                        curvationBorderSize: backgroundCurvationUniforms.border,
                                        vignetteAlpha: backgroundVignetteAlpha,
                                        motionBlurEnabled: backgroundMotionBlurEnabled,
                                        motionBlurStrength: model.crt.motionBlurStrength.resolvedStrength,
                                        chromaticAberrationEnabled: backgroundChromaticAberrationEnabled,
                                        chromaticAberrationStrength: model.crt.chromaticAberrationStrength.resolvedStrength,
                                        scanlinesEnabled: backgroundScanlinesEnabled,
                                        scanlineOpacity: model.crt.scanlineOpacity.resolvedOpacity(for: model.visualMode),
                                        scanlineDensity: model.crt.scanlineDensity.pitch,
                                        shatteredGlassOpacity: backgroundShatteredGlass.opacity,
                                        shatteredGlassRefraction: backgroundShatteredGlass.refraction,
                                        shatteredGlassHighlight: backgroundShatteredGlass.highlight,
                                        shatteredGlassFlipX: model.shatteredGlass.resolvedFlipX
                                    )
                                } else {
                                    LinearGradient(
                                        colors: [
                                            model.currentScene.palette.backdropTop,
                                            model.currentScene.palette.backdropBottom,
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                }
                            case .gif:
                                if let gif = model.currentGif {
                                    ZStack {
                                        if bongoVisible {
                                            Color(white: 0.02)
                                        } else {
                                            GifSceneView(
                                                asset: gif,
                                                isPlaying: shouldRenderMotion,
                                                curvationFactor: backgroundCurvationUniforms.factor,
                                                curvationOverscan: backgroundCurvationUniforms.overscan,
                                                curvationBorderSize: backgroundCurvationUniforms.border,
                                                vignetteAlpha: backgroundVignetteAlpha,
                                                motionBlurEnabled: backgroundMotionBlurEnabled,
                                                motionBlurStrength: model.crt.motionBlurStrength.resolvedStrength,
                                                chromaticAberrationEnabled: backgroundChromaticAberrationEnabled,
                                                chromaticAberrationStrength: model.crt.chromaticAberrationStrength.resolvedStrength,
                                                scanlinesEnabled: backgroundScanlinesEnabled,
                                                scanlineOpacity: model.crt.scanlineOpacity.resolvedOpacity(for: model.visualMode),
                                                scanlineDensity: model.crt.scanlineDensity.pitch,
                                                shatteredGlassOpacity: backgroundShatteredGlass.opacity,
                                                shatteredGlassRefraction: backgroundShatteredGlass.refraction,
                                                shatteredGlassHighlight: backgroundShatteredGlass.highlight,
                                                shatteredGlassFlipX: model.shatteredGlass.resolvedFlipX,
                                                onAnimatedGifReady: {
                                                    model.markPrimaryVisualMediaReady()
                                                }
                                            )
                                        }
                                    }
                                } else {
                                    SceneView(
                                        asset: model.currentScene,
                                        variant: model.currentVariant,
                                        isPlaying: shouldRenderMotion,
                                        curvationFactor: backgroundCurvationUniforms.factor,
                                        curvationOverscan: backgroundCurvationUniforms.overscan,
                                        curvationBorderSize: backgroundCurvationUniforms.border,
                                        vignetteAlpha: backgroundVignetteAlpha,
                                        motionBlurEnabled: backgroundMotionBlurEnabled,
                                        motionBlurStrength: model.crt.motionBlurStrength.resolvedStrength,
                                        chromaticAberrationEnabled: backgroundChromaticAberrationEnabled,
                                        chromaticAberrationStrength: model.crt.chromaticAberrationStrength.resolvedStrength,
                                        scanlinesEnabled: backgroundScanlinesEnabled,
                                        scanlineOpacity: model.crt.scanlineOpacity.resolvedOpacity(for: model.visualMode),
                                        scanlineDensity: model.crt.scanlineDensity.pitch,
                                        shatteredGlassOpacity: backgroundShatteredGlass.opacity,
                                        shatteredGlassRefraction: backgroundShatteredGlass.refraction,
                                        shatteredGlassHighlight: backgroundShatteredGlass.highlight,
                                        shatteredGlassFlipX: model.shatteredGlass.resolvedFlipX
                                    )
                                }
                            case .cover:
                                if bongoVisible {
                                    Color(white: 0.02)
                                } else {
                                    TrackCoverSceneView(
                                        track: model.currentTrack,
                                        curvationFactor: backgroundCurvationUniforms.factor,
                                        curvationOverscan: backgroundCurvationUniforms.overscan,
                                        curvationBorderSize: backgroundCurvationUniforms.border,
                                        vignetteAlpha: backgroundVignetteAlpha,
                                        motionBlurEnabled: backgroundMotionBlurEnabled,
                                        motionBlurStrength: model.crt.motionBlurStrength.resolvedStrength,
                                        chromaticAberrationEnabled: backgroundChromaticAberrationEnabled,
                                        chromaticAberrationStrength: model.crt.chromaticAberrationStrength.resolvedStrength,
                                        scanlinesEnabled: backgroundScanlinesEnabled,
                                        scanlineOpacity: model.crt.scanlineOpacity.resolvedOpacity(for: model.visualMode),
                                        scanlineDensity: model.crt.scanlineDensity.pitch,
                                        shatteredGlassOpacity: backgroundShatteredGlass.opacity,
                                        shatteredGlassRefraction: backgroundShatteredGlass.refraction,
                                        shatteredGlassHighlight: backgroundShatteredGlass.highlight,
                                        shatteredGlassFlipX: model.shatteredGlass.resolvedFlipX,
                                        onCoverReady: {
                                            model.markPrimaryVisualMediaReady()
                                        }
                                    )
                                    .environmentObject(model)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if bongoVisible {
                            BongoView(
                                isPlaying: shouldRenderMotion,
                                artworkScrollWheel: handleVolumeScrollWheel,
                                artworkContextMenu: { [weak model] in
                                    guard let model else { return NSMenu() }
                                    return SettingsContextMenu.build(model: model)
                                }
                            )
                        }

                        if !model.visualStageReady,
                           model.bongoOverlayVisible || model.visualMode == .gif || model.visualMode == .cover,
                           !(bongoVisible && model.visualMode == .cover) {
                            WorkspaceSnowLoadingCover()
                        }

                        if let gifToVideoSnowURL {
                            SnowOverlayView(url: gifToVideoSnowURL)
                                .opacity(gifToVideoSnowOpacity)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .allowsHitTesting(false)
                        }

                        Color.black
                            .opacity(gifToVideoDarkFieldOpacity)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)

                        if hovering && !isFullscreen {
                            // Top/bottom darkening only while the pointer is over the
                            // widget so chrome and TrackBadge stay legible on bright
                            // frames without a permanent overlay. In fullscreen the
                            // pointer is always inside the window, so keep this off.
                            LinearGradient(
                                colors: [
                                    .black.opacity(0.45),
                                    .black.opacity(0.0),
                                    .black.opacity(0.55),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .allowsHitTesting(false)
                        }
                    }
                    .onChange(of: model.visualMode) { oldValue, newValue in
                        gifToVideoSnowTask?.cancel()
                        gifToVideoSnowTask = nil
                        if oldValue == .gif, newValue == .cinematic {
                            gifToVideoSnowOpacity = 0
                            gifToVideoSnowURL = GifCache.bundledSnowOverlayURL()
                            gifToVideoSnowTask = Task { @MainActor in
                                defer { gifToVideoSnowTask = nil }
                                TransitionSnowStyle.fadeInSnowOpacity { gifToVideoSnowOpacity = $0 }
                                if let pick = await GifCache.shared.randomCachedStatic() {
                                    gifToVideoSnowURL = pick
                                }
                                try? await Task.sleep(
                                    nanoseconds: UInt64(
                                        TransitionSnowStyle.plateauAfterContentChange * 1_000_000_000
                                    )
                                )
                                guard !Task.isCancelled else { return }
                                guard model.visualMode == .cinematic else { return }
                                await TransitionSnowStyle.darkFieldCoverThenClearSnow(
                                    setDarkField: { gifToVideoDarkFieldOpacity = $0 },
                                    clearSnowURL: { gifToVideoSnowURL = nil },
                                    resetSnowOpacity: { gifToVideoSnowOpacity = 1 }
                                )
                            }
                        } else if newValue != .cinematic {
                            gifToVideoSnowTask?.cancel()
                            gifToVideoSnowTask = nil
                            gifToVideoDarkFieldOpacity = 0
                            gifToVideoSnowOpacity = 1
                            gifToVideoSnowURL = nil
                        }
                    }

                // The scroll-wheel volume HUD AND the right-click
                // settings menu both live on this transparent NSView.
                // Putting them on the same hit target means they share a
                // hit zone (anything not covered by chrome/badge), so
                // users get the menu by right-clicking the artwork
                // exactly the way they get the volume HUD by scrolling
                // it — no weird "right-click only works in the corner"
                // dead zone.
                WheelAndContextCatcher(
                    onDelta: handleVolumeScrollWheel,
                    menuBuilder: { [weak model] in
                        guard let model else { return NSMenu() }
                        return SettingsContextMenu.build(model: model)
                    },
                    bongoOverlayVisible: bongoVisible,
                    bongoLive2DStageFrame: bongoVisible
                        ? BongoLive2DHitGeometry.appKitLive2DStageFrame(
                            in: geo.size,
                            maxStageSize: model.bongoCatPack.maxLogicalStageSize(scaledBy: model.bongoStageScaleTier),
                            placement: model.bongoStagePlacement,
                            maxFittedStageHeightFractionOfContainer: model.bongoStageScaleTier
                                .maxFittedStageHeightFractionOfContainer,
                            crt: model.crt
                        )
                        : .zero
                )
                .id(
                    model.bongoOverlayVisible
                        ? "wheelAndContextCatch"
                        : "wheelCatch"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(true)

                // TrackBadge is always visible now (no background card, just
                // glowing pixel text on top of the artwork). It sits in a
                // ZStack with `.frame(alignment:)` driven by the user-
                // chosen `badgePosition` (default `.bottom` matches the
                // pre-menu layout), so the same view can snap to any of
                // the canonical 9 anchor points without per-position
                // layout code.
                //
                // The dynamic bottom padding (so the readout slides up
                // when the chrome reveals to clear the transport dock)
                // is now applied only to anchors that actually overlap
                // the dock. Top/middle anchors don't move when the
                // chrome appears.
                ZStack {
                    if model.isReadoutVisible && !settingsOpen {
                        TrackBadge(
                            width: badgeWidth,
                            position: model.badgePosition,
                            compact: compact,
                            isVisible: !showVolume && model.isWidgetVisible
                        )
                            .environmentObject(model)
                            .padding(badgeEdgeInsets(
                                position: model.badgePosition,
                                compact: compact,
                                chromeVisible: topChromeVisible
                            ))
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: model.badgePosition.alignment
                )
                .opacity(showVolume ? 0 : 1)
                .animation(.easeInOut(duration: 0.22), value: chromeVisible)
                .animation(.easeInOut(duration: 0.22), value: model.isReadoutVisible)
                .animation(.easeInOut(duration: 0.22), value: model.badgePosition)
                .allowsHitTesting(false)

                if chromeVisible {
                    VStack(spacing: 0) {
                        if topChromeVisible {
                            TopChrome(
                                compact: compact,
                                stationPickerOpen: $stationPickerOpen,
                                settingsOpen: $settingsOpen
                            )
                                .environmentObject(model)
                                .padding(.horizontal, compact ? 10 : 14)
                                .padding(.top, compact ? 10 : 14)
                        }

                        Spacer(minLength: 0)

                        if !settingsOpen {
                            BottomDock(compact: compact)
                                .environmentObject(model)
                                .padding(.horizontal, compact ? 10 : 16)
                                .padding(.bottom, compact ? 10 : 14)
                        }
                    }
                    .transition(.opacity)
                }

                if showVolume {
                    // Centered pill — chrome is hidden while we're up so we
                    // can dominate the frame without worrying about the dock
                    // or badge underneath.
                    VolumeOverlay(volume: model.volume, accent: model.accent)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .allowsHitTesting(false)
                }

                if settingsOpen && !showVolume {
                    SettingsOverlay(
                        compact: compact,
                        close: { settingsOpen = false }
                    )
                    .environmentObject(model)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .zIndex(10)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Color.black.opacity(0.001).contentShape(Rectangle()))
            // The rounded corner + hairline border are applied directly to the
            // NSWindow's contentView layer (see WindowConfigurator), so SwiftUI
            // does not paint its own clipShape/overlay here. That keeps the
            // window edge and the visible card edge perfectly aligned at every
            // size — no thin transparent gap between them.
            .onHover { isHovering in
                withAnimation(.easeOut(duration: 0.18)) {
                    hovering = isHovering
                }
            }
            .onAppear { syncFullscreenState() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
                syncFullscreenState()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
                syncFullscreenState()
            }
            .animation(.easeInOut(duration: 0.25), value: model.currentPreset.id)
            .animation(.easeInOut(duration: 0.18), value: chromeVisible)
            .animation(.easeInOut(duration: 0.18), value: showVolume)
            .frame(minWidth: 200, minHeight: 130)
        }
        .frame(minWidth: 200, minHeight: 130)
    }

    private func syncFullscreenState() {
        if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { !($0 is NSPanel) }) {
            isFullscreen = window.styleMask.contains(.fullScreen)
        }
    }
}

// MARK: - Top Chrome
//
// All controls are now "icon-only" — no pill backgrounds, no rings — sitting
// directly on top of the artwork. To keep them legible against bright
// frames we lean on:
//   * a soft black drop shadow on every glyph,
//   * SF Symbol "fill" weights, and
//   * subtle hover scale + color shifts.
//
// The close button stays at the standard macOS traffic-light size (12pt) and
// the rest are sized just slightly larger so the row reads as one family
// without the close button looking out of proportion.

private struct TopChrome: View {
    @EnvironmentObject private var model: AppModel
    let compact: Bool
    @Binding var stationPickerOpen: Bool
    @Binding var settingsOpen: Bool

    /// Reserved height for the row, sized to the largest visible control so
    /// nothing in the layout below shifts when content swaps in/out.
    static let rowHeight: CGFloat = 18

    var body: some View {
        HStack(spacing: 8) {
            // Don't rely on `NSApp.keyWindow` — when the user clicks any
            // chrome control on a non-key widget, keyWindow is either nil
            // or some other app's window (so .close() / .toggleFullScreen
            // would silently no-op). Both helpers below resolve to our
            // widget by walking NSApp.windows instead.
            CloseDot(action: { WidgetFullscreenCoordinator.closeWidget() })

            // Sit a green "zoom" dot right next to the red close so the
            // pair reads like the standard macOS traffic-light cluster.
            // The coordinator strips `.canJoinAllSpaces` for the duration
            // of the toggle (AppKit refuses fullscreen on
            // canJoinAllSpaces windows) — see WidgetFullscreenCoordinator
            // in LofiiApp.swift.
            FullscreenDot(action: {
                WidgetFullscreenCoordinator.toggleFullscreen()
            })
            .padding(.trailing, 2)

            IconChromeButton(
                glyph: model.visualMode.glyph,
                action: model.toggleVisualMode
            )
            .help("Visual mode: \(model.visualMode.label)")

            if model.visualMode == .cinematic {
                IconChromeButton(
                    glyph: model.currentVariant.glyph,
                    action: model.cycleVariant
                )
                .help("Variant: \(model.currentVariant.label)")
            } else if model.visualMode == .gif {
                IconChromeButton(
                    glyph: .shuffle,
                    action: model.nextGif
                )
                .help("Next GIF (G)")
            }

            Spacer(minLength: 0)

            // Station picker — replaces the old always-visible 8-dot preset
            // row at the bottom of the dock. We surface a single radio icon
            // here that pops a 2-column grid on demand, so the resting UI
            // only ever shows prev/play/next + the current station name in
            // the badge below.
            IconChromeButton(
                glyph: .radioSignal,
                tint: stationPickerOpen ? model.accent : nil,
                action: { stationPickerOpen.toggle() }
            )
            .help("Pick a station")
            .popover(isPresented: $stationPickerOpen, arrowEdge: .top) {
                StationPicker()
                    .environmentObject(model)
            }

            IconChromeButton(
                glyph: .sliders,
                tint: settingsOpen ? model.accent : nil,
                action: { settingsOpen.toggle() }
            )
            .help("Settings")

            IconChromeButton(
                glyph: .pin,
                tint: model.alwaysOnTop ? model.accent : nil,
                action: { model.alwaysOnTop.toggle() }
            )
            .help(model.alwaysOnTop ? "Pinned on top" : "Pin on top")
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.rowHeight)
    }
}

/// Popover-hosted station grid. We keep it dense (2 columns) so even with
/// 8+ presets the picker stays a tidy short rectangle that doesn't feel
/// like a full menu.
///
/// We deliberately paint our own near-black background (and zero out the
/// system's `.popoverBox` material via `presentationBackground`). Without
/// this the popover defaults to a light/translucent `NSVisualEffectView`,
/// which on top of our dark widget reads as washed-out grey and crushes
/// the white pixel text into illegibility.
private struct StationPicker: View {
    @EnvironmentObject private var model: AppModel

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(model.presets.enumerated()), id: \.element.id) { index, preset in
                let selected = index == model.selectedIndex
                Button {
                    model.selectPreset(at: index)
                } label: {
                    HStack(spacing: 8) {
                        PixelIcon(preset.scene.glyph, size: 12)
                            .foregroundStyle(selected ? .black : preset.scene.palette.accent)
                            .frame(width: 20, height: 20)
                            .background(
                                Rectangle().fill(
                                    selected
                                        ? preset.scene.palette.accent
                                        : Color.white.opacity(0.10)
                                )
                            )

                        Text(preset.displayName.uppercased())
                            .font(.pixel(size: 13))
                            .kerning(0.5)
                            .foregroundStyle(selected ? .white : .white.opacity(0.92))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        // Sharp 1px-style fill (no rounded corners, no blur)
                        // so the row reads as pixel/CRT chrome rather than
                        // a soft macOS list cell.
                        Rectangle().fill(
                            selected
                                ? preset.scene.palette.accent.opacity(0.22)
                                : Color.white.opacity(0.04)
                        )
                    )
                    .overlay(
                        Rectangle().stroke(
                            selected
                                ? preset.scene.palette.accent
                                : Color.white.opacity(0.10),
                            lineWidth: 1
                        )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 320)
        // Force a dark, opaque base so the system's translucent popover
        // material doesn't bleed through and grey out our text.
        .background(Color(red: 0.06, green: 0.06, blue: 0.08))
        .presentationBackground(Color(red: 0.06, green: 0.06, blue: 0.08))
    }
}

/// macOS-style traffic-light close dot. Sized to the system's standard 12pt
/// so it reads as a "real" close button instead of a custom widget. The X
/// glyph stays hidden until hover, matching the system convention.
///
/// Glyph is a pixel icon (not SF Symbol) so the whole chrome family feels
/// hand-drawn on the same grid. At 9pt it's small but pixelarticons stays
/// legible because the close mark is just a thick X.
private struct CloseDot: View {
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(red: 1.0, green: 0.37, blue: 0.36))
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)

                PixelIcon(.close, size: 9)
                    .foregroundStyle(.black.opacity(0.7))
                    .opacity(hovering ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Close")
    }
}

/// macOS-style traffic-light "zoom" dot — green circle that toggles the
/// window's native fullscreen state. Mirrors `CloseDot`'s sizing/glyph
/// reveal-on-hover behavior so the two read as a single traffic-light pair.
///
/// Pixelarticons doesn't have inward / outward arrow pairs, so we reuse
/// `expand` for "enter fullscreen" and `scale` for "exit fullscreen" —
/// `scale` reads as "fit/size to box" which is close enough to "exit
/// fullscreen back to the small widget". Tooltip carries the literal
/// meaning regardless.
private struct FullscreenDot: View {
    let action: () -> Void

    @State private var hovering = false
    @State private var isFullscreen = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.27, green: 0.78, blue: 0.27))
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)

                PixelIcon(isFullscreen ? .scale : .expand, size: 9)
                    .foregroundStyle(.black.opacity(0.7))
                    .opacity(hovering ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isFullscreen ? "Exit Full Screen" : "Enter Full Screen")
        // Listen for native fullscreen transitions so the glyph flips even
        // when the user uses the menu shortcut (⌃⌘F) or a Mission Control
        // gesture instead of clicking our dot.
        .onAppear { syncFullscreenState() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullscreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullscreen = false
        }
    }

    private func syncFullscreenState() {
        if let window = NSApp.keyWindow ?? NSApp.windows.first {
            isFullscreen = window.styleMask.contains(.fullScreen)
        }
    }
}

/// Borderless, icon-only chrome button. Sits flush on the artwork — no
/// pill background, no ring — relying on a drop shadow for legibility.
/// Tooltips (`.help`) carry the meaning that a text label used to.
///
/// Uses `PixelIcon` (from `PixelIcons.swift`) so the glyph matches the
/// Doto readout text instead of the smooth SF Symbol look.
private struct IconChromeButton: View {
    let glyph: PixelGlyph
    /// Optional accent override. When set (e.g. pin = on), the glyph
    /// adopts this color; otherwise we use white.
    var tint: Color? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            PixelIcon(glyph, size: 16)
                .foregroundStyle(foreground)
                .shadow(color: .black.opacity(0.55), radius: 2, y: 0.5)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    /// macOS toolbar idiom: rest at ~75% white, brighten to full white on
    /// hover. No scale, no glow — just a tone change so the affordance is
    /// felt without anything moving.
    private var foreground: Color {
        if let tint {
            return hovering ? tint : tint.opacity(0.85)
        }
        return hovering ? .white : .white.opacity(0.75)
    }
}

// MARK: - Track Badge

/// Outsets so `GlowShadowStack` (up to ~6pt radius) is not clipped by the
/// readout `frame(width:)` or `MarqueePixelText` layout bounds.
private enum ReadoutGlowBleed {
    static let horizontal: CGFloat = 10
    static let vertical: CGFloat = 8
}

/// When `AppModel.debugModeEnabled` is on, repeat title/artist fragments so
/// the marquee path is easy to exercise without long station metadata.
private func marqueeStretchForDebug(_ raw: String, enabled: Bool) -> String {
    guard enabled else { return raw }
    return String(repeating: raw + " · ", count: 28) + " ⟦DEBUG⟧"
}

private struct TrackCoverSceneView: View {
    @EnvironmentObject private var model: AppModel
    let track: LiveTrack?
    let curvationFactor: Double
    let curvationOverscan: Double
    let curvationBorderSize: Double
    let vignetteAlpha: Double
    let motionBlurEnabled: Bool
    let motionBlurStrength: Double
    let chromaticAberrationEnabled: Bool
    let chromaticAberrationStrength: Double
    let scanlinesEnabled: Bool
    let scanlineOpacity: Double
    let scanlineDensity: Double
    let shatteredGlassOpacity: Double
    let shatteredGlassRefraction: Double
    let shatteredGlassHighlight: Double
    let shatteredGlassFlipX: Double
    let onCoverReady: (@MainActor () -> Void)?

    @State private var localURL: URL?
    @State private var loadError: String?
    @State private var firstFrameReadyURL: URL?

    private var artworkKey: String {
        track?.image?.absoluteString ?? "no-cover"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.035), Color(white: 0.11)],
                startPoint: .top,
                endPoint: .bottom
            )

            if let localURL {
                StageMetalPlayerView(
                    source: .image(localURL),
                    isPlaying: true,
                    curvationFactor: curvationFactor,
                    curvationOverscan: curvationOverscan,
                    curvationBorderSize: curvationBorderSize,
                    vignetteAlpha: vignetteAlpha,
                    motionBlurEnabled: motionBlurEnabled,
                    motionBlurStrength: motionBlurStrength,
                    chromaticAberrationEnabled: chromaticAberrationEnabled,
                    chromaticAberrationStrength: chromaticAberrationStrength,
                    scanlinesEnabled: scanlinesEnabled,
                    scanlineOpacity: scanlineOpacity,
                    scanlineDensity: scanlineDensity,
                    shatteredGlassOpacity: shatteredGlassOpacity,
                    shatteredGlassRefraction: shatteredGlassRefraction,
                    shatteredGlassHighlight: shatteredGlassHighlight,
                    shatteredGlassFlipX: shatteredGlassFlipX,
                    onFirstFrameReady: {
                        markCoverReady(for: localURL)
                    }
                )
                .id(localURL)
            } else {
                PixelIcon(.imageFrame, size: 44)
                    .foregroundStyle(.white.opacity(0.28))
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
            }

            if let loadError {
                VStack(spacing: 4) {
                    PixelIcon(.signalOff, size: 16)
                    Text(loadError)
                        .font(.pixel(size: 11))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(10)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: WidgetChromeMetrics.contentCornerRadius))
            }
        }
        .task(id: artworkKey) {
            await loadCover()
        }
    }

    @MainActor
    private func markCoverReady(for url: URL) {
        guard firstFrameReadyURL != url else { return }
        firstFrameReadyURL = url
        onCoverReady?()
    }

    @MainActor
    private func loadCover() async {
        model.resetVisualStageLoadingGate(updateBongoLayer: false)
        guard let artworkURL = track?.image else {
            localURL = nil
            loadError = nil
            onCoverReady?()
            return
        }

        loadError = nil
        if let cached = TrackArtworkCache.cachedURLIfAvailable(for: artworkURL) {
            localURL = cached
            return
        }

        do {
            let url = try await TrackArtworkCache.ensureLocal(for: artworkURL)
            guard !Task.isCancelled else { return }
            localURL = url
            loadError = nil
        } catch {
            guard !Task.isCancelled else { return }
            localURL = nil
            loadError = "Cover unavailable"
            onCoverReady?()
        }
    }
}

private struct TrackBadge: View {
    @EnvironmentObject private var model: AppModel
    let width: CGFloat
    let position: BadgePosition
    let compact: Bool
    let isVisible: Bool

    var body: some View {
        // Sizes intentionally match the original VT323 layout (14 / 18 /
        // 14) at `BadgeSize.medium`; the `scale` multiplier applied below
        // makes the right-click size picker affect every text and the
        // waveform together so the readout stays visually balanced as it
        // scales up/down.
        let scale = model.badgeSize.scale
        let glowEnabled = model.readoutFontSettings.textGlow
        let shadowEnabled = model.readoutFontSettings.textShadow
        let placement = position.horizontalPlacement
        let innerInsets = badgeInnerInsets(compact: compact, placement: placement)
        let waveformSlotH = 14 * scale
        let marqueeDebugStretch = model.debugModeEnabled

        VStack(spacing: 1) {
            if model.readoutFontSettings.waveform {
                // `NSViewRepresentable` expands to fill a proposed max width.
                // Pin the waveform to a fixed 120×14pt slot inside an `HStack`
                // so bar math always matches the design width and lines up with
                // the text rows (which use the same horizontal placement).
                //
                // Size the representable *before* `GlowShadowStack`: applying
                // shadows first made SwiftUI clip the NSView to the bloomed
                // bounds, which cropped the top half when the row was centered.
                HStack(alignment: .center, spacing: 0) {
                    if placement == .center || placement == .trailing {
                        Spacer(minLength: 0)
                    }
                    PixelWaveform(
                        mode: {
                            if model.isPlaying,
                               !model.isBuffering,
                               model.currentTrack != nil {
                                return .playing
                            }
                            if model.isPlaying {
                                return .loading
                            }
                            return .idle
                        }(),
                        color: model.accent,
                        placement: placement
                    )
                    .frame(width: 120 * scale, height: waveformSlotH)
                    .fixedSize(horizontal: true, vertical: true)
                    .modifier(
                        GlowShadowStack(
                            glowColor: model.accent,
                            glowEnabled: glowEnabled,
                            shadowEnabled: shadowEnabled
                        )
                    )
                    if placement == .center || placement == .leading {
                        Spacer(minLength: 0)
                    }
                }
                // Reserve vertical room for bloom/shadow above and below the bars.
                .frame(minHeight: waveformSlotH + (glowEnabled ? 14 : (shadowEnabled ? 6 : 0)))
                .padding(.bottom, 2)
            }

            GlowingPixelText(
                text: model.currentPreset.displayName.uppercased(),
                size: 14 * scale,
                kerning: 2.0,
                color: model.accent,
                glowColor: model.accent,
                glowEnabled: glowEnabled,
                shadowEnabled: shadowEnabled
            )
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: placement.frameAlignment)

            if let track = model.currentTrack {
                trackText(track: track, placement: placement, marqueeDebugStretch: marqueeDebugStretch)
            } else {
                GlowingPixelText(
                    text: model.streamStatus,
                    size: 14 * scale,
                    kerning: 0.3,
                    color: .white.opacity(0.78),
                    glowColor: .white,
                    glowEnabled: glowEnabled,
                    shadowEnabled: shadowEnabled
                )
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: placement.frameAlignment)
            }
        }
        .multilineTextAlignment(placement.textAlignment)
        .padding(innerInsets)
        .frame(width: width)
        .padding(.horizontal, ReadoutGlowBleed.horizontal)
        .padding(.vertical, ReadoutGlowBleed.vertical)
    }

    private func trackText(
        track: LiveTrack,
        placement: BadgeHorizontalPlacement,
        marqueeDebugStretch: Bool
    ) -> some View {
        let scale = model.badgeSize.scale
        let glowEnabled = model.readoutFontSettings.textGlow
        let shadowEnabled = model.readoutFontSettings.textShadow

        return VStack(spacing: 0) {
            MarqueePixelText(
                text: marqueeStretchForDebug(track.title, enabled: marqueeDebugStretch),
                size: 18 * scale,
                kerning: 0.4,
                color: .white,
                glowColor: .white,
                glowEnabled: glowEnabled,
                shadowEnabled: shadowEnabled,
                placement: placement,
                scrollingEnabled: isVisible
            )

            MarqueePixelText(
                text: marqueeStretchForDebug(track.artists, enabled: marqueeDebugStretch),
                size: 14 * scale,
                kerning: 0.3,
                color: .white.opacity(0.78),
                glowColor: .white,
                glowEnabled: glowEnabled,
                shadowEnabled: shadowEnabled,
                placement: placement,
                scrollingEnabled: isVisible
            )
        }
        .frame(maxWidth: .infinity, alignment: placement.frameAlignment)
    }
}

/// Pixel/dot-matrix text with stacked `.shadow` layers for CRT-style bloom
/// (optional) plus an optional black drop shadow for contrast on bright frames.
private struct GlowingPixelText: View {
    @EnvironmentObject private var model: AppModel

    let text: String
    let size: CGFloat
    let kerning: CGFloat
    let color: Color
    let glowColor: Color
    /// Toggle for the expensive 3-shadow CRT bloom stack. Off, we keep
    /// just the 1px black readability shadow so the text still pops on
    /// bright frames without the per-frame compositor cost.
    var glowEnabled: Bool = true
    /// Black drop shadow (Readout menu); independent of `glowEnabled`.
    var shadowEnabled: Bool = true

    var body: some View {
        Text(text)
            .font(
                .pixel(
                    size: size,
                    weightAxis: model.readoutFontSettings.weight.axisValue,
                    elementShape: model.readoutFontSettings.elementShape.axisValue
                )
            )
            .kerning(kerning)
            .foregroundStyle(color)
            .modifier(
                GlowShadowStack(
                    glowColor: glowColor,
                    glowEnabled: glowEnabled,
                    shadowEnabled: shadowEnabled
                )
            )
    }
}

/// Colored bloom + optional black drop shadow for readout text and waveform.
/// Split so Text Glow and Text Shadow can be toggled
/// independently.
private struct GlowShadowStack: ViewModifier {
    let glowColor: Color
    var glowEnabled: Bool
    var shadowEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        switch (glowEnabled, shadowEnabled) {
        case (true, true):
            content
                .shadow(color: glowColor.opacity(0.55), radius: 6)
                .shadow(color: glowColor.opacity(0.45), radius: 3)
                .shadow(color: .black.opacity(0.55), radius: 1, y: 1)
        case (true, false):
            content
                .shadow(color: glowColor.opacity(0.55), radius: 6)
                .shadow(color: glowColor.opacity(0.45), radius: 3)
        case (false, true):
            content
                .shadow(color: .black.opacity(0.55), radius: 1, y: 1)
        case (false, false):
            content
        }
    }
}

/// Glowing pixel text that horizontally scrolls when it overflows its
/// container. When the text fits we just render it centered like
/// `GlowingPixelText` would — no animation, no jitter. When it doesn't,
/// we duplicate the string with a separator and slide both copies left
/// at a constant speed so the readout reads as a continuous loop (the
/// classic radio/jukebox marquee idiom).
///
/// We measure the rendered text width via a hidden sizing pass rather
/// than `String.count` because Doto is grid-monospaced but kerning
/// still makes character-count math drift; rendering once and reading the
/// resulting frame is cheap and exact.
private struct MarqueePixelText: View {
    @EnvironmentObject private var model: AppModel

    let text: String
    let size: CGFloat
    let kerning: CGFloat
    let color: Color
    let glowColor: Color
    /// See `GlowingPixelText.glowEnabled`.
    var glowEnabled: Bool = true
    /// See `GlowingPixelText.shadowEnabled`.
    var shadowEnabled: Bool = true
    let placement: BadgeHorizontalPlacement
    /// When false, render static centered text and stop timeline ticks.
    var scrollingEnabled: Bool = true

    /// Line box height: Doto metrics plus room for `GlowShadowStack` halos
    /// (radii up to 6) so we do not clip the bloom vertically.
    private static let lineHeightFactor: CGFloat = 1.38

    /// How fast the strip slides, in points per second. Slow enough to be
    /// readable on a 240–400pt widget, fast enough that a long title gets
    /// across in well under a minute.
    private static let pixelsPerSecond: Double = 28
    /// Spacer between the trailing edge of one centered copy and the
    /// leading edge of the next. We keep this only for center-aligned
    /// marquees; edge-aligned rows use a seamless loop so the anchored
    /// side never flashes a blank strip while the next copy enters.
    private static let centeredLoopGap: CGFloat = 32
    /// Pause at the leftmost position before the scroll starts, so users
    /// who glance at the badge can read the start of the title without it
    /// already moving.
    private static let leadingPause: Double = 1.2

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var phaseOffset: CGFloat = 0
    @State private var marqueeTask: Task<Void, Never>?

    var body: some View {
        // Measure intrinsic line width in `.background` so it never widens
        // the marquee container. A wide hidden sizer was previously a sibling
        // in `ZStack` with the marquee; `ZStack` took `max(sizer, viewport)`
        // width and centered children, so the clipped viewport showed empty
        // space on the leading edge (wrong for `.leading` and `.center`).
        let widthMeasurer = base
            .fixedSize()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TextWidthKey.self,
                        value: proxy.size.width
                    )
                }
            )
            .opacity(0)
            .allowsHitTesting(false)

        return GeometryReader { geo in
            Color.clear
                .frame(width: geo.size.width, height: size * Self.lineHeightFactor)
                .overlay(alignment: .topLeading) {
                    if !scrollingEnabled || textWidth <= geo.size.width {
                        base.frame(maxWidth: .infinity, alignment: placement.frameAlignment)
                    } else {
                        marquee(in: geo.size.width)
                    }
                }
                .background(alignment: .topLeading) {
                    widthMeasurer
                }
                .onAppear {
                    containerWidth = geo.size.width
                    restartMarqueeIfNeeded()
                }
                .onChange(of: geo.size.width) { _, new in
                    containerWidth = new
                    restartMarqueeIfNeeded()
                }
        }
        .frame(height: size * Self.lineHeightFactor)
        .onPreferenceChange(TextWidthKey.self) { width in
            textWidth = width
            restartMarqueeIfNeeded()
        }
        .onChange(of: scrollingEnabled) { _, _ in
            restartMarqueeIfNeeded()
        }
        .onChange(of: text) { _, _ in
            restartMarqueeIfNeeded()
        }
        .onDisappear {
            marqueeTask?.cancel()
            marqueeTask = nil
        }
    }

    private var base: some View {
        Text(text)
            .font(
                .pixel(
                    size: size,
                    weightAxis: model.readoutFontSettings.weight.axisValue,
                    elementShape: model.readoutFontSettings.elementShape.axisValue
                )
            )
            .kerning(kerning)
            .foregroundStyle(color)
            .modifier(
                GlowShadowStack(
                    glowColor: glowColor,
                    glowEnabled: glowEnabled,
                    shadowEnabled: shadowEnabled
                )
            )
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var loopGap: CGFloat {
        switch placement {
        case .center:
            return Self.centeredLoopGap
        case .leading, .trailing:
            return 0
        }
    }

    /// Three-copy strip slid by `phase`. Phase wraps every
    /// `(textWidth + loopGap)` points so the next copy seamlessly
    /// covers the gap left by the previous one.
    ///
    /// Centering: the previous version anchored the strip with
    /// `.frame(alignment: .leading)`, so a long title would always
    /// "live" in the left half of the viewport — visually mis-aligned
    /// with the centered station name and artists rows above/below it
    /// (and producing the "the marquee row isn't centered" complaint
    /// when scrolling). We now anchor copy #2 (the middle one) to the
    /// horizontal center of the viewport at the start of every cycle,
    /// so the readout begins centered, drifts left through the center
    /// for one stride, and then snaps back invisibly to the next copy
    /// — same on-screen position, no jump. Three copies are required
    /// for that snap to be seamless on BOTH edges of the viewport
    /// (with two copies the left edge would briefly go blank at the
    /// wrap point).
    ///
    /// Layout note: we deliberately put `.frame(width:) → .clipped() →
    /// .mask(...)` on the OUTER container, not on the offset HStack
    /// inside. SwiftUI's `.mask` paints its mask shape across the
    /// rendered bounds of the view it's attached to, and an HStack with
    /// `.offset(x:)` reports a much wider rendered bound than the
    /// visible window — so attaching the gradient to the offset strip
    /// stretched the fade across the entire (textWidth*N + gaps) range,
    /// pushed the left fade halfway across the visible area and pushed
    /// the right fade off-screen entirely. Clipping first, then masking
    /// the clipped result, makes both fades hug the actual viewport
    /// edges symmetrically.
    private func marquee(in width: CGFloat) -> some View {
        let strideWidth = textWidth + loopGap
        let anchorX: CGFloat
        let middleCopyAnchorOffset: CGFloat
        switch placement {
        case .leading:
            anchorX = 0
            middleCopyAnchorOffset = 0
        case .center:
            anchorX = width / 2
            middleCopyAnchorOffset = textWidth / 2
        case .trailing:
            anchorX = width
            middleCopyAnchorOffset = textWidth
        }
        let baseX = anchorX - strideWidth - middleCopyAnchorOffset
        return HStack(spacing: loopGap) {
            base
            base
            base
        }
        .frame(height: size * Self.lineHeightFactor, alignment: .leading)
        .offset(x: baseX - phaseOffset)
        .frame(width: width, height: size * Self.lineHeightFactor, alignment: .leading)
        // No `.clipped()` here — it cut off the shadow stack at the viewport
        // edge. `GeometryReader` in the parent already bounds horizontal draw.
        .mask(edgeFadeMask(for: width))
    }

    private func edgeFadeMask(for width: CGFloat) -> LinearGradient {
        let fade = min(0.12, 12.0 / max(width, 1))
        let stops: [Gradient.Stop]

        switch placement {
        case .leading:
            // Left-aligned marquee should feel pinned to the left edge, so
            // only the trailing edge fades out as text exits the viewport.
            stops = [
                .init(color: .black, location: 0.0),
                .init(color: .black, location: 1.0 - fade),
                .init(color: .clear, location: 1.0),
            ]
        case .center:
            stops = [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: fade),
                .init(color: .black, location: 1.0 - fade),
                .init(color: .clear, location: 1.0),
            ]
        case .trailing:
            // Mirror of `.leading`: keep the anchored right edge solid and
            // only fade the leading edge as text enters.
            stops = [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: fade),
                .init(color: .black, location: 1.0),
            ]
        }

        return LinearGradient(
            stops: stops,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func restartMarqueeIfNeeded() {
        marqueeTask?.cancel()
        marqueeTask = nil
        phaseOffset = 0

        let shouldScroll = scrollingEnabled
            && containerWidth > 0
            && textWidth > containerWidth
        guard shouldScroll else { return }

        let strideWidth = textWidth + loopGap
        let duration = Double(strideWidth) / Self.pixelsPerSecond
        marqueeTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.leadingPause * 1_000_000_000))
                guard !Task.isCancelled else { break }

                phaseOffset = 0
                withAnimation(.linear(duration: duration)) {
                    phaseOffset = strideWidth
                }

                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                guard !Task.isCancelled else { break }
                phaseOffset = 0
            }
        }
    }
}

/// PreferenceKey used by `MarqueePixelText` to bubble its rendered width
/// up from the hidden sizer pass.
private struct TextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Flat baseline, same segmented strip with a traveling brightness (no extra
/// height), or full EQ animation when audio is flowing.
private enum PixelWaveformMode: Equatable {
    case idle
    case loading
    case playing
}

/// Decorative pixel-art waveform that sits above the preset name.
///
/// Rendered entirely inside a CALayer via a CADisplayLink so it never
/// touches the SwiftUI layout engine after initial mount. The previous
/// implementation used a `Task { @MainActor }` loop that wrote a
/// `@State` property every 125 ms, which caused the full SwiftUI body
/// (GeometryReader → ForEach → 16 Rectangles) to re-evaluate at 8 Hz —
/// measurably dominant in CPU profiles. This version draws directly into
/// a CGContext each tick instead, keeping all work off the main-thread
/// layout path.
private struct PixelWaveform: NSViewRepresentable {
    let mode: PixelWaveformMode
    let color: Color
    let placement: BadgeHorizontalPlacement

    func makeCoordinator() -> WaveformCoordinator {
        WaveformCoordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        host.wantsLayer = true
        context.coordinator.attach(to: host)
        context.coordinator.update(
            mode: mode,
            color: color,
            placement: placement
        )
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            mode: mode,
            color: color,
            placement: placement
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: WaveformCoordinator) {
        coordinator.tearDown()
    }
}

/// Drives the waveform CALayer via CADisplayLink at ≤15 fps.
/// All drawing is done with CoreGraphics directly into the layer's
/// `contents` CGImage — no SwiftUI layout, no UIKit/AppKit measure pass.
@MainActor
private final class WaveformCoordinator: NSObject {
    private static let barCount = 16
    private static let gap: CGFloat = 1

    private let layer = CALayer()
    private var displayLink: CADisplayLink?
    private weak var hostView: NSView?

    // Props mirrored from the SwiftUI side.
    private var mode: PixelWaveformMode = .idle
    private var cgColor: CGColor = NSColor.white.cgColor
    private var placement: BadgeHorizontalPlacement = .center

    func attach(to host: NSView) {
        hostView = host
        layer.frame = host.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        host.layer?.addSublayer(layer)
    }

    fileprivate func update(
        mode: PixelWaveformMode,
        color: Color,
        placement: BadgeHorizontalPlacement
    ) {
        let newCG = NSColor(color).cgColor
        let changed = mode != self.mode
            || newCG != self.cgColor
            || placement != self.placement

        self.mode = mode
        self.cgColor = newCG
        self.placement = placement

        if changed { syncDisplayLink() }
        if changed {
            switch mode {
            case .idle:
                drawFrame(timestamp: 0)
            case .loading:
                drawFrame(timestamp: CACurrentMediaTime())
            case .playing:
                break
            }
        }
    }

    private var needsDisplayLink: Bool {
        mode == .playing || mode == .loading
    }

    private func syncDisplayLink() {
        if needsDisplayLink && displayLink == nil {
            let dl = hostView?.displayLink(target: self, selector: #selector(tick))
                ?? NSScreen.main?.displayLink(target: self, selector: #selector(tick))
            if let dl {
                dl.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 15, preferred: 10)
                dl.add(to: .main, forMode: .common)
                displayLink = dl
            }
        } else if !needsDisplayLink, let dl = displayLink {
            dl.invalidate()
            displayLink = nil
        }
    }

    @objc nonisolated private func tick(_ dl: CADisplayLink) {
        let timestamp = dl.timestamp
        Task { @MainActor in
            drawFrame(timestamp: timestamp)
        }
    }

    private func drawFrame(timestamp: CFTimeInterval) {
        let bounds = layer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let scale = layer.contentsScale
        let w = Int(bounds.width * scale)
        let h = Int(bounds.height * scale)
        guard w > 0, h > 0 else { return }

        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return }

        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))

        let count = Self.barCount
        let gap = Self.gap * scale
        let totalGap = gap * CGFloat(count - 1)
        let barW = max(1, floor((CGFloat(w) - totalGap) / CGFloat(count)))
        let usedW = barW * CGFloat(count) + totalGap
        let slack = max(0, CGFloat(w) - usedW)
        let leadingInset: CGFloat
        switch placement {
        case .leading:  leadingInset = 0
        case .center:   leadingInset = slack / 2
        case .trailing: leadingInset = slack
        }

        switch mode {
        case .idle:
            ctx.setFillColor(cgColor)
            ctx.setAlpha(1)
            for i in 0..<count {
                let barH = scale
                let x = leadingInset + CGFloat(i) * (barW + gap)
                let y = (CGFloat(h) - barH) / 2
                ctx.fill(CGRect(x: x, y: y, width: barW, height: barH))
            }

        case .loading:
            // Keep the 16-bar retro waveform, but drive it with the referenced
            // Lottie's five-step timing: tight left-to-right phase groups,
            // separate height/offset curves, and a lower loading peak.
            ctx.setFillColor(cgColor)
            for i in 0..<count {
                let state = loadingBarState(timestamp: timestamp, index: i, count: count)
                ctx.setAlpha(0.58 + 0.42 * state.height)
                let baseH = scale
                let peakH = max(baseH, floor(CGFloat(h) * 0.48))
                let barH = floor(baseH + (peakH - baseH) * state.height)
                let x = leadingInset + CGFloat(i) * (barW + gap)
                let y = (CGFloat(h) - barH) / 2 - state.offset * CGFloat(h) * 0.18
                ctx.fill(CGRect(x: x, y: y, width: barW, height: barH))
            }
            ctx.setAlpha(1)

        case .playing:
            ctx.setFillColor(cgColor)
            ctx.setAlpha(1)
            let t = timestamp
            for i in 0..<count {
                let phase = Double(i) * 0.7
                let a = cos(t * 2.4 + phase)
                let b = cos(t * 0.9 - phase * 0.5)
                let envelope = (a * 0.6 + b * 0.4 + 1) / 2
                let scaled = 0.20 + envelope * 0.80
                let barH = max(scale, floor(scaled * CGFloat(h)))
                let x = leadingInset + CGFloat(i) * (barW + gap)
                let y = (CGFloat(h) - barH) / 2
                ctx.fill(CGRect(x: x, y: y, width: barW, height: barH))
            }
        }

        if let img = ctx.makeImage() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.contents = img
            CATransaction.commit()
        }
    }

    private func loadingBarState(
        timestamp: CFTimeInterval,
        index: Int,
        count: Int
    ) -> (height: CGFloat, offset: CGFloat) {
        guard count > 1 else { return (0, 0) }

        let frame = (timestamp * 30).truncatingRemainder(dividingBy: 60)
        let phaseGroup = round(Double(index) / Double(count - 1) * 4)
        let delay = phaseGroup * 4
        let local = (frame - delay + 60).truncatingRemainder(dividingBy: 60)

        let height: CGFloat = switch local {
        case 0..<5:
            lottieBezier(CGFloat(local / 5), x1: 0, y1: 0, x2: 0.68, y2: 0.19)
        case 5..<12:
            1
        case 12..<20:
            1 - lottieBezier(CGFloat((local - 12) / 8), x1: 0.55, y1: 0.06, x2: 1, y2: 1)
        default:
            0
        }

        let offset: CGFloat = switch local {
        case 5..<12:
            lottieBezier(CGFloat((local - 5) / 7), x1: 0.55, y1: 0.06, x2: 0.68, y2: 0.19)
        case 12..<20:
            1
        case 20..<30:
            1 - lottieBezier(CGFloat((local - 20) / 10), x1: 0.55, y1: 0.06, x2: 1, y2: 1)
        default:
            0
        }

        return (height, offset)
    }

    private func lottieBezier(
        _ progress: CGFloat,
        x1: CGFloat,
        y1: CGFloat,
        x2: CGFloat,
        y2: CGFloat
    ) -> CGFloat {
        let x = min(1, max(0, progress))
        var low: CGFloat = 0
        var high: CGFloat = 1
        var t = x
        for _ in 0..<8 {
            t = (low + high) / 2
            if cubicBezier(t, 0, x1, x2, 1) < x {
                low = t
            } else {
                high = t
            }
        }
        return cubicBezier(t, 0, y1, y2, 1)
    }

    private func cubicBezier(
        _ t: CGFloat,
        _ p0: CGFloat,
        _ p1: CGFloat,
        _ p2: CGFloat,
        _ p3: CGFloat
    ) -> CGFloat {
        let clamped = min(1, max(0, t))
        let inverse = 1 - clamped
        return inverse * inverse * inverse * p0
            + 3 * inverse * inverse * clamped * p1
            + 3 * inverse * clamped * clamped * p2
            + clamped * clamped * clamped * p3
    }

    func tearDown() {
        displayLink?.invalidate()
        displayLink = nil
        layer.removeFromSuperlayer()
    }
}

// MARK: - Bottom Dock

/// Bottom transport dock — retro/vaporwave styling. No more pill / glass /
/// blur: every control is a hard-edged rectangle with a 1px accent border
/// and a thin chromatic-aberration shadow stack so the whole row reads as
/// a piece of CRT-era console UI rather than a macOS toolbar.
///
/// The 8-station preset row that used to live here is gone — the pop-out
/// grid in TopChrome owns station selection. Prev/next still cycles
/// through stations so keyboard/power users don't lose anything.
private struct BottomDock: View {
    @EnvironmentObject private var model: AppModel
    let compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            RetroTransportButton(
                glyph: .prev,
                accent: model.accent,
                size: CGSize(width: 36, height: 30),
                action: model.previousStation
            )

            RetroPlayPauseButton(
                isPlaying: model.isPlaying,
                isBuffering: model.isBuffering,
                accent: model.accent,
                action: model.togglePlayback
            )

            RetroTransportButton(
                glyph: .next,
                accent: model.accent,
                size: CGSize(width: 36, height: 30),
                action: model.nextStation
            )
        }
    }
}

/// Borderless side transport button. Keeps the same hit area as before so
/// the dock remains easy to click, but visually renders as just the glyph
/// with a light hover lift instead of a boxed button.
private struct RetroTransportButton: View {
    let glyph: PixelGlyph
    let accent: Color
    let size: CGSize
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            PixelIcon(glyph, size: 14)
                .foregroundStyle(hovering ? .white : .white.opacity(0.80))
                .frame(width: size.width, height: size.height)
                // Soft cyan/magenta drop shadows to mimic the chromatic
                // misregistration of an old VHS / CRT signal.
                .shadow(color: Color(red: 0.32, green: 0.95, blue: 1.00).opacity(hovering ? 0.42 : 0.28), radius: 0, x: -1, y: 0)
                .shadow(color: Color(red: 1.00, green: 0.32, blue: 0.85).opacity(hovering ? 0.42 : 0.28), radius: 0, x: 1, y: 0)
                .shadow(color: accent.opacity(hovering ? 0.30 : 0.0), radius: hovering ? 6 : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Wider, accent-filled play/pause cell. Same hard-edge vocabulary as the
/// transport buttons but inverted (accent fill, dark glyph) so the
/// primary action visually dominates the row.
private struct RetroPlayPauseButton: View {
    let isPlaying: Bool
    /// Render an indeterminate progress strip on top of the cell while
    /// the network/audio pipeline is still warming up. The button stays
    /// clickable (so users can cancel a stalled stream) and the
    /// underlying play/pause glyph stays visible.
    let isBuffering: Bool
    let accent: Color
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.65)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 56, height: 30)
                    .overlay(
                        Rectangle().stroke(.white.opacity(0.18), lineWidth: 1)
                    )

                PixelIcon(isPlaying ? .pause : .play, size: 16)
                    .foregroundStyle(.black.opacity(isBuffering ? 0.35 : 0.88))
                    .offset(x: isPlaying ? 0 : 1)

                if isBuffering {
                    BufferingBar(accent: accent)
                        .frame(width: 56, height: 30)
                        .transition(.opacity)
                }
            }
            // Same chromatic shadow vocabulary as the side transports —
            // a little stronger here because this cell is bigger.
            .shadow(color: Color(red: 0.32, green: 0.95, blue: 1.00).opacity(0.50), radius: 0, x: -1.5, y: 0)
            .shadow(color: Color(red: 1.00, green: 0.32, blue: 0.85).opacity(0.50), radius: 0, x: 1.5, y: 0)
            .shadow(color: accent.opacity(hovering ? 0.55 : 0.30), radius: hovering ? 10 : 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.18), value: isBuffering)
    }
}

/// Indeterminate progress strip drawn on top of the play/pause cell when
/// the stream is buffering. Replaces the old `BufferingRing` (a circular
/// stroke) which made no sense on a square cell — we use a 28pt scanning
/// segment that slides across the bottom edge instead, mirroring the
/// "loading" bar idiom of 80s/90s VCRs.
private struct BufferingBar: View {
    let accent: Color
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let segmentWidth: CGFloat = max(20, geo.size.width * 0.4)
            let travel = geo.size.width + segmentWidth
            let x = -segmentWidth + phase * travel
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(.black.opacity(0.28))
                    .frame(height: 3)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                Rectangle()
                    .fill(.white.opacity(0.95))
                    .frame(width: segmentWidth, height: 3)
                    .offset(x: x)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .onAppear {
            phase = 0
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
        .onDisappear {
            phase = 0
        }
    }
}

// MARK: - Volume Overlay

/// Centered, chunky volume HUD. No background card — the readout sits
/// directly on the artwork like the TrackBadge does, relying on the same
/// per-element drop shadow + glow stack for legibility against bright
/// scenes. The speaker glyph cycles through the pixelarticons volume
/// ladder (mute → 1 / 2 / 3 waves → full) so the icon itself reflects
/// the current level, the way the macOS / iOS speaker glyphs do.
private struct VolumeOverlay: View {
    let volume: Double
    let accent: Color

    /// Number of segments in the bar. 10 maps cleanly to a 0–100 readout
    /// and keeps each block big enough to read at small window sizes.
    private static let segmentCount = 10

    private var filledSegments: Int {
        // Round so 1% still lights one block (the user definitely turned the
        // knob), and 100% fills the full bar.
        let raw = volume * Double(Self.segmentCount)
        if volume > 0 && raw < 1 { return 1 }
        return min(Self.segmentCount, Int(raw.rounded()))
    }

    /// Maps the current 0…1 volume onto the pixelarticons speaker ladder.
    /// Thresholds are picked so each glyph "owns" a clear quarter of the
    /// slider — at 0% you get the muted X, at ~25/50/75% you climb the
    /// 1/2/3 wave glyphs, and ~95%+ flips to the full speaker so users
    /// can tell when they've actually maxed out.
    private var levelGlyph: PixelGlyph {
        switch volume {
        case ..<0.001: return .volumeMute
        case ..<0.25:  return .volume1
        case ..<0.55:  return .volume2
        case ..<0.85:  return .volume3
        default:       return .volumeFull
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                PixelIcon(levelGlyph, size: 18)
                    .foregroundStyle(.white)
                    // Same shadow stack as GlowingPixelText so the
                    // glyph stays readable on bright scenes without a
                    // background plate.
                    .shadow(color: .white.opacity(0.45), radius: 5)
                    .shadow(color: .black.opacity(0.55), radius: 1, y: 1)

                Text("VOL")
                    .font(.pixel(size: 18))
                    .kerning(2)
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .white.opacity(0.40), radius: 5)
                    .shadow(color: .black.opacity(0.55), radius: 1, y: 1)

                Spacer(minLength: 16)

                Text("\(Int(round(volume * 100)))")
                    .font(.pixel(size: 22))
                    .foregroundStyle(accent)
                    .monospacedDigit()
                    .shadow(color: accent.opacity(0.55), radius: 6)
                    .shadow(color: .black.opacity(0.55), radius: 1, y: 1)
            }

            HStack(spacing: 3) {
                ForEach(0..<Self.segmentCount, id: \.self) { i in
                    Rectangle()
                        .fill(i < filledSegments ? accent : Color.white.opacity(0.18))
                        .frame(height: 14)
                        .overlay(
                            Rectangle().stroke(
                                i < filledSegments
                                    ? accent
                                    : Color.white.opacity(0.35),
                                lineWidth: 1
                            )
                        )
                }
            }
            // Soft halo under the whole bar so the segments don't
            // disappear on near-white frames; chromatic accents keep
            // the dock/HUD/badge family identity.
            .shadow(color: accent.opacity(0.45), radius: 6)
            .shadow(color: Color(red: 0.32, green: 0.95, blue: 1.00).opacity(0.35), radius: 0, x: -1, y: 0)
            .shadow(color: Color(red: 1.00, green: 0.32, blue: 0.85).opacity(0.35), radius: 0, x: 1, y: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 220)
    }
}

// MARK: - Settings Overlay

/// In-widget settings panel for the same preferences exposed by the
/// right-click menu. It stays background-light like the volume HUD:
/// compact rows over the artwork, with paging instead of nested menus.
private struct SettingsOverlay: View {
    @EnvironmentObject private var model: AppModel

    let compact: Bool
    let close: () -> Void

    @State private var page: SettingsOverlayPage = .readout
    @State private var bongoModelListOpen = false

    private var textSize: CGFloat { compact ? 10 : 11 }
    private var titleSize: CGFloat { compact ? 12 : 13 }

    private var bongoCatPackChoices: [BongoCatPack] {
        BongoCatModelKind.allCases.map { .bundled($0) }
            + model.bongoImportedModelFolderNames.map { .imported(folderName: $0) }
    }

    var body: some View {
        GeometryReader { geo in
            let edge = compact ? CGFloat(10) : CGFloat(14)
            let panelWidth = max(geo.size.width - edge * 2, 188)
            let panelHeight = max(geo.size.height - edge * 2, 190)

            ZStack(alignment: .top) {
                Color.black.opacity(0.80)
                    .contentShape(Rectangle())

                VStack(spacing: 0) {
                    header
                    SettingsPageTabs(
                    selection: $page,
                    accent: model.accent,
                    textSize: textSize
                )

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            currentPage
                        }
                        .padding(.horizontal, compact ? 10 : 12)
                        .padding(.vertical, 10)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(width: panelWidth, alignment: .top)
                .frame(maxHeight: panelHeight, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture {}
                .padding(edge)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear {
                model.refreshBongoImportedModels()
            }
        }
    }

    @ViewBuilder
    private var currentPage: some View {
        switch page {
        case .readout:
            readoutSection
        case .bongo:
            bongoSection
        case .crt:
            crtSection
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            PixelIcon(.sliders, size: 13)
                .foregroundStyle(model.accent)

            Text("LOFI SETUP")
                .font(.pixel(size: titleSize))
                .kerning(1.2)
                .foregroundStyle(.white)

            Spacer(minLength: 8)

            Button(action: close) {
                PixelIcon(.close, size: 12)
                    .foregroundStyle(model.accent)
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.plain)
            .help("Close settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(model.accent.opacity(0.34)).frame(height: 1)
        }
    }

    private var readoutSection: some View {
        SettingsSection {
            SettingsToggleRow(
                title: "Enabled",
                isOn: binding(
                    get: { model.isReadoutVisible },
                    set: { model.isReadoutVisible = $0 }
                ),
                accent: model.accent,
                textSize: textSize
            )

            SettingsChoiceRow(
                title: "Size",
                choices: BadgeSize.allCases,
                selection: binding(
                    get: { model.badgeSize },
                    set: { model.badgeSize = $0 }
                ),
                label: { $0.label },
                accent: model.accent,
                textSize: textSize
            )

            SettingsFontWeightChoiceRow(
                title: "Weight",
                selection: readoutChoice(\.weight),
                accent: model.accent,
                textSize: textSize
            )

            SettingsChoiceRow(
                title: "Element Shape",
                choices: ReadoutFontElementShape.allCases,
                selection: readoutChoice(\.elementShape),
                label: { $0.label },
                accent: model.accent,
                textSize: textSize
            )

            SettingsToggleRow(
                title: "Waveform",
                isOn: readoutBool(\.waveform),
                accent: model.accent,
                textSize: textSize
            )

            SettingsToggleRow(
                title: "Text Shadow",
                isOn: readoutBool(\.textShadow),
                accent: model.accent,
                textSize: textSize
            )

            SettingsToggleRow(
                title: "Text Glow",
                isOn: readoutBool(\.textGlow),
                accent: model.accent,
                textSize: textSize
            )

            SettingsPositionGrid(
                title: "Alignment",
                choices: [
                    .topLeading, .top, .topTrailing,
                    .leading, .center, .trailing,
                    .bottomLeading, .bottom, .bottomTrailing,
                ],
                selection: binding(
                    get: { model.badgePosition },
                    set: { model.badgePosition = $0 }
                ),
                label: { $0.shortGridLabel },
                accent: model.accent,
                textSize: textSize
            )
        }
    }

    private var bongoSection: some View {
        SettingsSection {
            SettingsToggleRow(
                title: "Enabled",
                isOn: binding(
                    get: { model.bongoOverlayVisible },
                    set: { model.bongoOverlayVisible = $0 }
                ),
                accent: model.accent,
                textSize: textSize
            )

            SettingsModelPickerRow(
                title: "Model",
                choices: bongoCatPackChoices,
                selection: binding(
                    get: { model.bongoCatPack },
                    set: { model.bongoCatPack = $0 }
                ),
                expanded: $bongoModelListOpen,
                label: { $0.menuLabel },
                accent: model.accent,
                textSize: textSize
            )

            SettingsDualActionRow(
                title: "Custom Models",
                primaryTitle: "Open Folder",
                secondaryTitle: "Refresh",
                accent: model.accent,
                textSize: textSize,
                primaryAction: model.openBongoModelsFolder,
                secondaryAction: model.reloadBongoModelsFromDisk
            )

            SettingsPositionGrid(
                title: "Alignment",
                choices: Array(BongoStageAnchor.allCases),
                selection: binding(
                    get: { model.bongoStageAnchor },
                    set: { model.bongoStageAnchor = $0 }
                ),
                label: { $0.shortGridLabel },
                accent: model.accent,
                textSize: textSize
            )

            SettingsChoiceRow(
                title: "Size",
                choices: BongoStageScaleTier.allCases,
                selection: binding(
                    get: { model.bongoStageScaleTier },
                    set: { model.bongoStageScaleTier = $0 }
                ),
                label: { $0.menuLabel },
                accent: model.accent,
                textSize: textSize
            )

            SettingsChoiceRow(
                title: "Input Rate",
                choices: BongoInputTickRate.allCases,
                selection: binding(
                    get: { model.bongoInputTickRate },
                    set: { model.bongoInputTickRate = $0 }
                ),
                label: { $0.menuLabel },
                accent: model.accent,
                textSize: textSize
            )

            SettingsChoiceRow(
                title: "Mouse Space",
                choices: BongoMouseCursorSpace.allCases,
                selection: binding(
                    get: { model.bongoMouseCursorSpace },
                    set: { model.bongoMouseCursorSpace = $0 }
                ),
                label: { $0.menuLabel },
                accent: model.accent,
                textSize: textSize
            )

            SettingsToggleRow(
                title: "Desktop",
                isOn: binding(
                    get: { model.isBongoDesktopMaskEnabled },
                    set: { enabled in
                        model.bongoDesktopMaskTint = enabled ? .modelDynamic : .hidden
                    }
                ),
                accent: model.accent,
                textSize: textSize
            )

            SettingsColorChoiceRow(
                title: "Desktop Color",
                choices: BongoDesktopMaskTint.colorCases,
                selection: binding(
                    get: {
                        model.bongoDesktopMaskTint == .hidden
                            ? .black
                            : model.bongoDesktopMaskTint
                    },
                    set: { model.bongoDesktopMaskTint = $0 }
                ),
                label: { $0.menuLabel },
                color: { $0.settingsPreviewColor },
                textColor: { $0.settingsPreviewTextColor },
                accent: model.accent,
                textSize: textSize
            )
        }
    }

    private var crtSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection {
                SettingsToggleRow(
                    title: "Enabled",
                    isOn: crtBool(\.enabled),
                    accent: model.accent,
                    textSize: textSize
                )

                SettingsToggleRow(
                    title: "Curvation",
                    isOn: crtBool(\.curvation),
                    accent: model.accent,
                    textSize: textSize
                )

                SettingsChoiceRow(
                    title: "Curvation Strength",
                    choices: CurvationStrength.allCases,
                    selection: crtChoice(\.curvationStrength),
                    label: { $0.label },
                    accent: model.accent,
                    textSize: textSize
                )

                SettingsToggleRow(
                    title: "Vignette",
                    isOn: crtBool(\.vignette),
                    accent: model.accent,
                    textSize: textSize
                )

                SettingsChoiceRow(
                    title: "Vignette Strength",
                    choices: VignetteStrength.allCases,
                    selection: crtChoice(\.vignetteStrength),
                    label: { $0.label },
                    accent: model.accent,
                    textSize: textSize
                )

                SettingsToggleRow(
                    title: "Chromatic Aberration",
                    isOn: crtBool(\.chromaticAberration),
                    accent: model.accent,
                    textSize: textSize
                )

                SettingsChoiceRow(
                    title: "Chromatic Strength",
                    choices: ChromaticAberrationStrength.allCases,
                    selection: crtChoice(\.chromaticAberrationStrength),
                    label: { $0.label },
                    accent: model.accent,
                    textSize: textSize
                )

                SettingsToggleRow(
                    title: "Scan Line",
                    isOn: crtBool(\.scanlines),
                    accent: model.accent,
                    textSize: textSize
                )

                SettingsChoiceRow(
                    title: "Scan Strength",
                    choices: ScanlineOpacity.allCases,
                    selection: crtChoice(\.scanlineOpacity),
                    label: { $0.label },
                    accent: model.accent,
                    textSize: textSize
                )

                SettingsChoiceRow(
                    title: "Scan Density",
                    choices: ScanlineDensity.allCases,
                    selection: crtChoice(\.scanlineDensity),
                    label: { $0.label },
                    accent: model.accent,
                    textSize: textSize
                )

                SettingsToggleRow(
                    title: "Motion Blur",
                    isOn: crtBool(\.motionBlur),
                    accent: model.accent,
                    textSize: textSize
                )

                SettingsChoiceRow(
                    title: "Blur Strength",
                    choices: MotionBlurStrength.allCases,
                    selection: crtChoice(\.motionBlurStrength),
                    label: { $0.label },
                    accent: model.accent,
                    textSize: textSize
                )
            }

            shatteredGlassSection
        }
    }

    private var shatteredGlassSection: some View {
        SettingsSection {
            SettingsToggleRow(
                title: "Enabled",
                isOn: shatteredGlassBool(\.enabled),
                accent: model.accent,
                textSize: textSize
            )

            SettingsChoiceRow(
                title: "Strength",
                choices: ShatteredGlassStrength.allCases,
                selection: shatteredGlassChoice(\.strength),
                label: { $0.label },
                accent: model.accent,
                textSize: textSize
            )

            SettingsChoiceRow(
                title: "Position",
                choices: ShatteredGlassPlacement.allCases,
                selection: shatteredGlassChoice(\.placement),
                label: { $0.label },
                accent: model.accent,
                textSize: textSize
            )
        }
    }

    private func binding<Value>(
        get: @escaping @MainActor @Sendable () -> Value,
        set: @escaping @MainActor @Sendable (Value) -> Void
    ) -> Binding<Value> {
        Binding(get: get, set: set)
    }

    private func readoutBool(_ keyPath: WritableKeyPath<ReadoutFontSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.readoutFontSettings[keyPath: keyPath] },
            set: { value in
                var settings = model.readoutFontSettings
                settings[keyPath: keyPath] = value
                model.readoutFontSettings = settings
            }
        )
    }

    private func readoutChoice<Value>(
        _ keyPath: WritableKeyPath<ReadoutFontSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { model.readoutFontSettings[keyPath: keyPath] },
            set: { value in
                var settings = model.readoutFontSettings
                settings[keyPath: keyPath] = value
                model.readoutFontSettings = settings
            }
        )
    }

    private func crtBool(_ keyPath: WritableKeyPath<CRTSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.crt[keyPath: keyPath] },
            set: { value in
                var settings = model.crt
                settings[keyPath: keyPath] = value
                model.crt = settings
            }
        )
    }

    private func crtChoice<Value>(_ keyPath: WritableKeyPath<CRTSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.crt[keyPath: keyPath] },
            set: { value in
                var settings = model.crt
                settings[keyPath: keyPath] = value
                model.crt = settings
            }
        )
    }

    private func shatteredGlassBool(_ keyPath: WritableKeyPath<ShatteredGlassSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.shatteredGlass[keyPath: keyPath] },
            set: { value in
                var settings = model.shatteredGlass
                settings[keyPath: keyPath] = value
                model.shatteredGlass = settings
            }
        )
    }

    private func shatteredGlassChoice<Value>(_ keyPath: WritableKeyPath<ShatteredGlassSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.shatteredGlass[keyPath: keyPath] },
            set: { value in
                var settings = model.shatteredGlass
                settings[keyPath: keyPath] = value
                model.shatteredGlass = settings
            }
        )
    }
}

private enum SettingsOverlayPage: String, CaseIterable, Identifiable {
    case readout
    case bongo
    case crt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readout: return "READOUT"
        case .bongo: return "BONGO"
        case .crt: return "CRT"
        }
    }
}

private struct SettingsPageTabs: View {
    @Binding var selection: SettingsOverlayPage
    let accent: Color
    let textSize: CGFloat
    @State private var hovered: SettingsOverlayPage?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SettingsOverlayPage.allCases) { page in
                let selected = selection == page
                let highlighted = selected || hovered == page
                Button {
                    selection = page
                } label: {
                    Text(page.title)
                        .font(.pixel(size: textSize))
                        .foregroundStyle(selected ? accent : (highlighted ? .white.opacity(0.86) : .white.opacity(0.58)))
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .background(selected ? Color.white.opacity(0.070) : (highlighted ? Color.white.opacity(0.060) : Color.clear))
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    hovered = isHovering ? page : (hovered == page ? nil : hovered)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(accent.opacity(0.24)).frame(height: 1)
        }
    }
}

private struct SettingsSection<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            content
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let accent: Color
    let textSize: CGFloat
    @State private var hovering = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                Text(title.uppercased())
                    .font(.pixel(size: textSize))
                    .foregroundStyle(hovering ? .white : .white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 8)

                Text(isOn ? "ON" : "OFF")
                    .font(.pixel(size: textSize))
                    .monospacedDigit()
                    .foregroundStyle(isOn ? .black : .white.opacity(0.76))
                    .frame(width: 42, height: 21)
                    .background(isOn ? accent : Color.white.opacity(hovering ? 0.105 : 0.055))
            }
            .frame(minHeight: 24)
            .background(hovering ? Color.white.opacity(0.045) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct SettingsChoiceRow<Choice: Equatable>: View {
    let title: String
    let choices: [Choice]
    @Binding var selection: Choice
    let label: (Choice) -> String
    let accent: Color
    let textSize: CGFloat
    @State private var hoveredIndex: Int?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title.uppercased())
                .font(.pixel(size: textSize))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 118, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                    choiceButton(choice, index: index)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 24)
    }

    private func choiceButton(_ choice: Choice, index: Int) -> some View {
        let selected = selection == choice
        let hovering = hoveredIndex == index
        return Button {
            selection = choice
        } label: {
            Text(label(choice).uppercased())
                .font(.pixel(size: max(9, textSize - 1)))
                .foregroundStyle(selected ? .black : (hovering ? .white : .white.opacity(0.82)))
                .lineLimit(1)
                .minimumScaleFactor(0.60)
                .frame(maxWidth: .infinity, minHeight: 22)
                .padding(.horizontal, 3)
                .background(selected ? accent : Color.white.opacity(hovering ? 0.115 : 0.055))
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredIndex = isHovering ? index : (hoveredIndex == index ? nil : hoveredIndex)
        }
    }
}

private struct SettingsFontWeightChoiceRow: View {
    let title: String
    @Binding var selection: ReadoutFontWeight
    let accent: Color
    let textSize: CGFloat

    @State private var hoveredIndex: Int?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title.uppercased())
                .font(.pixel(size: textSize))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 118, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(Array(ReadoutFontWeight.allCases.enumerated()), id: \.offset) { index, weight in
                    weightButton(weight, index: index)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 24)
    }

    private func weightButton(_ weight: ReadoutFontWeight, index: Int) -> some View {
        let selected = selection == weight
        let hovering = hoveredIndex == index
        return Button {
            selection = weight
        } label: {
            Text(weight.label.uppercased())
                .font(.pixel(
                    size: max(9, textSize - 1),
                    weightAxis: weight.axisValue,
                    elementShape: ReadoutFontElementShape.square.axisValue
                ))
                .foregroundStyle(selected ? .black : (hovering ? .white : .white.opacity(0.84)))
                .lineLimit(1)
                .minimumScaleFactor(0.60)
                .frame(maxWidth: .infinity, minHeight: 22)
                .padding(.horizontal, 3)
                .background(selected ? accent : Color.white.opacity(hovering ? 0.115 : 0.055))
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredIndex = isHovering ? index : (hoveredIndex == index ? nil : hoveredIndex)
        }
    }
}

private struct SettingsColorChoiceRow<Choice: Equatable>: View {
    let title: String
    let choices: [Choice]
    @Binding var selection: Choice
    let label: (Choice) -> String
    let color: (Choice) -> Color
    let textColor: (Choice) -> Color
    let accent: Color
    let textSize: CGFloat

    @State private var hoveredIndex: Int?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title.uppercased())
                .font(.pixel(size: textSize))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 118, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                    colorButton(choice, index: index)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 24)
    }

    private func colorButton(_ choice: Choice, index: Int) -> some View {
        let selected = selection == choice
        let hovering = hoveredIndex == index
        return Button {
            selection = choice
        } label: {
            ZStack(alignment: .bottom) {
                Text(label(choice).uppercased())
                    .font(.pixel(size: max(9, textSize - 1)))
                    .foregroundStyle(textColor(choice))
                    .lineLimit(1)
                    .minimumScaleFactor(0.56)
                    .frame(maxWidth: .infinity, minHeight: 22)

                if selected {
                    Rectangle()
                        .fill(textColor(choice))
                        .frame(height: 2)
                        .padding(.horizontal, 6)
                }
            }
            .shadow(color: .black.opacity(0.28), radius: 1, y: 0.5)
            .frame(maxWidth: .infinity, minHeight: 22)
            .padding(.horizontal, 3)
            .background(color(choice).opacity(hovering ? 0.92 : 0.78))
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredIndex = isHovering ? index : (hoveredIndex == index ? nil : hoveredIndex)
        }
    }
}

private struct SettingsModelPickerRow<Choice: Equatable>: View {
    let title: String
    let choices: [Choice]
    @Binding var selection: Choice
    @Binding var expanded: Bool
    let label: (Choice) -> String
    let accent: Color
    let textSize: CGFloat

    @State private var headerHovering = false
    @State private var hoveredIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(title.uppercased())
                    .font(.pixel(size: textSize))
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: 118, alignment: .leading)

                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Text(label(selection).uppercased())
                            .font(.pixel(size: max(9, textSize - 1)))
                            .foregroundStyle(headerHovering ? .white : .white.opacity(0.88))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 8)

                        Text(expanded ? "HIDE" : "CHANGE")
                            .font(.pixel(size: max(9, textSize - 1)))
                            .foregroundStyle(headerHovering ? .white : accent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 22)
                    .padding(.horizontal, 3)
                    .background(Color.white.opacity(headerHovering ? 0.105 : 0.055))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { headerHovering = $0 }
            }
            .frame(minHeight: 24)

            if expanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                        modelButton(choice, index: index)
                    }
                }
                .padding(.leading, 126)
                .transition(.opacity)
            }
        }
    }

    private func modelButton(_ choice: Choice, index: Int) -> some View {
        let selected = selection == choice
        let hovering = hoveredIndex == index
        return Button {
            selection = choice
            expanded = false
        } label: {
            HStack(spacing: 8) {
                Text(selected ? ">" : " ")
                    .font(.pixel(size: max(9, textSize - 1)))
                    .foregroundStyle(selected ? .black : .white.opacity(0.40))
                    .frame(width: 10)

                Text(label(choice).uppercased())
                    .font(.pixel(size: max(9, textSize - 1)))
                    .foregroundStyle(selected ? .black : (hovering ? .white : .white.opacity(0.82)))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 21)
            .padding(.horizontal, 3)
            .background(selected ? accent : Color.white.opacity(hovering ? 0.105 : 0.035))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredIndex = isHovering ? index : (hoveredIndex == index ? nil : hoveredIndex)
        }
    }
}

private struct SettingsActionRow: View {
    let title: String
    let actionTitle: String
    let accent: Color
    let textSize: CGFloat
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title.uppercased())
                .font(.pixel(size: textSize))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 118, alignment: .leading)

            Button(action: action) {
                Text(actionTitle.uppercased())
                    .font(.pixel(size: max(9, textSize - 1)))
                    .foregroundStyle(hovering ? .white : accent)
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                    .padding(.horizontal, 3)
                    .background(hovering ? Color.white.opacity(0.085) : Color.clear)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
        .frame(minHeight: 24)
    }
}

private struct SettingsDualActionRow: View {
    let title: String
    let primaryTitle: String
    let secondaryTitle: String
    let accent: Color
    let textSize: CGFloat
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    @State private var hoveringPrimary = false
    @State private var hoveringSecondary = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title.uppercased())
                .font(.pixel(size: textSize))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .frame(width: 118, alignment: .leading)

            HStack(spacing: 4) {
                actionButton(
                    title: primaryTitle,
                    hovering: hoveringPrimary,
                    action: primaryAction
                )
                .onHover { hoveringPrimary = $0 }

                actionButton(
                    title: secondaryTitle,
                    hovering: hoveringSecondary,
                    action: secondaryAction
                )
                .onHover { hoveringSecondary = $0 }
            }
        }
        .frame(minHeight: 24)
    }

    private func actionButton(title: String, hovering: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.pixel(size: max(9, textSize - 1)))
                .foregroundStyle(hovering ? .white : accent)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .frame(maxWidth: .infinity, minHeight: 22)
                .padding(.horizontal, 3)
                .background(hovering ? Color.white.opacity(0.085) : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsPositionGrid<Choice: Equatable>: View {
    let title: String
    let choices: [Choice]
    @Binding var selection: Choice
    let label: (Choice) -> String
    let accent: Color
    let textSize: CGFloat
    @State private var hoveredIndex: Int?

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title.uppercased())
                .font(.pixel(size: textSize))
                .foregroundStyle(.white.opacity(0.74))
                .frame(width: 118, alignment: .leading)
                .padding(.top, 3)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                    let selected = selection == choice
                    let hovering = hoveredIndex == index
                    Button {
                        selection = choice
                    } label: {
                        Text(label(choice))
                            .font(.pixel(size: max(9, textSize - 1)))
                            .foregroundStyle(selected ? .black : (hovering ? .white : .white.opacity(0.82)))
                            .lineLimit(1)
                            .minimumScaleFactor(0.70)
                            .frame(maxWidth: .infinity, minHeight: 20)
                            .background(selected ? accent : Color.white.opacity(hovering ? 0.115 : 0.055))
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovering in
                        hoveredIndex = isHovering ? index : (hoveredIndex == index ? nil : hoveredIndex)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private extension BongoDesktopMaskTint {
    var settingsPreviewColor: Color {
        swiftUIColor
    }

    var settingsPreviewTextColor: Color {
        switch self {
        case .ink:
            return .black
        case .black, .dynamic, .modelDynamic, .hidden:
            return .white
        }
    }
}

private extension BadgePosition {
    var shortGridLabel: String {
        switch self {
        case .topLeading: return "TL"
        case .top: return "T"
        case .topTrailing: return "TR"
        case .leading: return "L"
        case .center: return "C"
        case .trailing: return "R"
        case .bottomLeading: return "BL"
        case .bottom: return "B"
        case .bottomTrailing: return "BR"
        }
    }
}

private extension BongoStageAnchor {
    var shortGridLabel: String {
        switch self {
        case .leading: return "L"
        case .center: return "C"
        case .trailing: return "R"
        case .bottomLeading: return "BL"
        case .bottom: return "B"
        case .bottomTrailing: return "BR"
        }
    }
}

// MARK: - Scroll Wheel + Right-Click Context Menu

/// Transparent NSView that owns BOTH the scroll-wheel volume gesture and
/// the right-click settings menu. Combining them in one host means the
/// hit zones are identical (everything that isn't a chrome control or
/// the badge), so users don't have to hunt for "the right place" to
/// right-click — the same hover area that scrolls volume opens the
/// settings menu.
///
/// `mouseDownCanMoveWindow` stays true so primary-button clicks on the
/// artwork still drag the window. Playback is toggled only from the transport
/// control (or menu / shortcuts), not from bare artwork clicks — so Bongo
/// Live2D taps do not pause the widget. Secondary clicks still pop the menu.
private struct WheelAndContextCatcher: NSViewRepresentable {
    let onDelta: (Double) -> Void
    /// Re-entered every time the menu is about to open so the items
    /// reflect the live model state (e.g. checkmarks on the currently
    /// selected size, alignment, and effect toggles).
    let menuBuilder: () -> NSMenu
    /// When `true`, primary hit-testing misses on `bongoLive2DStageFrame` so clicks reach the Bongo `MTKView` (e.g. random motion).
    let bongoOverlayVisible: Bool
    /// Stage rect in the same coordinate space as the wheel view (full widget).
    let bongoLive2DStageFrame: CGRect

    func makeNSView(context _: Context) -> NSView {
        let view = WheelView()
        view.onDelta = onDelta
        view.menuBuilder = menuBuilder
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        guard let view = nsView as? WheelView else { return }
        view.onDelta = onDelta
        view.menuBuilder = menuBuilder
        view.bongoPassThroughPrimaryHits = bongoOverlayVisible
        view.bongoLive2DStageFrame = bongoLive2DStageFrame
    }

    final class WheelView: NSView {
        var onDelta: ((Double) -> Void)?
        var menuBuilder: (() -> NSMenu)?
        var bongoPassThroughPrimaryHits = false
        var bongoLive2DStageFrame = CGRect.zero

        override func scrollWheel(with event: NSEvent) {
            let delta = Double(event.scrollingDeltaY)
            onDelta?(delta)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let eventType = NSApp.currentEvent?.type
            let isPrimaryMouseEvent = eventType == .leftMouseDown
                || eventType == .leftMouseDragged
                || eventType == .leftMouseUp
            if isPrimaryMouseEvent,
               bongoPassThroughPrimaryHits,
               bongoLive2DStageFrame.width > 1,
               bongoLive2DStageFrame.height > 1,
               bongoLive2DStageFrame.contains(point) {
                return nil
            }
            return self
        }

        // First-mouse so the very first click (primary OR secondary) on
        // a non-key widget still gets through to us — otherwise AppKit
        // would eat the click just to bring the window key, and a
        // right-click on a non-active widget would be silently
        // discarded.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override var acceptsFirstResponder: Bool { true }
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard event.buttonNumber == 0 else {
                super.mouseDown(with: event)
                return
            }
            window?.performDrag(with: event)
        }

        // AppKit's default `menu(for:)` returns the view's `menu`
        // property, but that captures the menu at construction time.
        // Rebuilding via the closure guarantees the items always
        // reflect the live model state (current badge size, current
        // effect toggles, …).
        override func menu(for event: NSEvent) -> NSMenu? {
            return menuBuilder?()
        }
    }
}

/// Builder for the right-click settings menu. Lives outside SwiftUI
/// because NSMenu / NSMenuItem are AppKit types and have to be returned
/// from `NSView.menu(for:)`. We rebuild the menu on every right-click so
/// the checkmarks always mirror the current model state.
@MainActor
enum SettingsContextMenu {
    static func build(model: AppModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // --- Readout submenu ---
        let readoutItem = NSMenuItem(title: "Readout", action: nil, keyEquivalent: "")
        let readoutMenu = NSMenu()
        let visibleItem = NSMenuItem(
            title: "Enabled",
            action: #selector(MenuTarget.toggleReadoutVisibility(_:)),
            keyEquivalent: ""
        )
        visibleItem.state = model.isReadoutVisible ? .on : .off
        visibleItem.target = MenuTarget.shared
        readoutMenu.addItem(visibleItem)
        readoutMenu.addItem(.separator())

        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for size in BadgeSize.allCases {
            let item = NSMenuItem(
                title: size.label,
                action: #selector(MenuTarget.selectSize(_:)),
                keyEquivalent: ""
            )
            item.representedObject = size.rawValue
            item.state = (model.badgeSize == size) ? .on : .off
            item.target = MenuTarget.shared
            sizeMenu.addItem(item)
        }
        sizeItem.submenu = sizeMenu
        readoutMenu.addItem(sizeItem)

        let weightItem = NSMenuItem(title: "Weight", action: nil, keyEquivalent: "")
        let weightMenu = NSMenu()
        for weight in ReadoutFontWeight.allCases {
            let item = NSMenuItem(
                title: weight.label,
                action: #selector(MenuTarget.selectReadoutWeight(_:)),
                keyEquivalent: ""
            )
            item.representedObject = weight.rawValue
            item.state = (model.readoutFontSettings.weight == weight) ? .on : .off
            item.target = MenuTarget.shared
            weightMenu.addItem(item)
        }
        weightItem.submenu = weightMenu
        readoutMenu.addItem(weightItem)

        let shapeItem = NSMenuItem(title: "Element Shape", action: nil, keyEquivalent: "")
        let shapeMenu = NSMenu()
        for shape in ReadoutFontElementShape.allCases {
            let item = NSMenuItem(
                title: shape.label,
                action: #selector(MenuTarget.selectReadoutElementShape(_:)),
                keyEquivalent: ""
            )
            item.representedObject = shape.rawValue
            item.state = (model.readoutFontSettings.elementShape == shape) ? .on : .off
            item.target = MenuTarget.shared
            shapeMenu.addItem(item)
        }
        shapeItem.submenu = shapeMenu
        readoutMenu.addItem(shapeItem)

        let waveformItem = NSMenuItem(
            title: "Waveform",
            action: #selector(MenuTarget.toggleReadoutWaveform(_:)),
            keyEquivalent: ""
        )
        waveformItem.state = model.readoutFontSettings.waveform ? .on : .off
        waveformItem.target = MenuTarget.shared
        readoutMenu.addItem(waveformItem)

        let readoutShadowItem = NSMenuItem(
            title: "Text Shadow",
            action: #selector(MenuTarget.toggleReadoutTextShadow(_:)),
            keyEquivalent: ""
        )
        readoutShadowItem.state = model.readoutFontSettings.textShadow ? .on : .off
        readoutShadowItem.target = MenuTarget.shared
        readoutMenu.addItem(readoutShadowItem)

        let textGlowItem = NSMenuItem(
            title: "Text Glow",
            action: #selector(MenuTarget.toggleReadoutTextGlow(_:)),
            keyEquivalent: ""
        )
        textGlowItem.state = model.readoutFontSettings.textGlow ? .on : .off
        textGlowItem.target = MenuTarget.shared
        readoutMenu.addItem(textGlowItem)

        let posItem = NSMenuItem(title: "Alignment", action: nil, keyEquivalent: "")
        let posMenu = NSMenu()
        addPositionRows(
            to: posMenu,
            rows: badgePositionRows,
            selected: model.badgePosition,
            title: \.label,
            rawValue: \.rawValue,
            action: #selector(MenuTarget.selectPosition(_:))
        )
        posItem.submenu = posMenu
        readoutMenu.addItem(posItem)
        readoutItem.submenu = readoutMenu
        menu.addItem(readoutItem)

        let bongoRoot = NSMenuItem(title: "Bongo Cat", action: nil, keyEquivalent: "")
        let bongoMenu = NSMenu()

        let bongoEnabledItem = NSMenuItem(
            title: "Enabled",
            action: #selector(MenuTarget.toggleBongoOverlay(_:)),
            keyEquivalent: ""
        )
        bongoEnabledItem.state = model.bongoOverlayVisible ? .on : .off
        bongoEnabledItem.target = MenuTarget.shared
        bongoMenu.addItem(bongoEnabledItem)

        let modelItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        model.refreshBongoImportedModels()
        for kind in BongoCatModelKind.allCases {
            let item = NSMenuItem(
                title: kind.menuLabel,
                action: #selector(MenuTarget.selectBongoCatPackBundled(_:)),
                keyEquivalent: ""
            )
            item.representedObject = kind.rawValue
            item.state = (model.bongoCatPack == .bundled(kind)) ? .on : .off
            item.target = MenuTarget.shared
            modelMenu.addItem(item)
        }
        if !model.bongoImportedModelFolderNames.isEmpty {
            modelMenu.addItem(.separator())
            let header = NSMenuItem(title: "Imported (~/.lofii/bongo)", action: nil, keyEquivalent: "")
            header.isEnabled = false
            modelMenu.addItem(header)
            for name in model.bongoImportedModelFolderNames {
                let item = NSMenuItem(
                    title: "    " + name,
                    action: #selector(MenuTarget.selectBongoCatPackImported(_:)),
                    keyEquivalent: ""
                )
                item.representedObject = name
                item.state = (model.bongoCatPack == .imported(folderName: name)) ? .on : .off
                item.target = MenuTarget.shared
                modelMenu.addItem(item)
            }
        }
        modelMenu.addItem(.separator())
        let openModelsFolderItem = NSMenuItem(
            title: "Open Custom Models Folder",
            action: #selector(MenuTarget.openBongoModelsFolder(_:)),
            keyEquivalent: ""
        )
        openModelsFolderItem.target = MenuTarget.shared
        modelMenu.addItem(openModelsFolderItem)
        let reloadModelsItem = NSMenuItem(
            title: "Reload Models",
            action: #selector(MenuTarget.reloadBongoModelsFromDisk(_:)),
            keyEquivalent: ""
        )
        reloadModelsItem.target = MenuTarget.shared
        modelMenu.addItem(reloadModelsItem)
        modelItem.submenu = modelMenu
        bongoMenu.addItem(modelItem)

        let bongoPosItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        let bongoPosMenu = NSMenu()
        if model.hasCustomBongoStagePlacement {
            let customItem = NSMenuItem(title: "Custom", action: nil, keyEquivalent: "")
            customItem.state = .on
            customItem.isEnabled = false
            bongoPosMenu.addItem(customItem)
        }
        let bongoLockItem = NSMenuItem(
            title: "Locked",
            action: #selector(MenuTarget.toggleBongoStageDragLock(_:)),
            keyEquivalent: ""
        )
        bongoLockItem.state = model.bongoStageDragLocked ? .on : .off
        bongoLockItem.target = MenuTarget.shared
        bongoPosMenu.addItem(bongoLockItem)
        bongoPosMenu.addItem(.separator())
        addPositionRows(
            to: bongoPosMenu,
            rows: bongoPositionRows,
            selected: model.hasCustomBongoStagePlacement ? nil : model.bongoStageAnchor,
            title: \.label,
            rawValue: \.rawValue,
            action: #selector(MenuTarget.selectBongoStageAnchor(_:))
        )
        bongoPosItem.submenu = bongoPosMenu
        bongoMenu.addItem(bongoPosItem)

        let bongoSizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let bongoSizeMenu = NSMenu()
        for tier in BongoStageScaleTier.allCases {
            let item = NSMenuItem(
                title: tier.menuLabel,
                action: #selector(MenuTarget.selectBongoStageScaleTier(_:)),
                keyEquivalent: ""
            )
            item.representedObject = tier.rawValue
            item.state = (model.bongoStageScaleTier == tier) ? .on : .off
            item.target = MenuTarget.shared
            bongoSizeMenu.addItem(item)
        }
        bongoSizeItem.submenu = bongoSizeMenu
        bongoMenu.addItem(bongoSizeItem)

        let bongoInputRateItem = NSMenuItem(title: "Input Rate", action: nil, keyEquivalent: "")
        let bongoInputRateMenu = NSMenu()
        for rate in BongoInputTickRate.allCases {
            let item = NSMenuItem(
                title: rate.menuLabel,
                action: #selector(MenuTarget.selectBongoInputTickRate(_:)),
                keyEquivalent: ""
            )
            item.representedObject = rate.rawValue
            item.state = (model.bongoInputTickRate == rate) ? .on : .off
            item.target = MenuTarget.shared
            bongoInputRateMenu.addItem(item)
        }
        bongoInputRateItem.submenu = bongoInputRateMenu
        bongoMenu.addItem(bongoInputRateItem)

        let bongoMouseSpaceItem = NSMenuItem(title: "Mouse Space", action: nil, keyEquivalent: "")
        let bongoMouseSpaceMenu = NSMenu()
        for space in BongoMouseCursorSpace.allCases {
            let item = NSMenuItem(
                title: space.menuLabel,
                action: #selector(MenuTarget.selectBongoMouseCursorSpace(_:)),
                keyEquivalent: ""
            )
            item.representedObject = space.rawValue
            item.state = (model.bongoMouseCursorSpace == space) ? .on : .off
            item.target = MenuTarget.shared
            bongoMouseSpaceMenu.addItem(item)
        }
        bongoMouseSpaceItem.submenu = bongoMouseSpaceMenu
        bongoMenu.addItem(bongoMouseSpaceItem)

        bongoMenu.addItem(.separator())

        let desktopItem = NSMenuItem(title: "Desktop", action: nil, keyEquivalent: "")
        let desktopMenu = NSMenu()
        let desktopEnabledItem = NSMenuItem(
            title: "Enabled",
            action: #selector(MenuTarget.toggleBongoDesktopMask(_:)),
            keyEquivalent: ""
        )
        desktopEnabledItem.state = model.isBongoDesktopMaskEnabled ? .on : .off
        desktopEnabledItem.target = MenuTarget.shared
        desktopMenu.addItem(desktopEnabledItem)
        desktopMenu.addItem(.separator())

        let desktopColorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        let desktopColorMenu = NSMenu()
        for tint in BongoDesktopMaskTint.colorCases {
            let item = NSMenuItem(
                title: tint.menuLabel,
                action: #selector(MenuTarget.selectBongoDesktopTint(_:)),
                keyEquivalent: ""
            )
            item.representedObject = tint.rawValue
            item.state = (model.bongoDesktopMaskTint == tint) ? .on : .off
            item.target = MenuTarget.shared
            desktopColorMenu.addItem(item)
        }
        desktopColorItem.submenu = desktopColorMenu
        desktopMenu.addItem(desktopColorItem)
        desktopItem.submenu = desktopMenu
        bongoMenu.addItem(desktopItem)

        bongoRoot.submenu = bongoMenu
        menu.addItem(bongoRoot)

        // --- CRT submenu ---
        let crtItem = NSMenuItem(title: "CRT", action: nil, keyEquivalent: "")
        let crtMenu = NSMenu()
        let crtEnabledItem = NSMenuItem(
            title: "Enabled",
            action: #selector(MenuTarget.toggleCRT(_:)),
            keyEquivalent: ""
        )
        crtEnabledItem.state = model.crt.enabled ? .on : .off
        crtEnabledItem.target = MenuTarget.shared
        crtMenu.addItem(crtEnabledItem)
        crtMenu.addItem(.separator())

        let curvationItem = NSMenuItem(title: "Curvation", action: nil, keyEquivalent: "")
        let curvationMenu = NSMenu()
        let curvationEnabledItem = NSMenuItem(
            title: "Enabled",
            action: #selector(MenuTarget.toggleCRTComponent(_:)),
            keyEquivalent: ""
        )
        curvationEnabledItem.representedObject = CRTComponentKey.curvation.rawValue
        curvationEnabledItem.state = model.crt.curvation ? .on : .off
        curvationEnabledItem.target = MenuTarget.shared
        curvationMenu.addItem(curvationEnabledItem)
        curvationMenu.addItem(.separator())
        let curvationStrengthItem = NSMenuItem(title: "Strength", action: nil, keyEquivalent: "")
        let curvationStrengthMenu = NSMenu()
        for strength in CurvationStrength.allCases {
            let item = NSMenuItem(
                title: strength.label,
                action: #selector(MenuTarget.selectCurvationStrength(_:)),
                keyEquivalent: ""
            )
            item.representedObject = strength.rawValue
            item.state = (model.crt.curvationStrength == strength) ? .on : .off
            item.target = MenuTarget.shared
            curvationStrengthMenu.addItem(item)
        }
        curvationStrengthItem.submenu = curvationStrengthMenu
        curvationMenu.addItem(curvationStrengthItem)
        curvationItem.submenu = curvationMenu
        crtMenu.addItem(curvationItem)

        let vignetteItem = NSMenuItem(title: "Vignette", action: nil, keyEquivalent: "")
        let vignetteMenu = NSMenu()
        let vignetteEnabledItem = NSMenuItem(
            title: "Enabled",
            action: #selector(MenuTarget.toggleCRTComponent(_:)),
            keyEquivalent: ""
        )
        vignetteEnabledItem.representedObject = CRTComponentKey.vignette.rawValue
        vignetteEnabledItem.state = model.crt.vignette ? .on : .off
        vignetteEnabledItem.target = MenuTarget.shared
        vignetteMenu.addItem(vignetteEnabledItem)
        vignetteMenu.addItem(.separator())
        let vignetteStrengthItem = NSMenuItem(title: "Strength", action: nil, keyEquivalent: "")
        let vignetteStrengthMenu = NSMenu()
        for strength in VignetteStrength.allCases {
            let item = NSMenuItem(
                title: strength.label,
                action: #selector(MenuTarget.selectVignetteStrength(_:)),
                keyEquivalent: ""
            )
            item.representedObject = strength.rawValue
            item.state = (model.crt.vignetteStrength == strength) ? .on : .off
            item.target = MenuTarget.shared
            vignetteStrengthMenu.addItem(item)
        }
        vignetteStrengthItem.submenu = vignetteStrengthMenu
        vignetteMenu.addItem(vignetteStrengthItem)
        vignetteItem.submenu = vignetteMenu
        crtMenu.addItem(vignetteItem)

        let chromaticItem = NSMenuItem(title: "Chromatic Aberration", action: nil, keyEquivalent: "")
        let chromaticMenu = NSMenu()
        let chromaticEnabledItem = NSMenuItem(
            title: "Enabled",
            action: #selector(MenuTarget.toggleCRTComponent(_:)),
            keyEquivalent: ""
        )
        chromaticEnabledItem.representedObject = CRTComponentKey.chromaticAberration.rawValue
        chromaticEnabledItem.state = model.crt.chromaticAberration ? .on : .off
        chromaticEnabledItem.target = MenuTarget.shared
        chromaticMenu.addItem(chromaticEnabledItem)
        chromaticMenu.addItem(.separator())

        let chromaticStrengthItem = NSMenuItem(title: "Strength", action: nil, keyEquivalent: "")
        let chromaticStrengthMenu = NSMenu()
        for strength in ChromaticAberrationStrength.allCases {
            let item = NSMenuItem(
                title: strength.label,
                action: #selector(MenuTarget.selectChromaticAberrationStrength(_:)),
                keyEquivalent: ""
            )
            item.representedObject = strength.rawValue
            item.state = (model.crt.chromaticAberrationStrength == strength) ? .on : .off
            item.target = MenuTarget.shared
            chromaticStrengthMenu.addItem(item)
        }
        chromaticStrengthItem.submenu = chromaticStrengthMenu
        chromaticMenu.addItem(chromaticStrengthItem)
        chromaticItem.submenu = chromaticMenu
        crtMenu.addItem(chromaticItem)

        let scanlineItem = NSMenuItem(title: "Scan Line", action: nil, keyEquivalent: "")
        let scanlineMenu = NSMenu()
        let scanlineEnabledItem = NSMenuItem(
            title: "Enabled",
            action: #selector(MenuTarget.toggleCRTComponent(_:)),
            keyEquivalent: ""
        )
        scanlineEnabledItem.representedObject = CRTComponentKey.scanlines.rawValue
        scanlineEnabledItem.state = model.crt.scanlines ? .on : .off
        scanlineEnabledItem.target = MenuTarget.shared
        scanlineMenu.addItem(scanlineEnabledItem)
        scanlineMenu.addItem(.separator())

        let opacityItem = NSMenuItem(title: "Strength", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for opacity in ScanlineOpacity.allCases {
            let item = NSMenuItem(
                title: opacity.label,
                action: #selector(MenuTarget.selectScanlineOpacity(_:)),
                keyEquivalent: ""
            )
            item.representedObject = opacity.rawValue
            item.state = (model.crt.scanlineOpacity == opacity) ? .on : .off
            item.target = MenuTarget.shared
            opacityMenu.addItem(item)
        }
        opacityItem.submenu = opacityMenu
        scanlineMenu.addItem(opacityItem)

        let densityItem = NSMenuItem(title: "Density", action: nil, keyEquivalent: "")
        let densityMenu = NSMenu()
        for density in ScanlineDensity.allCases {
            let item = NSMenuItem(
                title: density.label,
                action: #selector(MenuTarget.selectScanlineDensity(_:)),
                keyEquivalent: ""
            )
            item.representedObject = density.rawValue
            item.state = (model.crt.scanlineDensity == density) ? .on : .off
            item.target = MenuTarget.shared
            densityMenu.addItem(item)
        }
        densityItem.submenu = densityMenu
        scanlineMenu.addItem(densityItem)

        scanlineItem.submenu = scanlineMenu
        crtMenu.addItem(scanlineItem)

        let motionBlurItem = NSMenuItem(title: "Motion Blur", action: nil, keyEquivalent: "")
        let motionBlurMenu = NSMenu()
        let motionBlurEnabledItem = NSMenuItem(
            title: "Enabled",
            action: #selector(MenuTarget.toggleCRTComponent(_:)),
            keyEquivalent: ""
        )
        motionBlurEnabledItem.representedObject = CRTComponentKey.motionBlur.rawValue
        motionBlurEnabledItem.state = model.crt.motionBlur ? .on : .off
        motionBlurEnabledItem.target = MenuTarget.shared
        motionBlurMenu.addItem(motionBlurEnabledItem)
        motionBlurMenu.addItem(.separator())

        let motionBlurStrengthItem = NSMenuItem(title: "Strength", action: nil, keyEquivalent: "")
        let motionBlurStrengthMenu = NSMenu()
        for strength in MotionBlurStrength.allCases {
            let item = NSMenuItem(
                title: strength.label,
                action: #selector(MenuTarget.selectMotionBlurStrength(_:)),
                keyEquivalent: ""
            )
            item.representedObject = strength.rawValue
            item.state = (model.crt.motionBlurStrength == strength) ? .on : .off
            item.target = MenuTarget.shared
            motionBlurStrengthMenu.addItem(item)
        }
        motionBlurStrengthItem.submenu = motionBlurStrengthMenu
        motionBlurMenu.addItem(motionBlurStrengthItem)
        motionBlurItem.submenu = motionBlurMenu
        crtMenu.addItem(motionBlurItem)

        crtMenu.addItem(.separator())

        let glassItem = NSMenuItem(title: "Glass", action: nil, keyEquivalent: "")
        let glassMenu = NSMenu()
        let glassEnabledItem = NSMenuItem(
            title: "Enabled",
            action: #selector(MenuTarget.toggleShatteredGlass(_:)),
            keyEquivalent: ""
        )
        glassEnabledItem.state = model.shatteredGlass.enabled ? .on : .off
        glassEnabledItem.target = MenuTarget.shared
        glassMenu.addItem(glassEnabledItem)
        glassMenu.addItem(.separator())

        let glassStrengthItem = NSMenuItem(title: "Strength", action: nil, keyEquivalent: "")
        let glassStrengthMenu = NSMenu()
        for strength in ShatteredGlassStrength.allCases {
            let item = NSMenuItem(
                title: strength.label,
                action: #selector(MenuTarget.selectShatteredGlassStrength(_:)),
                keyEquivalent: ""
            )
            item.representedObject = strength.rawValue
            item.state = (model.shatteredGlass.strength == strength) ? .on : .off
            item.target = MenuTarget.shared
            glassStrengthMenu.addItem(item)
        }
        glassStrengthItem.submenu = glassStrengthMenu
        glassMenu.addItem(glassStrengthItem)

        let glassPlacementItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        let glassPlacementMenu = NSMenu()
        for placement in ShatteredGlassPlacement.allCases {
            let item = NSMenuItem(
                title: placement.label,
                action: #selector(MenuTarget.selectShatteredGlassPlacement(_:)),
                keyEquivalent: ""
            )
            item.representedObject = placement.rawValue
            item.state = (model.shatteredGlass.placement == placement) ? .on : .off
            item.target = MenuTarget.shared
            glassPlacementMenu.addItem(item)
        }
        glassPlacementItem.submenu = glassPlacementMenu
        glassMenu.addItem(glassPlacementItem)

        glassItem.submenu = glassMenu
        crtMenu.addItem(glassItem)

        crtItem.submenu = crtMenu
        menu.addItem(crtItem)

        // Update the singleton's reference to the live model so the
        // selectors (which receive the NSMenuItem, not the model)
        // mutate the right object. The widget only ever has one
        // AppModel, so a singleton bridge is fine — and it keeps the
        // menu items free of captured closures (which NSMenu doesn't
        // accept anyway: actions must be ObjC selectors).
        MenuTarget.shared.model = model

        return menu
    }

    private static let badgePositionRows: [(String, [BadgePosition])] = [
        ("Top", [.topLeading, .top, .topTrailing]),
        ("Middle", [.leading, .center, .trailing]),
        ("Bottom", [.bottomLeading, .bottom, .bottomTrailing]),
    ]

    private static let bongoPositionRows: [(String, [BongoStageAnchor])] = [
        ("Middle", [.leading, .center, .trailing]),
        ("Bottom", [.bottomLeading, .bottom, .bottomTrailing]),
    ]

    private static func addPositionRows<Position: Equatable>(
        to menu: NSMenu,
        rows: [(String, [Position])],
        selected: Position?,
        title: KeyPath<Position, String>,
        rawValue: KeyPath<Position, String>,
        action: Selector
    ) {
        // NSMenu is one-dimensional, so disabled row headers and separators
        // mirror the alignment grid used in the settings overlay.
        for (rowIndex, (rowLabel, positions)) in rows.enumerated() {
            if rowIndex > 0 { menu.addItem(.separator()) }
            let header = NSMenuItem(title: rowLabel, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for position in positions {
                let item = NSMenuItem(
                    title: "    " + position[keyPath: title],
                    action: action,
                    keyEquivalent: ""
                )
                item.representedObject = position[keyPath: rawValue]
                item.state = (selected == position) ? .on : .off
                item.target = MenuTarget.shared
                menu.addItem(item)
            }
        }
    }
}

private enum CRTComponentKey: String {
    case curvation
    case vignette
    case chromaticAberration
    case scanlines
    case motionBlur
}

/// Single ObjC bridge object that every menu item targets. NSMenuItem
/// requires ObjC selectors and a target object reference, so we can't
/// hand it a Swift closure. Keeping a singleton (rather than
/// constructing a target per build) means the menu reconstruction logic
/// stays simple and the lifetime of the target outlives any single
/// right-click.
@MainActor
final class MenuTarget: NSObject {
    static let shared = MenuTarget()

    weak var model: AppModel?

    @objc func selectSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let size = BadgeSize(rawValue: raw),
              let model
        else { return }
        model.badgeSize = size
    }

    @objc func toggleReadoutVisibility(_ sender: NSMenuItem) {
        guard let model else { return }
        model.isReadoutVisible.toggle()
    }

    @objc func toggleReadoutWaveform(_ sender: NSMenuItem) {
        guard let model else { return }
        var s = model.readoutFontSettings
        s.waveform.toggle()
        model.readoutFontSettings = s
    }

    @objc func toggleReadoutTextShadow(_ sender: NSMenuItem) {
        guard let model else { return }
        var s = model.readoutFontSettings
        s.textShadow.toggle()
        model.readoutFontSettings = s
    }

    @objc func toggleReadoutTextGlow(_ sender: NSMenuItem) {
        guard let model else { return }
        var s = model.readoutFontSettings
        s.textGlow.toggle()
        model.readoutFontSettings = s
    }

    @objc func toggleBongoOverlay(_ sender: NSMenuItem) {
        guard let model else { return }
        model.toggleBongoOverlay()
    }

    @objc func toggleBongoStageDragLock(_ sender: NSMenuItem) {
        guard let model else { return }
        model.toggleBongoStageDragLock()
    }

    @objc func selectBongoCatPackBundled(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = BongoCatModelKind(rawValue: raw),
              let model
        else { return }
        model.bongoCatPack = .bundled(kind)
    }

    @objc func selectBongoCatPackImported(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              BongoCatPack.isSafeImportedFolderName(name),
              let model
        else { return }
        model.bongoCatPack = .imported(folderName: name)
    }

    @objc func reloadBongoModelsFromDisk(_ sender: NSMenuItem) {
        guard let model else { return }
        model.reloadBongoModelsFromDisk()
    }

    @objc func openBongoModelsFolder(_ sender: NSMenuItem) {
        guard let model else { return }
        model.openBongoModelsFolder()
    }

    @objc func selectBongoStageAnchor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let anchor = BongoStageAnchor(rawValue: raw),
              let model
        else { return }
        model.selectBongoStageAnchor(anchor)
    }

    @objc func selectBongoStageScaleTier(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let tier = BongoStageScaleTier(rawValue: raw),
              let model
        else { return }
        model.bongoStageScaleTier = tier
    }

    @objc func selectBongoInputTickRate(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let rate = BongoInputTickRate(rawValue: raw),
              let model
        else { return }
        model.bongoInputTickRate = rate
    }

    @objc func selectBongoMouseCursorSpace(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let space = BongoMouseCursorSpace(rawValue: raw),
              let model
        else { return }
        model.bongoMouseCursorSpace = space
    }

    @objc func selectBongoDesktopTint(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let tint = BongoDesktopMaskTint(rawValue: raw),
              let model
        else { return }
        model.bongoDesktopMaskTint = tint
    }

    @objc func toggleBongoDesktopMask(_ sender: NSMenuItem) {
        guard let model else { return }
        model.toggleBongoDesktopMask()
    }

    @objc func selectPosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let pos = BadgePosition(rawValue: raw),
              let model
        else { return }
        model.badgePosition = pos
    }

    @objc func selectReadoutWeight(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let weight = ReadoutFontWeight(rawValue: raw),
              let model
        else { return }
        var settings = model.readoutFontSettings
        settings.weight = weight
        model.readoutFontSettings = settings
    }

    @objc func selectReadoutElementShape(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let shape = ReadoutFontElementShape(rawValue: raw),
              let model
        else { return }
        var settings = model.readoutFontSettings
        settings.elementShape = shape
        model.readoutFontSettings = settings
    }

    @objc func toggleCRT(_ sender: NSMenuItem) {
        guard let model else { return }
        var settings = model.crt
        settings.enabled.toggle()
        model.crt = settings
    }

    @objc func toggleShatteredGlass(_ sender: NSMenuItem) {
        guard let model else { return }
        var settings = model.shatteredGlass
        settings.enabled.toggle()
        model.shatteredGlass = settings
    }

    @objc func toggleCRTComponent(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let key = CRTComponentKey(rawValue: raw),
              let model
        else { return }
        var settings = model.crt
        switch key {
        case .curvation: settings.curvation.toggle()
        case .vignette: settings.vignette.toggle()
        case .chromaticAberration: settings.chromaticAberration.toggle()
        case .scanlines: settings.scanlines.toggle()
        case .motionBlur: settings.motionBlur.toggle()
        }
        model.crt = settings
    }

    @objc func selectScanlineOpacity(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let opacity = ScanlineOpacity(rawValue: raw),
              let model
        else { return }
        var settings = model.crt
        settings.scanlineOpacity = opacity
        model.crt = settings
    }

    @objc func selectScanlineDensity(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let density = ScanlineDensity(rawValue: raw),
              let model
        else { return }
        var settings = model.crt
        settings.scanlineDensity = density
        model.crt = settings
    }

    @objc func selectMotionBlurStrength(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let strength = MotionBlurStrength(rawValue: raw),
              let model
        else { return }
        var settings = model.crt
        settings.motionBlurStrength = strength
        model.crt = settings
    }

    @objc func selectChromaticAberrationStrength(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let strength = ChromaticAberrationStrength(rawValue: raw),
              let model
        else { return }
        var settings = model.crt
        settings.chromaticAberrationStrength = strength
        model.crt = settings
    }

    @objc func selectCurvationStrength(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let strength = CurvationStrength(rawValue: raw),
              let model
        else { return }
        var settings = model.crt
        settings.curvationStrength = strength
        model.crt = settings
    }

    @objc func selectVignetteStrength(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let strength = VignetteStrength(rawValue: raw),
              let model
        else { return }
        var settings = model.crt
        settings.vignetteStrength = strength
        model.crt = settings
    }

    @objc func selectShatteredGlassStrength(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let strength = ShatteredGlassStrength(rawValue: raw),
              let model
        else { return }
        var settings = model.shatteredGlass
        settings.strength = strength
        model.shatteredGlass = settings
    }

    @objc func selectShatteredGlassPlacement(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let placement = ShatteredGlassPlacement(rawValue: raw),
              let model
        else { return }
        var settings = model.shatteredGlass
        settings.placement = placement
        model.shatteredGlass = settings
    }

}

// MARK: - Helpers

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
