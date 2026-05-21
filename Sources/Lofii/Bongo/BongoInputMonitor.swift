import AppKit
import CoreGraphics

// MARK: - Key Mapping

private enum KeySide { case left, right }

private let keySideMap: [CGKeyCode: KeySide] = {
    let leftCodes: [CGKeyCode] = [
        53,             // Escape
        50,10,18,19,20,21,23,  // ` 1 2 3 4 5
        48,12,13,14,15,17,     // Tab Q W E R T
        57,0,1,2,3,5,          // Caps A S D F G
        56,6,7,8,9,11,         // Shift-L Z X C V B
        49,                    // Space
    ]
    let rightCodes: [CGKeyCode] = [
        22,26,28,25,29,27,24,51,
        16,32,34,31,35,33,30,42,
        4,38,40,37,41,39,36,
        45,46,43,47,44,
        60,
        123,124,125,126,
    ]
    var map = [CGKeyCode: KeySide]()
    for k in leftCodes  { map[k] = .left  }
    for k in rightCodes { map[k] = .right }
    return map
}()

/// Physical arrow keys on macOS (`NSEvent.keyCode`).
private let arrowKeyCodes: Set<CGKeyCode> = [123, 124, 125, 126]

// MARK: - Per-stem key codes (US ANSI, macOS virtual key codes)

/// Maps `left-keys/<stem>.png` stem names to hardware key codes. Only stems listed in the
/// active pack’s `left-keys` folder participate in overlay + left-hand params; unknown
/// stems in the folder are ignored until a mapping is added here.
private enum BongoInputKeyBindings {
    static let stemToKeyCodes: [String: [CGKeyCode]] = [
        "Escape": [53],
        "BackQuote": [50],
        "Num1": [18], "Num2": [19], "Num3": [20], "Num4": [21], "Num5": [23],
        "Num6": [22], "Num7": [26], "Num8": [28], "Num9": [25], "Num0": [29],
        "Minus": [27], "Equal": [24],
        "Backspace": [51],
        "Tab": [48],
        "KeyQ": [12], "KeyW": [13], "KeyE": [14], "KeyR": [15], "KeyT": [17],
        "KeyY": [16], "KeyU": [32], "KeyI": [34], "KeyO": [31], "KeyP": [35],
        "BracketLeft": [33], "BracketRight": [30], "Backslash": [42],
        "CapsLock": [57],
        "KeyA": [0], "KeyS": [1], "KeyD": [2], "KeyF": [3], "KeyG": [5], "KeyH": [4],
        "KeyJ": [38], "KeyK": [40], "KeyL": [37],
        "Semicolon": [41], "Quote": [39],
        "Return": [36],
        "ShiftLeft": [56], "ShiftRight": [60],
        "Shift": [56, 60],
        "KeyZ": [6], "KeyX": [7], "KeyC": [8], "KeyV": [9], "KeyB": [11],
        "KeyN": [45], "KeyM": [46],
        "Comma": [43], "Period": [47], "Slash": [44],
        "ControlLeft": [59], "ControlRight": [62],
        "Control": [59, 62],
        "Fn": [63],
        "Alt": [58], "AltGr": [61],
        "Meta": [55, 54],
        "Space": [49],
        "Delete": [117],
        "ArrowLeft": [123], "ArrowRight": [124], "ArrowDown": [125], "ArrowUp": [126],
        "LeftArrow": [123], "RightArrow": [124], "DownArrow": [125], "UpArrow": [126],
    ]

    /// Longer stem names win when two supported images map to the same key code
    /// (e.g. `ControlLeft` vs `Control`).
    static func keyCodeToOverlayStem(supported: Set<String>) -> [CGKeyCode: String] {
        let sorted = supported.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            return a < b
        }
        var out: [CGKeyCode: String] = [:]
        for stem in sorted {
            guard let codes = stemToKeyCodes[stem], !codes.isEmpty else { continue }
            for code in codes where out[code] == nil {
                out[code] = stem
            }
        }
        return out
    }

    /// Generic “right hand on keyboard” (`CatParamRightHandDown`) only when the pack
    /// actually includes art for at least one key on the physical right half — so minimal
    /// packs (e.g. only `Space`) do not react to the entire right side of the keyboard.
    /// Packs whose only right-half keys are **arrow keys** (handled as overlays) stay `false`
    /// so models without `CatParamRightHandDown` still work.
    static func modelUsesRightHalfTyping(supported: Set<String>) -> Bool {
        let arrowOnlyCodes: Set<CGKeyCode> = [123, 124, 125, 126]
        for stem in supported {
            guard let codes = stemToKeyCodes[stem] else { continue }
            for code in codes where keySideMap[code] == .right {
                if !arrowOnlyCodes.contains(code) {
                    return true
                }
            }
        }
        return false
    }
}

