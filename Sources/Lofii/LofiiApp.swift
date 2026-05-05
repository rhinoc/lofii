import SwiftUI
import AppKit
import OSLog
import Sparkle

@MainActor
@main
struct LofiiApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Sparkle auto-update (feed + EdDSA public key in embedded `Info.plist`).
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // Register both bundled fonts before any view tries to use them.
        // Doing it in App.init guarantees they're resolvable on the very
        // first render (including SwiftUI previews) — `Font.pixel(...)`
        // for the Doto readout text and `PixelIcon(...)` for every
        // glyph in the chrome.
        PixelFont.registerIfNeeded()
        PixelIcons.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup(id: "lofii-widget") {
            WidgetRootView()
                .environmentObject(model)
                .onAppear {
                    AppCommandBridge.install(model: model)
                }
                // Without this, SwiftUI keeps a ~28px top safe-area inset for
                // the (hidden) titlebar, leaving an empty transparent strip
                // above the rounded card.
                .ignoresSafeArea()
                .background(
                    WindowConfigurator(
                        alwaysOnTop: model.alwaysOnTop,
                        contentCornerRadius: model.widgetWindowContentCornerRadius
                    )
                )
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 400, height: 300)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("lofii") {
                Button("Toggle Widget") {
                    AppCommandBridge.toggleWidgetWindow()
                }
                .keyboardShortcut("w", modifiers: [.command])

                Divider()

                Button("Play / Pause") {
                    AppCommandBridge.togglePlayback()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Previous Scene") {
                    AppCommandBridge.previousStation()
                }
                // Command + arrows avoid colliding with any mode-local
                // key handling.
                .keyboardShortcut(.leftArrow, modifiers: [.command])

                Button("Next Scene") {
                    AppCommandBridge.nextStation()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])

                Button("Cycle Variant") {
                    AppCommandBridge.cycleVariant()
                }
                .keyboardShortcut("v", modifiers: [.command])

                Divider()

                Button("Toggle Visual Mode") {
                    AppCommandBridge.toggleVisualMode()
                }
                .keyboardShortcut("m", modifiers: [.command])

                Button("Next GIF") {
                    AppCommandBridge.nextGif()
                }
                .keyboardShortcut("g", modifiers: [])

                Divider()

                Button("Toggle Always on Top") {
                    AppCommandBridge.toggleAlwaysOnTop()
                }
                .keyboardShortcut("t", modifiers: [.command])

                Divider()

                Button("Check for Updates…") {
                    updaterController.checkForUpdates(nil)
                }
                .disabled(!updaterController.updater.canCheckForUpdates)
            }
        }

        MenuBarExtra("lofii", systemImage: "radio") {
            Button("Toggle Widget") {
                toggleWidgetWindow()
            }

            Divider()

            Button(model.isPlaying ? "Pause" : "Play") {
                model.togglePlayback()
            }

            Button("Previous Scene") {
                model.previousStation()
            }

            Button("Next Scene") {
                model.nextStation()
            }

            Divider()

            Toggle("Always on Top", isOn: Binding(
                get: { model.alwaysOnTop },
                set: { model.alwaysOnTop = $0 }
            ))

            Divider()

            Toggle("Debug Mode", isOn: Binding(
                get: { model.debugModeEnabled },
                set: { model.debugModeEnabled = $0 }
            ))
            .help("Developer overlays; readout title/artist repeat for marquee testing when on")

            Divider()

            Button("Check for Updates…") {
                updaterController.checkForUpdates(nil)
            }
            .disabled(!updaterController.updater.canCheckForUpdates)

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }

    private func toggleWidgetWindow() {
        if let window = WidgetFullscreenCoordinator.widgetWindow() {
            if window.isVisible {
                window.orderOut(nil)
                model.setWidgetWindowVisible(false)
            } else {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                model.setWidgetWindowVisible(true)
            }
            return
        }

        openWindow(id: "lofii-widget")
        model.setWidgetWindowVisible(true)
    }

    @Environment(\.openWindow) private var openWindow
}

