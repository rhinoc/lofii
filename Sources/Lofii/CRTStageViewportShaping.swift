import CoreGraphics
import Foundation

/// Matches `StageMetalShaders.metal` UV chain: overscan zoom, then `screenDistort(..., -curvationFactor)`.
enum CRTStageViewportShaping {
    /// Minimum overscan ≥ `presetOverscan` so boundary pixels stay inside \([0,1]\) after curvature (avoids large black wedges).
    static func resolvedOverscan(curvationFactor: Double, presetOverscan: Double) -> Double {
        let k = curvationFactor
        let floorO = max(presetOverscan, 1)
        guard k > 1e-5 else { return floorO }
        if samplesEntirelyInside(overscan: floorO, curvature: k) { return floorO }

        var hi = max(floorO, 1.02)
        var guardCount = 0
        while !samplesEntirelyInside(overscan: hi, curvature: k), hi < 4.75, guardCount < 56 {
            hi += 0.06 + (hi - floorO) * 0.04
            guardCount += 1
        }
        if !samplesEntirelyInside(overscan: hi, curvature: k) {
            return min(4.75, hi)
        }

        var lo = floorO
        for _ in 0..<26 {
            let mid = (lo + hi) / 2
            if samplesEntirelyInside(overscan: mid, curvature: k) {
                hi = mid
            } else {
                lo = mid
            }
        }
        return max(floorO, hi)
    }

    // MARK: - UV transform (keep in sync with `StageMetalShaders.metal`)

    private static func applyOverscan(_ uv: CGPoint, overscan O: CGFloat) -> CGPoint {
        CGPoint(x: (uv.x - 0.5) / O + 0.5, y: (uv.y - 0.5) / O + 0.5)
    }

    private static func screenRadius(_ uv: CGPoint) -> CGFloat {
        let cx = uv.x - 0.5
        let cy = uv.y - 0.5
        return sqrt(cx * cx + cy * cy)
    }

    private static func screenZoom(_ uv: CGPoint, f: CGFloat) -> CGPoint {
        CGPoint(
            x: uv.x - (uv.x - 0.5) * f,
            y: uv.y - (uv.y - 0.5) * f
        )
    }

    /// Metal: `screenDistort(viewportUV, -uniforms.curvationFactor)` with positive uniform `curvature`.
    private static func screenDistortAfterOverscan(_ uv: CGPoint, curvature: CGFloat) -> CGPoint {
        let r = screenRadius(uv)
        return screenZoom(uv, f: r * (-curvature))
    }

    private static func transformedScreenToSample(uv: CGPoint, overscan O: CGFloat, curvature k: CGFloat) -> CGPoint {
        let u1 = applyOverscan(uv, overscan: O)
        return screenDistortAfterOverscan(u1, curvature: k)
    }

    private static func samplesEntirelyInside(overscan O: Double, curvature k: Double) -> Bool {
        let o = CGFloat(O)
        let kk = CGFloat(k)
        let n = 48
        let e: CGFloat = 1e-4
        for i in 0...n {
            for j in 0...n {
                let onEdge = i == 0 || i == n || j == 0 || j == n
                if !onEdge { continue }
                let u = CGPoint(x: CGFloat(i) / CGFloat(n), y: CGFloat(j) / CGFloat(n))
                let v = transformedScreenToSample(uv: u, overscan: o, curvature: kk)
                if v.x < -e || v.x > 1 + e || v.y < -e || v.y > 1 + e {
                    return false
                }
            }
        }
        return true
    }
}
