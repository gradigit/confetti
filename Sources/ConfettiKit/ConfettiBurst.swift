import AppKit
import QuartzCore

/// Turns baked particle tracks into Core Animation layers, committed once.
///
/// After the commit the app does no per-frame work: the render server interpolates every
/// animation, the way it runs CAEmitterLayer. Per particle:
/// - outer layer: position (`.cubic` keyframes), z-rotation, opacity fade
/// - inner layer: the shape image, flutter (x-scale following cos) and a back-face image swap
enum ConfettiBurst {

    /// Adds one layer pair per track to `root`. Returns seconds until the last particle is gone.
    /// Call inside a transaction with actions disabled.
    @discardableResult
    static func addLayers(for tracks: [ParticleTrack], to root: CALayer, scale: CGFloat,
                          images: ParticleImageCache) -> Double {
        let lead = 1.0 / 60.0   // start one frame out so the commit reaches the render server first
        let t0 = root.convertTime(CACurrentMediaTime(), from: nil) + lead
        var end = 0.0

        for tr in tracks {
            let begin = t0 + tr.birth
            let dur = tr.duration
            end = max(end, tr.birth + dur)

            // Outer: position path, z-rotation, opacity
            let outer = CALayer()
            outer.bounds = .zero
            outer.opacity = 0   // hidden outside its animation

            let position = CAKeyframeAnimation(keyPath: "position")
            position.values = tr.points.map { NSValue(point: $0) }
            position.keyTimes = tr.keyTimes.map { NSNumber(value: $0) }
            position.calculationMode = .cubic

            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = tr.rotation
            rotation.toValue = Double(tr.rotation) + Double(tr.spinSpeed) * dur

            let fadeTime = 0.8
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [1, 1, tr.endAlpha]
            opacity.keyTimes = [0, NSNumber(value: max(0, (dur - fadeTime) / dur)), 1]

            for a in [position, rotation, opacity] as [CAAnimation] { a.duration = dur }  // not inherited from group
            let group = CAAnimationGroup()
            group.animations = [position, rotation, opacity]
            group.beginTime = begin
            group.duration = dur
            keepAfterCompletion(group)
            outer.add(group, forKey: "confetti")

            // Inner: image, flutter, back face
            let inner = CALayer()
            inner.bounds = CGRect(origin: .zero, size: tr.size)
            inner.position = .zero
            inner.contentsScale = scale
            let front = images.image(color: tr.color, shape: tr.shape, back: false)
            let back = images.image(color: tr.color, shape: tr.shape, back: true)
            inner.contents = front

            // cos(φ + ωt) with ω < 0 equals cos(-φ + |ω|t)
            let omega = Double(abs(tr.flutterSpeed))
            let phase = Double(tr.flutterSpeed >= 0 ? tr.flutterPhase : -tr.flutterPhase)
            let period = 2 * Double.pi / omega
            var offset = (phase / omega).truncatingRemainder(dividingBy: period)
            if offset < 0 { offset += period }

            let steps = 16
            let flutter = CAKeyframeAnimation(keyPath: "transform.scale.x")
            flutter.values = (0...steps).map { NSNumber(value: cos(2 * Double.pi * Double($0) / Double(steps))) }
            flutter.calculationMode = .cubic

            let face = CAKeyframeAnimation(keyPath: "contents")
            face.values = [front, back, front]
            face.keyTimes = [0, 0.25, 0.75, 1]   // cos < 0 between a quarter and three quarters of a turn
            face.calculationMode = .discrete

            for a in [flutter, face] {
                a.duration = period
                a.timeOffset = offset
                a.repeatDuration = dur + offset
                a.beginTime = begin
                keepAfterCompletion(a)
            }
            inner.add(flutter, forKey: "flutter")
            inner.add(face, forKey: "face")

            outer.addSublayer(inner)
            root.addSublayer(outer)
        }
        return tracks.isEmpty ? 0 : lead + end
    }

    /// With the default `isRemovedOnCompletion = true`, the app wakes to remove each finished
    /// animation (≈1,400 staggered removals per burst, ~40 ms CPU measured). Leaving them attached
    /// keeps the app asleep; `fillMode` holds the final (hidden) state.
    private static func keepAfterCompletion(_ animation: CAAnimation) {
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
    }
}

// MARK: - Images

/// Pre-coloured shape images (colour × shape × face), drawn with CGContext at pixel scale so
/// they're sharp on any display and don't depend on the main screen's backing scale.
final class ParticleImageCache {
    private let pixelsPerPoint: CGFloat
    private var cache: [Key: CGImage] = [:]

    private struct Key: Hashable {
        let r, g, b: UInt8
        let shape: ConfettiShape
        let back: Bool
    }

    /// - Parameters:
    ///   - maxSizeScale: largest size multiplier any particle will use (images are drawn at it)
    ///   - screenScale: display backing scale factor
    init(maxSizeScale: CGFloat, screenScale: CGFloat) {
        pixelsPerPoint = max(maxSizeScale, 0.1) * screenScale
    }

    /// Back faces are drawn darker, like paper seen from behind.
    func image(color: SIMD3<UInt8>, shape: ConfettiShape, back: Bool) -> CGImage {
        let key = Key(r: color.x, g: color.y, b: color.z, shape: shape, back: back)
        if let img = cache[key] { return img }
        let img = Self.draw(color: color, shape: shape, shade: back ? 0.6 : 1.0, k: pixelsPerPoint)
        cache[key] = img
        return img
    }

    private static func draw(color: SIMD3<UInt8>, shape: ConfettiShape, shade: CGFloat, k: CGFloat) -> CGImage {
        let base = BurstSimulation.baseSize(shape)
        let w = max(1, Int((base.width * k).rounded(.up)))
        let h = max(1, Int((base.height * k).rounded(.up)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return ConfettiEmitter.fallbackImage
        }
        ctx.setFillColor(red: CGFloat(color.x) / 255 * shade, green: CGFloat(color.y) / 255 * shade,
                         blue: CGFloat(color.z) / 255 * shade, alpha: 1)
        let r = CGRect(x: 0, y: 0, width: w, height: h)
        switch shape {
        case .rectangle:
            let radius = min(k, CGFloat(min(w, h)) / 2)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        case .triangle:
            ctx.move(to: CGPoint(x: r.midX, y: r.maxY))
            ctx.addLine(to: CGPoint(x: r.minX, y: r.minY))
            ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            ctx.closePath()
        case .circle:
            ctx.addEllipse(in: r)
        }
        ctx.fillPath()
        return ctx.makeImage() ?? ConfettiEmitter.fallbackImage
    }
}