@MainActor
private enum AppCommandState {
    static weak var model: AppModel?
}

private enum AppCommandBridge {
    @MainActor
    static func install(model: AppModel) {
        AppCommandState.model = model
    }

    static func toggleWidgetWindow() {
        Task { @MainActor in
            guard let model = AppCommandState.model else { return }
            if let window = WidgetFullscreenCoordinator.widgetWindow() {
                if window.isVisible {
                    window.orderOut(nil)
                    model.setWidgetWindowVisible(false)
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                    model.setWidgetWindowVisible(true)
                }
            }
        }
    }

    static func togglePlayback() {
        Task { @MainActor in
            AppCommandState.model?.togglePlayback()
        }
    }

    static func previousStation() {
        Task { @MainActor in
            AppCommandState.model?.previousStation()
        }
    }

    static func nextStation() {
        Task { @MainActor in
            AppCommandState.model?.nextStation()
        }
    }

    static func cycleVariant() {
        Task { @MainActor in
            AppCommandState.model?.cycleVariant()
        }
    }

    static func toggleVisualMode() {
        Task { @MainActor in
            AppCommandState.model?.toggleVisualMode()
        }
    }

    static func nextGif() {
        Task { @MainActor in
            AppCommandState.model?.nextGif()
        }
    }

    static func toggleAlwaysOnTop() {
        Task { @MainActor in
            AppCommandState.model?.alwaysOnTop.toggle()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set to true by `WidgetFullscreenCoordinator` when it had to strip
    /// `.canJoinAllSpaces` from the widget window's collectionBehavior
    /// to satisfy AppKit's "no fullscreen on canJoinAllSpaces" rule.
    /// Reset back to false after we've restored the flag in
    /// `windowDidExitFullScreen(_:)` below.
    fileprivate var didStripCanJoinAllSpaces = false
    fileprivate var isFullscreenTransitioning = false
    private var fullscreenEnterObserver: NSObjectProtocol?
    private var fullscreenExitObserver: NSObjectProtocol?
    private var occlusionObserver: NSObjectProtocol?
    private var miniaturizeObserver: NSObjectProtocol?
    private var deminiaturizeObserver: NSObjectProtocol?
    fileprivate let fullscreenLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "lofii",
        category: "fullscreen"
    )

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSApp.setActivationPolicy(.accessory)
            // Listen for fullscreen exit globally so we can restore the
            // `.canJoinAllSpaces` flag that
            // `WidgetFullscreenCoordinator.toggleFullscreen` had to
            // strip for the transition to be accepted by AppKit.
            // Without this, toggling fullscreen on/off would silently
            // turn off the "pinned across all Spaces" behavior even
            // though the pin glyph still reads as enabled.
            //
            // We pass `.main` so the block is documented as called on
            // the main thread; we still hop onto the MainActor inside
            // for Swift-6 strict-concurrency reasons (the closure
            // signature itself is non-isolated).
            fullscreenExitObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: nil,
                queue: .main
            ) { _ in
                // We don't need to read the notification payload here:
                // there is only one user-visible window in the app
                // (the widget), so any didExitFullScreenNotification
                // is the one we care about. Resolving the window via
                // `widgetWindow()` inside the MainActor block is both
                // safer (no captured non-Sendable Notification) and
                // simpler than threading `note.object` through
                // strict-concurrency boundaries.
                MainActor.assumeIsolated {
                    AppDelegate.shared?.handleDidExitFullscreen()
                }
            }
            fullscreenEnterObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    AppDelegate.shared?.handleDidEnterFullscreen()
                }
            }
            // Pause the GIF/Bongo rendering pipeline whenever the
            // widget window is fully occluded (covered by other apps, on a
            // hidden Space, or miniaturised to the Dock). This drops the
            // baseline CPU floor from ~10% to ~3% while the window is not
            // on screen — important for a "set-and-forget" lofi widget
            // that often lives behind other windows for hours.
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    AppDelegate.shared?.refreshWidgetWindowVisibility()
                }
            }
            miniaturizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMiniaturizeNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    AppDelegate.shared?.refreshWidgetWindowVisibility()
                }
            }
            deminiaturizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didDeminiaturizeNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    AppDelegate.shared?.refreshWidgetWindowVisibility()
                }
            }
            AppDelegate.shared = self
            fullscreenLogger.notice("App finished launching; fullscreen observers installed")
        }
    }

    @MainActor
    fileprivate func refreshWidgetWindowVisibility() {
        guard let window = WidgetFullscreenCoordinator.widgetWindow() else { return }
        let baseVisible = window.isVisible && !window.isMiniaturized
        guard baseVisible else {
            AppCommandState.model?.setWidgetWindowVisible(false)
            return
        }

        // `NSWindow.didChangeOcclusionState` often fires during native fullscreen
        // space transitions with **no** `.visible` bit even though the window is
        // still on-screen. `AppModel.shouldRenderStageMotion` pauses `MTKView` and passes **deltaTime 0**
        // into Live2D — so Bongo appears **frozen** for the whole fullscreen until
        // occlusion flips back after exit.
        if isFullscreenTransitioning {
            AppCommandState.model?.setWidgetWindowVisible(true)
            return
        }

        let occlusionOK = window.occlusionState.contains(.visible)
        let inNativeFullscreen = window.styleMask.contains(.fullScreen)
        let visible = occlusionOK || inNativeFullscreen
        AppCommandState.model?.setWidgetWindowVisible(visible)
    }

    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Weak singleton reference so the notification observer (which
    /// runs in a non-isolated context) can route into the live
    /// AppDelegate without capturing self in a way Swift 6 can't
    /// prove safe.
    @MainActor static weak var shared: AppDelegate?

    @MainActor
    private func handleDidEnterFullscreen() {
        guard let window = WidgetFullscreenCoordinator.widgetWindow() else {
            fullscreenLogger.error("didEnterFullscreen received but widgetWindow() returned nil")
            return
        }
        isFullscreenTransitioning = false
        WidgetWindowAppearance.applySystemFullscreenChrome(to: window, isFullscreen: true)
        fullscreenLogger.notice("Notification didEnterFullScreen: \(WidgetFullscreenCoordinator.debugDescription(for: window), privacy: .public)")
        window.level = .normal
        WidgetWindowAppearance.apply(to: window, isFullscreen: true)
        logStandardButtonStates(window, reason: "after handleDidEnterFullscreen")
        refreshWidgetWindowVisibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak window] in
            guard let self, let window else { return }
            self.logStandardButtonStates(window, reason: "0.35s after didEnterFullscreen")
        }
    }

    @MainActor
    private func handleDidExitFullscreen() {
        guard let window = WidgetFullscreenCoordinator.widgetWindow() else {
            fullscreenLogger.error("didExitFullscreen received but widgetWindow() returned nil")
            return
        }
        isFullscreenTransitioning = false
        WidgetWindowAppearance.applySystemFullscreenChrome(to: window, isFullscreen: false)
        fullscreenLogger.notice("Notification didExitFullScreen: \(WidgetFullscreenCoordinator.debugDescription(for: window), privacy: .public)")
        if didStripCanJoinAllSpaces {
            didStripCanJoinAllSpaces = false
            var behavior = window.collectionBehavior
            behavior.insert(.canJoinAllSpaces)
            window.collectionBehavior = behavior
            fullscreenLogger.notice("Restored canJoinAllSpaces after fullscreen exit: \(WidgetFullscreenCoordinator.debugDescription(for: window), privacy: .public)")
        }
        window.level = windowShouldFloat ? .floating : .normal
        WidgetWindowAppearance.apply(to: window, isFullscreen: false)
        refreshWidgetWindowVisibility()
    }

    @MainActor
    private func logStandardButtonStates(_ window: NSWindow, reason: String) {
        func describe(_ buttonType: NSWindow.ButtonType, name: String) -> String {
            guard let button = window.standardWindowButton(buttonType) else {
                return "\(name)=nil"
            }
            let actionName = button.action.map(NSStringFromSelector) ?? "nil"
            let targetName = button.target.map { NSStringFromClass(type(of: $0 as AnyObject)) } ?? "nil"
            return "\(name){hidden=\(button.isHidden), enabled=\(button.isEnabled), alpha=\(button.alphaValue), action=\(actionName), target=\(targetName), frame=\(NSStringFromRect(button.frame))}"
        }

        fullscreenLogger.notice(
            "Standard buttons \(reason, privacy: .public): \(describe(.closeButton, name: "close"), privacy: .public) \(describe(.miniaturizeButton, name: "mini"), privacy: .public) \(describe(.zoomButton, name: "zoom"), privacy: .public)"
        )
    }

    private var windowShouldFloat: Bool {
        let key = "lofii.alwaysOnTop"
        if UserDefaults.standard.object(forKey: key) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: key)
    }
}