// MARK: - BongoInputMonitor

@MainActor
final class BongoInputMonitor {
    typealias ParamCallback = @MainActor @Sendable ([(String, Double)]) -> Void
    typealias KeyCallback   = @MainActor @Sendable (String, Bool) -> Void  // (imageName, pressed)

    /// `AXTrustedCheckOptionPrompt` must only run from an explicit user action.
    /// Startup and app-activation checks stay silent so a stale TCC entry does
    /// not produce the system sheet on every launch.
    private static var didPresentAXTrustPromptThisProcess = false

    private let paramCallback: ParamCallback
    private let keyCallback:   KeyCallback
    private let keyCodeToOverlayStem: [CGKeyCode: String]
    private let emitsAggregateRightHandTyping: Bool
    /// Optional `resources/bongo-arrow-overlay-params.json`: overlay stem -> extra Live2D param Id.
    private let overlayAccessoryLive2DParamByStem: [String: String]

    private var keyboardMonitor:       Any?
    private var mouseMonitor:          Any?
    private var localKeyboardMonitor:  Any?
    private var localMouseMonitor:     Any?
    private var didBecomeActiveObserver: NSObjectProtocol?

    private var activeKeyImage: String?
    private var rightKeyHeld   = false
    private var leftMouseHeld  = false
    private var rightMouseHeld = false

    init(
        paramCallback: @escaping ParamCallback,
        keyCallback: @escaping KeyCallback,
        supportedKeyImages: Set<String>,
        overlayAccessoryLive2DParamByStem: [String: String] = [:]
    ) {
        self.paramCallback = paramCallback
        self.keyCallback   = keyCallback
        self.keyCodeToOverlayStem = BongoInputKeyBindings.keyCodeToOverlayStem(supported: supportedKeyImages)
        self.emitsAggregateRightHandTyping = BongoInputKeyBindings.modelUsesRightHalfTyping(supported: supportedKeyImages)
        self.overlayAccessoryLive2DParamByStem = overlayAccessoryLive2DParamByStem
    }

    // MARK: Start / Stop

    func start() {
        guard localKeyboardMonitor == nil else { return }

        installTrustedGlobalMonitorsIfNeeded()

        // Local monitors receive keyboard / mouse while this process is active
        // (including when our widget window is key). Global monitors only
        // see events targeted at *other* applications.
        localKeyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            Task { @MainActor [weak self] in self?.handleKey(event) }
            return event
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
        ) { [weak self] event in
            guard let self else { return event }
            Task { @MainActor [weak self] in self?.handleMouse(event) }
            return event
        }

