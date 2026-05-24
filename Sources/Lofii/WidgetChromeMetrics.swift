import CoreGraphics

/// Shared measurements for the widget window shell and any SwiftUI shapes that
/// should line up with that clip — one radius everywhere.
enum WidgetChromeMetrics {
    /// `containerCornerInsets` max-edge inference often lands near ~18pt, which reads
    /// much rounder than a typical tiled window. A single modest radius tracks
    /// standard AppKit window corners more closely.
    static let contentCornerRadius: CGFloat = 12
}