private enum WidgetWindowAppearance {
    @MainActor
    static func apply(to window: NSWindow, isFullscreen: Bool, contentCornerRadius: CGFloat? = nil) {
        stripSystemChrome(from: window)
        applyStandardButtonVisibility(to: window, isFullscreen: isFullscreen)

        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        guard let layer = contentView.layer else { return }

        let resolvedRadius: CGFloat = {
            if isFullscreen { return 0 }
            if let r = contentCornerRadius, r > 0 { return r }
            if let r = AppCommandState.model?.widgetWindowContentCornerRadius, r > 0 { return r }
            return WidgetChromeMetrics.contentCornerRadius
        }()

        if isFullscreen {
            layer.cornerRadius = 0
            layer.cornerCurve = .continuous
            layer.masksToBounds = false
            layer.borderWidth = 0
            layer.borderColor = nil
            return
        }

        layer.cornerRadius = resolvedRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.borderWidth = 1
        layer.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
    }

    @MainActor
    static func applySystemFullscreenChrome(to window: NSWindow, isFullscreen: Bool) {
        window.titlebarAppearsTransparent = !isFullscreen
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none

        if isFullscreen {
            window.styleMask.remove(.fullSizeContentView)
            window.styleMask.formUnion([.titled, .closable, .miniaturizable, .resizable])
        } else {
            window.styleMask.formUnion([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        }
    }

    @MainActor
    private static func applyStandardButtonVisibility(to window: NSWindow, isFullscreen: Bool) {
        let closeButton = window.standardWindowButton(.closeButton)
        let miniaturizeButton = window.standardWindowButton(.miniaturizeButton)
        let zoomButton = window.standardWindowButton(.zoomButton)

        closeButton?.isHidden = !isFullscreen
        miniaturizeButton?.isHidden = true
        zoomButton?.isHidden = !isFullscreen

        closeButton?.isEnabled = true
        miniaturizeButton?.isEnabled = false
        if isFullscreen {
            zoomButton?.target = window
            zoomButton?.action = #selector(NSWindow.toggleFullScreen(_:))
            zoomButton?.isEnabled = true
        } else {
            zoomButton?.target = nil
            zoomButton?.action = nil
            zoomButton?.isEnabled = true
        }
    }

    @MainActor
    private static func stripSystemChrome(from window: NSWindow) {
        guard let frameView = window.contentView?.superview else { return }

        func scrub(_ view: NSView) {
            let className = NSStringFromClass(type(of: view))
            let looksLikeTitlebarDecoration =
                className.localizedCaseInsensitiveContains("titlebar") ||
                className.localizedCaseInsensitiveContains("toolbar") ||
                className.localizedCaseInsensitiveContains("decoration")

            if looksLikeTitlebarDecoration {
                return
            }

            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
            view.layer?.borderWidth = 0
            view.layer?.borderColor = nil

            if let effectView = view as? NSVisualEffectView {
                effectView.material = .underWindowBackground
                effectView.state = .inactive
                effectView.isEmphasized = false
            }

            for child in view.subviews {
                scrub(child)
            }
        }

        scrub(frameView)
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    let alwaysOnTop: Bool
    let contentCornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            applyConfiguration(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            applyConfiguration(to: nsView.window)
        }
    }

    private func applyConfiguration(to window: NSWindow?) {
        guard let window else { return }

        // Do NOT runtime-swap the system-created NSWindow subclass here.
        // That earlier `object_setClass(..., FirstMouseWindow.self)` hack
        // made first-click chrome interactions feel nicer, but it also
        // destabilised AppKit's private KVO bookkeeping for titlebar views
        // during fullscreen entry and caused a crash in
        // `NSTitlebarView viewWillMoveToWindow`.

        if window.delegate !== AppDelegate.shared {
            window.delegate = AppDelegate.shared
            AppDelegate.shared?.fullscreenLogger.notice(
                "Attached AppDelegate as window delegate: \(WidgetFullscreenCoordinator.debugDescription(for: window), privacy: .public)"
            )
        }

        if AppDelegate.shared?.isFullscreenTransitioning == true {
            AppDelegate.shared?.fullscreenLogger.debug(
                "Skipped window reconfiguration during fullscreen transition: \(WidgetFullscreenCoordinator.debugDescription(for: window), privacy: .public)"
            )
            return
        }

        let isFullscreen = window.styleMask.contains(.fullScreen)

        // Transparent + edge-to-edge: SwiftUI would otherwise reserve ~28px at
        // the top for the (hidden) titlebar, which manifested as a stray gap
        // above the rounded card.
        WidgetWindowAppearance.applySystemFullscreenChrome(to: window, isFullscreen: isFullscreen)
        // `.resizable` is REQUIRED for `toggleFullScreen(_:)` to work —
        // AppKit silently no-ops the call on a window that can't be
        // resized (which is exactly what `.windowResizability(.contentSize)`
        // gives us at the SwiftUI layer: a content-driven size, but no
        // `.resizable` style bit on the underlying NSWindow). Without
        // this, the green traffic-light dot did nothing on click.
        window.styleMask.insert(.resizable)
        window.toolbar = nil
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.setContentBorderThickness(0, for: .maxY)

        // Enforce the minimum content size at the AppKit level. SwiftUI's
        // `.frame(minWidth:, minHeight:)` doesn't reliably propagate to the
        // NSWindow when the root view is wrapped in a GeometryReader (the
        // GeometryReader swallows the size proposal), so the user could
        // otherwise drag the window narrow enough that the TopChrome HStack
        // overflowed and the horizontal padding got eaten. Setting
        // contentMinSize directly stops the drag at a safe point.
        let minWidth: CGFloat = 200
        let minHeight: CGFloat = 130
        if window.contentMinSize.width < minWidth || window.contentMinSize.height < minHeight {
            window.contentMinSize = NSSize(width: minWidth, height: minHeight)
        }

        // AppKit's window shadow is rectangular and follows `contentView.frame`,
        // not our rounded contentView, so it drew a square shadow around our
        // rounded card. We let CoreAnimation paint a soft shadow on the
        // layer instead, which respects the cornerRadius.
        window.hasShadow = false

        window.level = isFullscreen ? .normal : (alwaysOnTop ? .floating : .normal)
        WidgetWindowAppearance.apply(to: window, isFullscreen: isFullscreen, contentCornerRadius: contentCornerRadius)
        // `.fullScreenPrimary` lets us call `toggleFullScreen(_:)` from our
        // green traffic-light dot. `.fullScreenAuxiliary` (the previous
        // value) explicitly disallows that and would have made the button
        // a no-op.
        //
        // Important: do NOT combine `.canJoinAllSpaces` with
        // `.fullScreenPrimary` while the window is in normal (non-
        // fullscreen) state — AppKit treats canJoinAllSpaces windows as
        // utility/auxiliary and refuses to honor the fullscreen request,
        // which is exactly why the green dot did nothing while the widget
        // was pinned-on-top. We keep canJoinAllSpaces only when the
        // window is NOT fullscreen, and `WidgetFullscreenCoordinator`
        // (below) temporarily strips it for the duration of the
        // toggle so the transition itself goes through.
        if isFullscreen {
            window.collectionBehavior = [.fullScreenPrimary]
        } else {
            window.collectionBehavior = alwaysOnTop
                ? [.canJoinAllSpaces, .fullScreenPrimary]
                : [.fullScreenPrimary]
        }

        AppDelegate.shared?.fullscreenLogger.debug(
            "Applied window configuration: alwaysOnTop=\(alwaysOnTop) \(WidgetFullscreenCoordinator.debugDescription(for: window), privacy: .public)"
        )
    }
}

/// NSWindow subclass that opts every hosted view into "first-mouse"
/// click handling. By default AppKit swallows the first click on a
/// non-key window and only uses it to bring the window into focus, so
/// our transparent overlay buttons (close, fullscreen, etc.) appeared
/// "dead" until you'd clicked twice. We override `sendEvent(_:)` so
/// that whenever the window receives a primary mouseDown while it
/// isn't yet key, we proactively make it key BEFORE the event is
/// dispatched to the SwiftUI hit-test pipeline — that way the click
/// counts both as the activation gesture AND as the button press,
/// rather than being swallowed by the activation only.
final class FirstMouseWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown && !isKeyWindow {
            // Bring the window key first, so the subsequent
            // hit-test sees it as the active window (which is what
            // unblocks SwiftUI Button hit testing on macOS).
            makeKeyAndOrderFront(nil)
        }
        super.sendEvent(event)
    }

