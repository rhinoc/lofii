import SwiftUI
import WebKit

private struct BilibiliLiveRoomResolution: Decodable, Equatable {
    struct DataPayload: Decodable, Equatable {
        let roomID: Int
        let liveStatus: Int

        enum CodingKeys: String, CodingKey {
            case roomID = "room_id"
            case liveStatus = "live_status"
        }
    }

    let code: Int
    let data: DataPayload?
}

enum BilibiliLivePlaybackEvent: Equatable {
    case ready
    case playing
    case mutedAutoplay
    case notAutoplay
    case paused
    case live
    case offline
    case replay

    var logValue: String {
        switch self {
        case .ready: return "ready"
        case .playing: return "playing"
        case .mutedAutoplay: return "mutedAutoplay"
        case .notAutoplay: return "notAutoplay"
        case .paused: return "paused"
        case .live: return "live"
        case .offline: return "offline"
        case .replay: return "replay"
        }
    }
}

struct BilibiliLivePlayerView: NSViewRepresentable {
    let roomID: Int
    let isPlaying: Bool
    let volume: Double
    let videoVisible: Bool
    var onPlaybackEvent: (BilibiliLivePlaybackEvent) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPlaybackEvent: onPlaybackEvent)
    }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "lofiiBilibiliLive")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.isHidden = false
        webView.allowsBackForwardNavigationGestures = false
        context.coordinator.webView = webView
        context.coordinator.load(
            roomID: roomID,
            isPlaying: isPlaying,
            volume: volume,
            videoVisible: videoVisible
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onPlaybackEvent = onPlaybackEvent
        context.coordinator.webView = webView
        context.coordinator.load(
            roomID: roomID,
            isPlaying: isPlaying,
            volume: volume,
            videoVisible: videoVisible
        )
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "lofiiBilibiliLive")
        nsView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var onPlaybackEvent: (BilibiliLivePlaybackEvent) -> Void

        private var loadedRoomID: Int?
        private var pendingPlaying = false
        private var pendingVolume = 0.58
        private var pendingVideoVisible = false
        private var playerReady = false
        private var resolveTask: Task<Void, Never>?
        private var loadToken = UUID()

        init(onPlaybackEvent: @escaping (BilibiliLivePlaybackEvent) -> Void) {
            self.onPlaybackEvent = onPlaybackEvent
        }

        func load(roomID: Int, isPlaying: Bool, volume: Double, videoVisible: Bool) {
            pendingPlaying = isPlaying
            pendingVolume = volume.clamped(to: 0...1)
            pendingVideoVisible = videoVisible

            if loadedRoomID != roomID {
                loadedRoomID = roomID
                playerReady = false
                resolveTask?.cancel()
                let token = UUID()
                loadToken = token
                webView?.loadHTMLString(Self.loadingHTML(videoVisible: videoVisible), baseURL: URL(string: "https://lofii.local/"))
                resolveTask = Task { [weak self] in
                    let resolution = await Self.resolveRoomID(roomID)
                    await MainActor.run {
                        guard let self, self.loadToken == token, self.loadedRoomID == roomID else { return }
                        let playbackRoomID = resolution?.data?.roomID ?? roomID
                        self.webView?.loadHTMLString(
                            Self.html(
                                sourceRoomID: roomID,
                                playbackRoomID: playbackRoomID,
                                liveStatus: resolution?.data?.liveStatus,
                                isPlaying: self.pendingPlaying,
                                volume: self.pendingVolume,
                                videoVisible: self.pendingVideoVisible
                            ),
                            baseURL: URL(string: "https://lofii.local/")
                        )
                        if let liveStatus = resolution?.data?.liveStatus {
                            switch liveStatus {
                            case 0:
                                self.onPlaybackEvent(.offline)
                            case 1:
                                self.onPlaybackEvent(.live)
                            case 2:
                                self.onPlaybackEvent(.replay)
                            default:
                                break
                            }
                        }
                    }
                }
                return
            }

            applyState()
        }

        func stop() {
            resolveTask?.cancel()
            webView?.evaluateJavaScript("window.lofiiStop?.()")
            webView?.stopLoading()
        }

        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            Task { @MainActor in
                guard let body = message.body as? [String: Any],
                      let type = body["type"] as? String,
                      type == "event",
                      let value = body["event"] as? String
                else { return }

                let event: BilibiliLivePlaybackEvent? = switch value {
                case "ready": .ready
                case "playing": .playing
                case "MutePlay": .mutedAutoplay
                case "NotAutoPlay": .notAutoplay
                case "paused": .paused
                case "live": .live
                case "offline": .offline
                case "replay": .replay
                default: nil
                }
                guard let event else { return }

                if event == .ready {
                    playerReady = true
                    applyState()
                }
                onPlaybackEvent(event)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyState()
        }

        private func applyState() {
            guard playerReady else { return }
            let volumePercent = Int((pendingVolume * 100).rounded())
            let script = """
            window.lofiiSetState?.({
              playing: \(pendingPlaying ? "true" : "false"),
              volume: \(volumePercent),
              videoVisible: \(pendingVideoVisible ? "true" : "false")
            });
            """
            webView?.evaluateJavaScript(script)
        }

        private static func resolveRoomID(_ roomID: Int) async -> BilibiliLiveRoomResolution? {
            guard let url = URL(string: "https://api.live.bilibili.com/room/v1/Room/room_init?id=\(roomID)") else {
                return nil
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    return nil
                }
                let resolution = try JSONDecoder().decode(BilibiliLiveRoomResolution.self, from: data)
                guard resolution.code == 0 else { return nil }
                return resolution
            } catch {
                return nil
            }
        }

        private static func loadingHTML(videoVisible: Bool) -> String {
            """
            <!doctype html>
            <html>
            <head>
              <meta name="viewport" content="width=device-width,initial-scale=1">
              <style>
                html, body {
                  margin: 0;
                  width: 100%;
                  height: 100%;
                  overflow: hidden;
                  background: \(videoVisible ? "#000" : "transparent");
                }
              </style>
            </head>
            <body></body>
            </html>
            """
        }

        private static func html(
            sourceRoomID: Int,
            playbackRoomID: Int,
            liveStatus: Int?,
            isPlaying: Bool,
            volume: Double,
            videoVisible: Bool
        ) -> String {
            let volumePercent = Int((volume.clamped(to: 0...1) * 100).rounded())
            let playerURL: String
            if playbackRoomID > 1000 {
                playerURL = "https://www.bilibili.com/blackboard/live/live-activity-player.html?cid=\(playbackRoomID)&sendpanel=0&quality=0&entrance=0&reload=0&danmaku=0&fullscreen=0&send=0&recommend=0&logo=0&mute=0&enableCtrlUI=0&enableAutoPlayTips=0"
            } else {
                playerURL = "https://www.bilibili.com/blackboard/live/live-activity-h5-player.html?cid=\(playbackRoomID)&type=room&controlbar=0&inputbar=0&logo=0&entrance=0&danmaku=0"
            }
            return """
            <!doctype html>
            <html>
            <head>
              <meta name="viewport" content="width=device-width,initial-scale=1">
              <style>
                html, body {
                  margin: 0;
                  width: 100%;
                  height: 100%;
                  overflow: hidden;
                  background: transparent;
                }
                body.video {
                  background: #000;
                }
                #player {
                  position: absolute;
                  left: 50%;
                  top: 50%;
                  width: max(100vw, calc(100vh * 16 / 9));
                  height: max(100vh, calc(100vw * 9 / 16));
                  transform: translate(-50%, -50%);
                  opacity: 1;
                  pointer-events: none;
                }
                body.audio #player {
                  left: 0;
                  top: 0;
                  width: 1px;
                  height: 1px;
                  transform: none;
                  opacity: 0;
                  pointer-events: none;
                }
                iframe {
                  width: 100%;
                  height: 100%;
                  border: 0;
                }
              </style>
            </head>
            <body class="\(videoVisible ? "video" : "audio")">
              <iframe
                id="player"
                allow="autoplay; encrypted-media"
                allowfullscreen="true"
                frameborder="0"
                scrolling="no"></iframe>
              <script>
                const iframe = document.getElementById('player');
                let ready = false;
                let lastState = {
                  playing: \(isPlaying ? "true" : "false"),
                  volume: \(volumePercent),
                  videoVisible: \(videoVisible ? "true" : "false")
                };
                const sourceRoomID = \(sourceRoomID);
                const playbackRoomID = \(playbackRoomID);
                const initialLiveStatus = \(liveStatus.map(String.init) ?? "null");

                function post(eventName) {
                  try {
                    window.webkit.messageHandlers.lofiiBilibiliLive.postMessage({
                      type: 'event',
                      event: eventName
                    });
                  } catch (_) {}
                }

                function sendPlayer(payload) {
                  try {
                    iframe.contentWindow.postMessage('setPlayer-' + JSON.stringify(payload), '*');
                  } catch (_) {}
                }

                function applyState() {
                  document.body.className = lastState.videoVisible ? 'video' : 'audio';
                  if (!ready) return;
                  sendPlayer({ type: 'changeVolume', value: { volume: lastState.volume } });
                  sendPlayer({ type: 'setDanmaku', value: { display: false } });
                  sendPlayer({ type: 'play', value: lastState.playing });
                }

                window.lofiiSetState = function(state) {
                  lastState = state;
                  applyState();
                };

                window.lofiiStop = function() {
                  sendPlayer({ type: 'play', value: false });
                };

                iframe.addEventListener('load', function() {
                  ready = true;
                  post('ready');
                  if (initialLiveStatus === 0) post('offline');
                  if (initialLiveStatus === 1) post('live');
                  if (initialLiveStatus === 2) post('replay');
                  setTimeout(applyState, 250);
                });

                window.addEventListener('message', function(event) {
                  let payload = null;
                  if (typeof event.data === 'string' && event.data.startsWith('playerOperation-')) {
                    try {
                      payload = JSON.parse(event.data.slice('playerOperation-'.length));
                    } catch (_) {
                      payload = null;
                    }
                  } else if (event.data && typeof event.data === 'object') {
                    payload = event.data;
                  }

                  if (!payload || !payload.type) {
                    return;
                  }

                  if (payload.type === 'liveStateChange') {
                    const status = payload.value && payload.value.status;
                    if (status === 1) post('live');
                    if (status === 0) post('offline');
                    if (status === 2) post('replay');
                    return;
                  }
                  post(payload.type);
                }, false);

                iframe.src = '\(playerURL)';
              </script>
            </body>
            </html>
            """
        }
    }
}
