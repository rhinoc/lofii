import SwiftUI
import WebKit

enum YouTubePlaybackState: Equatable {
    case unstarted
    case ended
    case playing
    case paused
    case buffering
    case cued
    case unknown(Int)

    init(rawValue: Int) {
        switch rawValue {
        case -1: self = .unstarted
        case 0: self = .ended
        case 1: self = .playing
        case 2: self = .paused
        case 3: self = .buffering
        case 5: self = .cued
        default: self = .unknown(rawValue)
        }
    }
}

struct YouTubePlayerView: NSViewRepresentable {
    let videoID: String
    let isPlaying: Bool
    let volume: Double
    let videoVisible: Bool
    var onError: (Int) -> Void = { _ in }
    var onPlaybackStateChange: (YouTubePlaybackState) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError, onPlaybackStateChange: onPlaybackStateChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "lofiiYouTube")

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
            videoID: videoID,
            isPlaying: isPlaying,
            volume: volume,
            videoVisible: videoVisible
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onError = onError
        context.coordinator.onPlaybackStateChange = onPlaybackStateChange
        context.coordinator.webView = webView
        context.coordinator.load(
            videoID: videoID,
            isPlaying: isPlaying,
            volume: volume,
            videoVisible: videoVisible
        )
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "lofiiYouTube")
        nsView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var onError: (Int) -> Void
        var onPlaybackStateChange: (YouTubePlaybackState) -> Void

        private var loadedVideoID: String?
        private var pendingPlaying = false
        private var pendingVolume = 0.58
        private var pendingVideoVisible = false
        private var playerReady = false
        private var lastAppliedVideoVisible: Bool?

        init(
            onError: @escaping (Int) -> Void,
            onPlaybackStateChange: @escaping (YouTubePlaybackState) -> Void
        ) {
            self.onError = onError
            self.onPlaybackStateChange = onPlaybackStateChange
        }

        func load(videoID: String, isPlaying: Bool, volume: Double, videoVisible: Bool) {
            pendingPlaying = isPlaying
            pendingVolume = volume.clamped(to: 0...1)
            pendingVideoVisible = videoVisible

            if loadedVideoID != videoID {
                loadedVideoID = videoID
                playerReady = false
                lastAppliedVideoVisible = nil
                webView?.loadHTMLString(
                    Self.html(
                        videoID: videoID,
                        isPlaying: isPlaying,
                        volume: pendingVolume,
                        videoVisible: videoVisible
                    ),
                    baseURL: URL(string: "https://lofii.local/")
                )
                return
            }

            applyState()
        }

        func stop() {
            webView?.evaluateJavaScript("window.lofiiStop?.()")
            webView?.stopLoading()
        }

        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            Task { @MainActor in
                guard let body = message.body as? [String: Any],
                      let type = body["type"] as? String
                else { return }

                switch type {
                case "ready":
                    playerReady = true
                    applyState()
                case "error":
                    if let code = body["code"] as? Int {
                        onError(code)
                    }
                case "state":
                    if let rawState = body["state"] as? Int {
                        onPlaybackStateChange(YouTubePlaybackState(rawValue: rawState))
                    }
                default:
                    break
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyState()
        }

        private func applyState() {
            guard playerReady else { return }
            let becameVisible = pendingVideoVisible && lastAppliedVideoVisible != true
            lastAppliedVideoVisible = pendingVideoVisible
            let reportVisibleState = becameVisible && pendingPlaying
                ? "setTimeout(function() { window.lofiiReportState?.(); }, 150);"
                : ""
            let script = """
            window.lofiiSetState?.({
              playing: \(pendingPlaying ? "true" : "false"),
              volume: \(Int((pendingVolume * 100).rounded())),
              videoVisible: \(pendingVideoVisible ? "true" : "false")
            });
            \(reportVisibleState)
            """
            webView?.evaluateJavaScript(script)
        }

        private static func html(
            videoID: String,
            isPlaying: Bool,
            volume: Double,
            videoVisible: Bool
        ) -> String {
            let escapedVideoID = videoID
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let initialVolume = Int((volume.clamped(to: 0...1) * 100).rounded())
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
              <div id="player"></div>
              <script>
                let player = null;
                let ready = false;
                let lastState = {
                  playing: \(isPlaying ? "true" : "false"),
                  volume: \(initialVolume),
                  videoVisible: \(videoVisible ? "true" : "false")
                };

                function post(message) {
                  try { window.webkit.messageHandlers.lofiiYouTube.postMessage(message); } catch (_) {}
                }

                function applyState() {
                  document.body.className = lastState.videoVisible ? 'video' : 'audio';
                  if (!ready || !player) return;
                  player.setVolume(lastState.volume);
                  if (lastState.playing) {
                    player.playVideo();
                  } else {
                    player.pauseVideo();
                  }
                }

                window.lofiiSetState = function(state) {
                  lastState = state;
                  applyState();
                };

                window.lofiiReportState = function() {
                  if (player && typeof player.getPlayerState === 'function') {
                    post({ type: 'state', state: player.getPlayerState() });
                  }
                };

                window.lofiiStop = function() {
                  if (player) {
                    player.stopVideo();
                    player.destroy();
                  }
                };

                window.onYouTubeIframeAPIReady = function() {
                  player = new YT.Player('player', {
                    videoId: '\(escapedVideoID)',
                    width: '100%',
                    height: '100%',
                    playerVars: {
                      autoplay: 0,
                      controls: 0,
                      disablekb: 1,
                      enablejsapi: 1,
                      fs: 0,
                      iv_load_policy: 3,
                      modestbranding: 1,
                      playsinline: 1,
                      rel: 0,
                      origin: 'https://lofii.local'
                    },
                    events: {
                      onReady: function() {
                        ready = true;
                        post({ type: 'ready' });
                        applyState();
                      },
                      onError: function(event) {
                        post({ type: 'error', code: event.data });
                      },
                      onStateChange: function(event) {
                        post({ type: 'state', state: event.data });
                      }
                    }
                  });
                };
              </script>
              <script src="https://www.youtube.com/iframe_api"></script>
            </body>
            </html>
            """
        }
    }
}