    // Borderless windows default to canBecomeKey = false, which is
    // why our `.hiddenTitleBar`-styled widget needed an explicit
    // override to ever take focus. Without this even the
    // `makeKeyAndOrderFront` call above would no-op.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Centralised helper for the "toggle fullscreen" gesture that the green
/// traffic-light dot wires into. Lives outside the SwiftUI layer because
/// it has to mutate AppKit window state (`collectionBehavior`) before and
/// after the transition — see comment inside.
@MainActor
enum WidgetFullscreenCoordinator {
    private static var logger: Logger? {
        AppDelegate.shared?.fullscreenLogger
    }

    /// Find the widget's NSWindow without relying on `keyWindow`. The
    /// caller may be a click on a non-key window (which is exactly the
    /// case we care about for first-click responsiveness), so
    /// `NSApp.keyWindow` would return nil or some other app's window.
    static func widgetWindow() -> NSWindow? {
        NSApp.windows.first(where: { !($0 is NSPanel) })
            ?? NSApp.keyWindow
    }

    static func debugDescription(for window: NSWindow) -> String {
        let styleMaskFlags = [
            ("fullScreen", window.styleMask.contains(.fullScreen)),
            ("resizable", window.styleMask.contains(.resizable)),
            ("fullSizeContentView", window.styleMask.contains(.fullSizeContentView)),
            ("borderless", window.styleMask.contains(.borderless))
        ]
        .filter(\.1)
        .map(\.0)
        .joined(separator: ",")

        let behaviorFlags = [
            ("canJoinAllSpaces", window.collectionBehavior.contains(.canJoinAllSpaces)),
            ("fullScreenPrimary", window.collectionBehavior.contains(.fullScreenPrimary)),
            ("fullScreenAuxiliary", window.collectionBehavior.contains(.fullScreenAuxiliary)),
            ("managed", window.collectionBehavior.contains(.managed)),
            ("transient", window.collectionBehavior.contains(.transient))
        ]
        .filter(\.1)
        .map(\.0)
        .joined(separator: ",")

        return "windowNumber=\(window.windowNumber) " +
            "title=\(window.title.isEmpty ? "<untitled>" : window.title) " +
            "isVisible=\(window.isVisible) isKey=\(window.isKeyWindow) isMain=\(window.isMainWindow) " +
            "styleMaskRaw=\(window.styleMask.rawValue) [\(styleMaskFlags)] " +
            "collectionBehaviorRaw=\(window.collectionBehavior.rawValue) [\(behaviorFlags)] " +
            "level=\(window.level.rawValue) frame=\(NSStringFromRect(window.frame))"
    }

