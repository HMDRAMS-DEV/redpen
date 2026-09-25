import CoreGraphics
import Foundation

/// A finished pen mark. A rough closed loop becomes a clean red-pen circle; anything else
/// (a line, a tick, a cross) stays as drawn, just smoothed.
enum Ink: Equatable {
    case loop(Loop)
    case line([CGPoint])

    /// An ellipse drawn the way a pen draws one: it starts where you started, goes the way you
    /// went, and overshoots its own start a little, so it reads as a mark rather than a shape.
    struct Loop: Equatable {
        var center: CGPoint
        var radii: CGSize
        var rotation: CGFloat
        var start: CGFloat
        var clockwise: Bool
    }

    var path: CGPath {
        switch self {
        case .loop(let loop): Ink.path(loop)
        case .line(let points): Ink.smoothPath(points)
        }
    }

    var isLoop: Bool {
        if case .loop = self { true } else { false }
    }

    /// Classifies a raw stroke. Returns nil for a stroke too short to be a mark (a click).
    static func recognize(_ points: [CGPoint], tapLength: CGFloat) -> Ink? {
        guard points.count >= 2, length(points) >= tapLength else { return nil }
        return loop(fitting: points).map(Ink.loop) ?? .line(thin(points, spacing: tapLength / 4))
    }

    static func length(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    /// Fits an ellipse to a stroke that goes most of the way around something. Returns nil for
    /// open or flat strokes, and for closed ones too irregular to be meant as a circle.
    static func loop(fitting points: [CGPoint]) -> Loop? {
        let n = CGFloat(points.count)
        let xs = points.map(\.x), ys = points.map(\.y)
        let width = xs.max()! - xs.min()!, height = ys.max()! - ys.min()!
        let diagonal = hypot(width, height)
        guard diagonal > 0, min(width, height) > diagonal * 0.2 else { return nil }

        let mean = CGPoint(x: xs.reduce(0, +) / n, y: ys.reduce(0, +) / n)

        // How far the pen turned around the middle of the stroke. A full circle is 2π.
        var turn: CGFloat = 0
        var previous = atan2(points[0].y - mean.y, points[0].x - mean.x)
        for point in points.dropFirst() {
            let angle = atan2(point.y - mean.y, point.x - mean.x)
            var delta = angle - previous
            if delta > .pi { delta -= 2 * .pi }
            if delta < -.pi { delta += 2 * .pi }
            turn += delta
            previous = angle
        }
        let gap = hypot(points.last!.x - points[0].x, points.last!.y - points[0].y)
        let closed = abs(turn) > 1.9 * .pi || (abs(turn) > 1.55 * .pi && gap < diagonal * 0.45)
        guard closed else { return nil }

        // Principal axes give the tilt of a sloppy oval.
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for p in points {
            let dx = p.x - mean.x, dy = p.y - mean.y
            sxx += dx * dx; syy += dy * dy; sxy += dx * dy
        }
        var rotation = 0.5 * atan2(2 * sxy, sxx - syy)
        // Near-round loops have no meaningful tilt; keep them upright.
        let spread = abs(sxx - syy) / max(sxx + syy, 1)
        if spread < 0.12 && abs(sxy) / max(sxx + syy, 1) < 0.06 { rotation = 0 }

        let axisU = CGPoint(x: cos(rotation), y: sin(rotation))
        let axisV = CGPoint(x: -sin(rotation), y: cos(rotation))
        let us = points.map { ($0.x - mean.x) * axisU.x + ($0.y - mean.y) * axisU.y }
        let vs = points.map { ($0.x - mean.x) * axisV.x + ($0.y - mean.y) * axisV.y }
        let midU = (us.max()! + us.min()!) / 2, midV = (vs.max()! + vs.min()!) / 2
        let a = (us.max()! - us.min()!) / 2, b = (vs.max()! - vs.min()!) / 2
        guard a > 0, b > 0 else { return nil }

        // Reject zigzags: the stroke should stay near the fitted outline.
        let error = zip(us, vs).reduce(0) { sum, uv in
            sum + abs(hypot((uv.0 - midU) / a, (uv.1 - midV) / b) - 1)
        } / n
        guard error < 0.3 else { return nil }

        let center = CGPoint(x: mean.x + midU * axisU.x + midV * axisV.x,
                             y: mean.y + midU * axisU.y + midV * axisV.y)
        let start = atan2((vs[0] - midV) / b, (us[0] - midU) / a)
        // A little breathing room, so the pen clears what it circles.
        return Loop(center: center, radii: CGSize(width: a * 1.04, height: b * 1.04),
                    rotation: rotation, start: start, clockwise: turn > 0)
    }

    static func path(_ loop: Loop) -> CGPath {
        let path = CGMutablePath()
        let steps = 120
        let sweep = 2 * CGFloat.pi + 0.5
        let direction: CGFloat = loop.clockwise ? 1 : -1
        let cosR = cos(loop.rotation), sinR = sin(loop.rotation)
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let angle = loop.start + direction * sweep * t
            // Only the overshoot drifts outward, so the end slides past the start like a
            // real hand instead of stacking on top of it.
            let overshoot = max(0, (t - 0.86) / 0.14)
            let grow = 1 + 0.06 * overshoot * overshoot
            let u = loop.radii.width * grow * cos(angle)
            let v = loop.radii.height * grow * sin(angle)
            let point = CGPoint(x: loop.center.x + u * cosR - v * sinR, y: loop.center.y + u * sinR + v * cosR)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    /// Quadratic curves through the midpoints, which smooths trackpad jitter without lag.
    static func smoothPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points.last!)
        return path
    }

    /// Drops points closer than `spacing` to the previous kept point.
    static func thin(_ points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        var kept = [points[0]]
        for point in points.dropFirst() where hypot(point.x - kept.last!.x, point.y - kept.last!.y) >= spacing {
            kept.append(point)
        }
        if kept.last != points.last { kept.append(points.last!) }
        return kept
    }
}