        if didBecomeActiveObserver == nil {
            didBecomeActiveObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // Run synchronously on the main queue: avoids queuing multiple
                // `installTrusted…` passes before `keyboardMonitor` is set (and
                // avoids stacking several deferred MainActor tasks at launch).
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.installTrustedGlobalMonitorsIfNeeded()
                }
            }
        }
    }

    @discardableResult
    static func requestAccessibilityTrustPromptIfNeeded() -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let silentOptions = [promptKey: false] as CFDictionary

        guard !AXIsProcessTrustedWithOptions(silentOptions) else { return true }
        guard !didPresentAXTrustPromptThisProcess else { return false }

        didPresentAXTrustPromptThisProcess = true
        let promptOptions = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(promptOptions)
    }

    /// Re-register global monitors when Accessibility is granted. This path is
    /// intentionally silent; prompting belongs to explicit Bongo enable actions.
    private func installTrustedGlobalMonitorsIfNeeded() {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let silentOptions = [promptKey: false] as CFDictionary

        guard AXIsProcessTrustedWithOptions(silentOptions) else { return }
        registerGlobalMonitorsIfTrusted()
    }

    private func registerGlobalMonitorsIfTrusted() {
        if keyboardMonitor == nil {
            keyboardMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.keyDown, .keyUp]
            ) { [weak self] event in
                Task { @MainActor [weak self] in self?.handleKey(event) }
            }
        }

        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
            ) { [weak self] event in
                Task { @MainActor [weak self] in self?.handleMouse(event) }
            }
        }
    }

    func stop() {
        if let o = didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(o)
            didBecomeActiveObserver = nil
        }
        if let m = keyboardMonitor       { NSEvent.removeMonitor(m); keyboardMonitor       = nil }
        if let m = localKeyboardMonitor  { NSEvent.removeMonitor(m); localKeyboardMonitor  = nil }
        if let m = mouseMonitor          { NSEvent.removeMonitor(m); mouseMonitor          = nil }
        if let m = localMouseMonitor     { NSEvent.removeMonitor(m); localMouseMonitor     = nil }

        var resetParams: [(String, Double)] = [
            ("CatParamLeftHandDown",  0.0),
            ("CatParamRightHandDown", 0.0),
            ("ParamMouseLeftDown",    0.0),
            ("ParamMouseRightDown",   0.0),
        ]
        for pid in Set(overlayAccessoryLive2DParamByStem.values) {
            resetParams.append((pid, 0.0))
        }
        emitParams(resetParams)
        activeKeyImage = nil; rightKeyHeld = false
        leftMouseHeld = false; rightMouseHeld = false
    }

    func reconcilePressedMouseButtons(_ pressedButtons: Int = NSEvent.pressedMouseButtons) {
        let leftPressed = pressedButtons & (1 << 0) != 0
        let rightPressed = pressedButtons & (1 << 1) != 0

        setLeftMouseHeld(leftPressed)
        setRightMouseHeld(rightPressed)
    }

    // MARK: Private handlers

    private func handleKey(_ event: NSEvent) {
        let code = CGKeyCode(event.keyCode)
        let pressed = event.type == .keyDown

        if let imageName = keyCodeToOverlayStem[code] {
            if pressed {
                guard activeKeyImage != imageName else { return }
                activeKeyImage = imageName
                keyCallback(imageName, true)
                var batch: [(String, Double)] = [("CatParamLeftHandDown", 1.0)]
                if let accessory = overlayAccessoryLive2DParamByStem[imageName] {
                    batch.append((accessory, 1.0))
                }
                emitParams(batch)
            } else if activeKeyImage == imageName {
                activeKeyImage = nil
                keyCallback(imageName, false)
                var batch: [(String, Double)] = [("CatParamLeftHandDown", 0.0)]
                if let accessory = overlayAccessoryLive2DParamByStem[imageName] {
                    batch.append((accessory, 0.0))
                }
                emitParams(batch)
            }
            return
        }

        // Many packs have no `Arrow*.png` but still drive paws via `CatParamRightHandDown`.
        // Do not gate arrow keys on `emitsAggregateRightHandTyping` (minimal WASD-only packs).
        let treatAsRightTyping = emitsAggregateRightHandTyping || arrowKeyCodes.contains(code)
        if treatAsRightTyping, keySideMap[code] == .right {
            guard rightKeyHeld != pressed else { return }
            rightKeyHeld = pressed
            emitParams([("CatParamRightHandDown", pressed ? 1.0 : 0.0)])
        }
    }

    private func handleMouse(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            setLeftMouseHeld(true)
        case .leftMouseUp:
            setLeftMouseHeld(false)
        case .rightMouseDown:
            setRightMouseHeld(true)
        case .rightMouseUp:
            setRightMouseHeld(false)
        default:
            break
        }
    }

    private func setLeftMouseHeld(_ held: Bool) {
        guard leftMouseHeld != held else { return }
        leftMouseHeld = held
        emitParams([("ParamMouseLeftDown", held ? 1.0 : 0.0)])
    }

    private func setRightMouseHeld(_ held: Bool) {
        guard rightMouseHeld != held else { return }
        rightMouseHeld = held
        emitParams([("ParamMouseRightDown", held ? 1.0 : 0.0)])
    }

    private func emitParams(_ params: [(String, Double)]) {
        paramCallback(params)
    }
}
