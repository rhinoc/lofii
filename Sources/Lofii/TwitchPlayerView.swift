import SwiftUI
import WebKit

enum TwitchPlaybackEvent: String, Equatable {
    case ready
    case play
    case playing
    case pause
    case ended
    case offline
    case online
    case playbackBlocked
}

struct TwitchPlayerView: NSViewRepresentable {
    let channelName: String
    let isPlaying: Bool
    let volume: Double
    let videoVisible: Bool
    var onPlaybackEvent: (TwitchPlaybackEvent) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPlaybackEvent: onPlaybackEvent)
    }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "lofiiTwitch")

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
            channelName: channelName,
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
            channelName: channelName,
            isPlaying: isPlaying,
            volume: volume,
            videoVisible: videoVisible
        )
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "lofiiTwitch")
        nsView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var onPlaybackEvent: (TwitchPlaybackEvent) -> Void

        private var loadedChannelName: String?
        private var pendingPlaying = false
        private var pendingVolume = 0.58
        private var pendingVideoVisible = false
        private var playerReady = false

        init(onPlaybackEvent: @escaping (TwitchPlaybackEvent) -> Void) {
            self.onPlaybackEvent = onPlaybackEvent
        }

        func load(channelName: String, isPlaying: Bool, volume: Double, videoVisible: Bool) {
            pendingPlaying = isPlaying
            pendingVolume = volume.clamped(to: 0...1)
            pendingVideoVisible = videoVisible

            if loadedChannelName != channelName {
                loadedChannelName = channelName
                playerReady = false
                webView?.loadHTMLString(
                    Self.html(
                        channelName: channelName,
                        isPlaying: isPlaying,
                        volume: pendingVolume,
                        videoVisible: videoVisible
                    ),
                    baseURL: URL(string: "https://localhost/")
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
                      let type = body["type"] as? String,
                      type == "event",
                      let value = body["event"] as? String,
                      let event = TwitchPlaybackEvent(rawValue: value)
                else { return }

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
            let script = """
            window.lofiiSetState?.({
              playing: \(pendingPlaying ? "true" : "false"),
              volume: \(pendingVolume),
              videoVisible: \(pendingVideoVisible ? "true" : "false")
            });
            """
            webView?.evaluateJavaScript(script)
        }

        private static func html(
            channelName: String,
            isPlaying: Bool,
            volume: Double,
            videoVisible: Bool
        ) -> String {
            let escapedChannelName = channelName
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
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
              <script src="https://player.twitch.tv/js/embed/v1.js"></script>
              <script>
                let player = null;
                let ready = false;
                let lastState = {
                  playing: \(isPlaying ? "true" : "false"),
                  volume: \(volume.clamped(to: 0...1)),
                  videoVisible: \(videoVisible ? "true" : "false")
                };

                function post(eventName) {
                  try {
                    window.webkit.messageHandlers.lofiiTwitch.postMessage({
                      type: 'event',
                      event: eventName
                    });
                  } catch (_) {}
                }

                function applyState() {
                  document.body.className = lastState.videoVisible ? 'video' : 'audio';
                  if (!ready || !player) return;
                  player.setMuted(false);
                  player.setVolume(lastState.volume);
                  if (lastState.playing) {
                    player.play();
                  } else {
                    player.pause();
                  }
                }

                window.lofiiSetState = function(state) {
                  lastState = state;
                  applyState();
                };

                window.lofiiStop = function() {
                  if (player) {
                    player.pause();
                  }
                };

                player = new Twitch.Player('player', {
                  width: '100%',
                  height: '100%',
                  channel: '\(escapedChannelName)',
                  parent: ['localhost'],
                  autoplay: false,
                  muted: false
                });
                player.addEventListener(Twitch.Player.READY, function() {
                  ready = true;
                  post('ready');
                  applyState();
                });
                player.addEventListener(Twitch.Player.PLAY, function() { post('play'); });
                player.addEventListener(Twitch.Player.PLAYING, function() { post('playing'); });
                player.addEventListener(Twitch.Player.PAUSE, function() { post('pause'); });
                player.addEventListener(Twitch.Player.ENDED, function() { post('ended'); });
                player.addEventListener(Twitch.Player.OFFLINE, function() { post('offline'); });
                player.addEventListener(Twitch.Player.ONLINE, function() { post('online'); });
                player.addEventListener(Twitch.Player.PLAYBACK_BLOCKED, function() { post('playbackBlocked'); });
              </script>
            </body>
            </html>
            """
        }
    }
}