    static func toggleFullscreen() {
        guard let window = widgetWindow() else {
            logger?.error("toggleFullscreen requested but widgetWindow() returned nil")
            return
        }
        logger?.notice("toggleFullscreen requested: \(debugDescription(for: window), privacy: .public)")
        if !window.styleMask.contains(.fullScreen) {
            WidgetWindowAppearance.applySystemFullscreenChrome(to: window, isFullscreen: true)
            logger?.notice("Prepared titled/closable style before fullscreen transition: \(debugDescription(for: window), privacy: .public)")
        }
        // AppKit refuses to enter fullscreen on a window whose
        // collectionBehavior contains `.canJoinAllSpaces` (it treats such
        // windows as utility surfaces). Strip that flag for the duration
        // of the transition; AppDelegate listens for the matching
        // didExitFullScreenNotification and reapplies the original
        // behavior so a "pinned" widget stays pinned after the user
        // leaves fullscreen.
        if !window.styleMask.contains(.fullScreen)
            && window.collectionBehavior.contains(.canJoinAllSpaces) {
            window.collectionBehavior = [.fullScreenPrimary]
            AppDelegate.shared?.didStripCanJoinAllSpaces = true
            logger?.notice("Stripped canJoinAllSpaces before entering fullscreen: \(debugDescription(for: window), privacy: .public)")
        }
        window.toggleFullScreen(nil)
        logger?.notice("toggleFullScreen(nil) dispatched: \(debugDescription(for: window), privacy: .public)")
    }

