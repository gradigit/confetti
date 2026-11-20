import AppKit
import QuartzCore

/// Confetti cannons as `CAEmitterLayer`s with Core Animation's private emitter behaviors:
/// - `drag`: velocity-proportional air resistance, so pieces shoot up, hang, then drift down
/// - `wave`: a sideways sway force
/// - `valueOverLife` on `color.alpha`: fade over the last `fadeTime` seconds
/// plus private cell properties: `plane` particles with random 3D orientation (so `spin` reads as
/// tumbling paper) and `mass`/`massRange` (so drag varies per piece and they spread as they fall).
///
/// Everything runs in the system's render server, like the stock emitter: no per-frame work in
/// the app, and far cheaper for the compositor than animating one layer per particle (1.3.0's
/// approach dropped a 75 Hz display to ~40 fps with three screens attached).
///
/// The private API is looked up at runtime. If it's missing (a future macOS), `isAvailable` is
/// false and the controller falls back to the plain 1.2.0 emitter.
enum EmitterBurst {

    /// Whether the private emitter behaviors exist on this system.
    static let isAvailable: Bool = {
        NSClassFromString("CAEmitterBehavior") != nil
            && CAEmitterLayer.instancesRespond(to: NSSelectorFromString("setEmitterBehaviors:"))
            && behavior("drag") != nil
    }()

    /// One cannon at `origin` (points, y-up) aimed at `aimDegrees` from the +x axis.
    static func makeCannon(at origin: CGPoint, aimDegrees: Float, in bounds: CGRect,
                           params p: BurstParameters, images: ParticleImageCache,
                           screenScale: CGFloat) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.frame = bounds
        emitter.emitterPosition = origin
        emitter.emitterShape = .point
        emitter.renderMode = .oldestFirst
        emitter.preservesDepth = true
        emitter.seed = arc4random()

        let speedScale = bounds.height / 956
        let lifetime = (p.lifeMin + p.lifeMax) / 2
        let cellCount = max(1, p.colors.count * p.shapes.count)
        let jitter = CGFloat(p.sizeJitter)

        var cells: [CAEmitterCell] = []
        for color in p.colors {
            for shape in p.shapes {
                let c = CAEmitterCell()
                c.contents = images.image(color: color, shape: shape)
                c.contentsScale = screenScale
                c.birthRate = p.burstWindow > 0 ? Float(p.perCannon) / p.burstWindow / Float(cellCount) : 0
                c.lifetime = lifetime
                c.lifetimeRange = (p.lifeMax - p.lifeMin) / 2
                c.velocity = CGFloat(p.speedMin + p.speedMax) / 2 * speedScale
                c.velocityRange = CGFloat(p.speedMax - p.speedMin) / 2 * speedScale
                c.emissionLongitude = CGFloat(aimDegrees) * .pi / 180
                c.emissionRange = CGFloat(p.spreadDegrees) * 2 * .pi / 180   // full cone width
                c.yAcceleration = -CGFloat(p.gravity)
                c.spin = 0
                c.spinRange = CGFloat(p.maxSpin)
                c.scale = 1 / (1 + jitter)               // images are drawn at the largest size
                c.scaleRange = jitter / (1 + jitter)
                c.setValue("plane", forKey: "particleType")
                c.setValue(CGFloat.pi, forKey: "orientationRange")
                c.setValue(CGFloat.pi / 2, forKey: "orientationLongitude")
                c.setValue(CGFloat.pi / 2, forKey: "orientationLatitude")
                c.setValue(1.0, forKey: "mass")
                c.setValue(CGFloat(p.massRange), forKey: "massRange")
                cells.append(c)
            }
        }
        emitter.emitterCells = cells

        var behaviors: [NSObject] = []
        if let drag = behavior("drag") {
            drag.setValue(p.drag, forKey: "drag")
            behaviors.append(drag)
        }
        if p.waveForce > 0, let wave = behavior("wave") {
            wave.setValue([p.waveForce, 0, 0], forKey: "force")
            wave.setValue(p.waveFrequency, forKey: "frequency")
            behaviors.append(wave)
        }
        if let fade = behavior("valueOverLife") {
            fade.setValue("color.alpha", forKey: "keyPath")
            fade.setValue([1, 1, 0], forKey: "values")
            fade.setValue([0, max(0, 1 - p.fadeTime / lifetime), 1], forKey: "locations")
            behaviors.append(fade)
        }
        emitter.setValue(behaviors, forKey: "emitterBehaviors")
        return emitter
    }

    /// `+[CAEmitterBehavior behaviorWithType:]`, looked up at runtime (private API).
    static func behavior(_ type: String) -> NSObject? {
        guard let cls = NSClassFromString("CAEmitterBehavior") else { return nil }
        let sel = NSSelectorFromString("behaviorWithType:")
        guard let method = class_getClassMethod(cls, sel) else { return nil }
        typealias BehaviorWithType = @convention(c) (AnyClass, Selector, NSString) -> NSObject?
        let fn = unsafeBitCast(method_getImplementation(method), to: BehaviorWithType.self)
        return fn(cls, sel, type as NSString)
    }
}

// MARK: - Images

/// Pre-coloured shape images for emitter cells, drawn with CGContext at pixel scale so they're
/// sharp on any display and don't depend on the main screen's backing scale.
final class ParticleImageCache {
    private let pixelsPerPoint: CGFloat
    private var cache: [Key: CGImage] = [:]

    private struct Key: Hashable {
        let r, g, b: UInt8
        let shape: ConfettiShape
    }

    /// - Parameters:
    ///   - maxSizeScale: largest size multiplier any particle will use (images are drawn at it)
    ///   - screenScale: display backing scale factor
    init(maxSizeScale: CGFloat, screenScale: CGFloat) {
        pixelsPerPoint = max(maxSizeScale, 0.1) * screenScale
    }

    func image(color: SIMD3<UInt8>, shape: ConfettiShape) -> CGImage {
        let key = Key(r: color.x, g: color.y, b: color.z, shape: shape)
        if let img = cache[key] { return img }
        let img = Self.draw(color: color, shape: shape, k: pixelsPerPoint)
        cache[key] = img
        return img
    }

    private static func draw(color: SIMD3<UInt8>, shape: ConfettiShape, k: CGFloat) -> CGImage {
        let base = BurstParameters.baseSize(shape)
        let w = max(1, Int((base.width * k).rounded(.up)))
        let h = max(1, Int((base.height * k).rounded(.up)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return ConfettiEmitter.fallbackImage
        }
        ctx.setFillColor(red: CGFloat(color.x) / 255, green: CGFloat(color.y) / 255,
                         blue: CGFloat(color.z) / 255, alpha: 1)
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