    static func closeWidget() {
        widgetWindow()?.close()
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillEnterFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            fullscreenLogger.error("windowWillEnterFullScreen received without NSWindow payload")
            return
        }
        isFullscreenTransitioning = true
        fullscreenLogger.notice("Delegate windowWillEnterFullScreen: \(WidgetFullscreenCoordinator.debugDescription(for: window), privacy: .public)")
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            fullscreenLogger.error("windowDidEnterFullScreen received without NSWindow payload")
            return
        }
        fullscreenLogger.notice("Delegate windowDidEnterFullScreen: \(WidgetFullscreenCoordinator.debugDescription(for: window), privacy: .public)")
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            fullscreenLogger.error("windowWillExitFullScreen received without NSWindow payload")
            return
        }
        isFullscreenTransitioning = true
        fullscreenLogger.notice("Delegate windowWillExitFullScreen: \(WidgetFullscreenCoordinator.debugDescription(for: window), privacy: .public)")
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            fullscreenLogger.error("windowDidExitFullScreen received without NSWindow payload")
            return
        }
        fullscreenLogger.notice("Delegate windowDidExitFullScreen: \(WidgetFullscreenCoordinator.debugDescription(for: window), privacy: .public)")
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        isFullscreenTransitioning = false
        fullscreenLogger.error("Delegate windowDidFailToEnterFullScreen: \(WidgetFullscreenCoordinator.debugDescription(for: window), privacy: .public)")
    }

    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        isFullscreenTransitioning = false
        fullscreenLogger.error("Delegate windowDidFailToExitFullScreen: \(WidgetFullscreenCoordinator.debugDescription(for: window), privacy: .public)")
    }

}
