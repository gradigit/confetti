import AppKit
import QuartzCore

/// Confetti cannons as `CAEmitterLayer`s, using private Core Animation emitter features:
/// - behavior `drag`: velocity-proportional air resistance, so pieces shoot up, hang, then drift down
/// - behavior `valueOverLife` on `color.alpha`: fade over the last `fadeTime` seconds
/// - behavior `wave` on each cell: sideways sway, at a different frequency per cell group
/// - cell sprite-sheet animation (`contentsFrameCount`, `contentsFramesPerSecond`,
///   `contentsFrameMode = "random"`): each piece plays a paper-flip strip from a random starting
///   frame, so it turns edge-on and shows a darker back at its own phase
/// - cell `mass`/`massRange`: drag varies per piece, so they spread out as they fall
///
/// Everything runs in the system's render server, like the stock emitter: no per-frame work in
/// the app, and far cheaper for the compositor than animating one layer per particle (1.3.0's
/// approach dropped a 75 Hz display to ~40 fps with three screens attached).
///
/// The private API is looked up at runtime. Without the behaviors (`isAvailable` false) the
/// controller falls back to the plain 1.2.0 emitter; without sprite-sheet frames
/// (`flipAvailable` false) pieces use 3D `plane` particles instead of the flip strip.
enum EmitterBurst {

    /// Whether the private emitter behaviors exist on this system.
    static let isAvailable: Bool = {
        NSClassFromString("CAEmitterBehavior") != nil
            && CAEmitterLayer.instancesRespond(to: NSSelectorFromString("setEmitterBehaviors:"))
            && behavior("drag") != nil
    }()

    /// Whether emitter cells can play sprite-sheet frames (private).
    static let flipAvailable: Bool = {
        ["setContentsFrameCount:", "setContentsFramesPerRow:", "setContentsFrameMode:", "setContentsFramesPerSecond:"]
            .allSatisfy { CAEmitterCell.instancesRespond(to: NSSelectorFromString($0)) }
            && CAEmitterCell.instancesRespond(to: NSSelectorFromString("setEmitterBehaviors:"))
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
        emitter.seed = arc4random()

        let flip = flipAvailable && !p.flipSpeeds.isEmpty
        let groups = flip ? p.flipSpeeds.count : 1
        if !flip { emitter.preservesDepth = true }

        let speedScale = bounds.height / 956
        let lifetime = (p.lifeMin + p.lifeMax) / 2
        let cellCount = max(1, p.colors.count * p.shapes.count * groups)
        let jitter = CGFloat(p.sizeJitter)
        let frames = max(1, p.flipFrames)

        var cells: [CAEmitterCell] = []
        for color in p.colors {
            for shape in p.shapes {
                for g in 0..<groups {
                    let c = CAEmitterCell()
                    c.contentsScale = screenScale
                    c.birthRate = p.burstWindow > 0 ? Float(p.perCannon) / p.burstWindow / Float(cellCount) : 0
                    c.lifetime = lifetime
                    c.lifetimeRange = (p.lifeMax - p.lifeMin) / 2
                    c.velocity = CGFloat(p.speedMin + p.speedMax) / 2 * speedScale
                    c.velocityRange = CGFloat(p.speedMax - p.speedMin) / 2 * speedScale
                    c.emissionLongitude = CGFloat(aimDegrees) * .pi / 180
                    c.emissionRange = CGFloat(p.spreadDegrees * BurstParameters.emissionRangeFactor) * .pi / 180
                    c.yAcceleration = -CGFloat(p.gravity)
                    c.spin = 0
                    c.spinRange = CGFloat(p.maxSpin)
                    c.scale = 1 / (1 + jitter)               // images are drawn at the largest size
                    c.scaleRange = jitter / (1 + jitter)
                    c.setValue(1.0, forKey: "mass")
                    c.setValue(CGFloat(p.massRange), forKey: "massRange")
                    if flip {
                        c.contents = images.flipStrip(color: color, shape: shape, frames: frames, backShade: CGFloat(p.backShade))
                        c.contentsRect = CGRect(x: 0, y: 0, width: 1 / CGFloat(frames), height: 1)
                        c.setValue(frames, forKey: "contentsFrameCount")
                        c.setValue(frames, forKey: "contentsFramesPerRow")
                        c.setValue("random", forKey: "contentsFrameMode")
                        c.setValue(Double(p.flipSpeeds[g]) * Double(frames), forKey: "contentsFramesPerSecond")
                        if p.swayAmplitude > 0, !p.swayFrequencies.isEmpty,
                           let wave = sway(frequency: p.swayFrequencies[g % p.swayFrequencies.count],
                                           amplitude: p.swayAmplitude, drag: p.drag) {
                            c.setValue([wave], forKey: "emitterBehaviors")
                        }
                    } else {
                        c.contents = images.image(color: color, shape: shape)
                        c.setValue("plane", forKey: "particleType")
                        c.setValue(CGFloat.pi, forKey: "orientationRange")
                        c.setValue(CGFloat.pi / 2, forKey: "orientationLongitude")
                        c.setValue(CGFloat.pi / 2, forKey: "orientationLatitude")
                    }
                    cells.append(c)
                }
            }
        }
        emitter.emitterCells = cells

        var behaviors: [NSObject] = []
        if let drag = behavior("drag") {
            drag.setValue(p.drag, forKey: "drag")
            behaviors.append(drag)
        }
        if !flip, p.swayAmplitude > 0, let f = p.swayFrequencies.first,
           let wave = sway(frequency: f, amplitude: p.swayAmplitude, drag: p.drag) {
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

    /// A `wave` behavior pushing sideways at `frequency` Hz, with its force set so a piece under
    /// `drag` swings about ±`amplitude` points (treating the force as sinusoidal; approximate).
    static func sway(frequency: Float, amplitude: Float, drag: Float) -> NSObject? {
        guard let wave = behavior("wave") else { return nil }
        let w = 2 * Float.pi * frequency
        let force = amplitude * w * (w * w + drag * drag).squareRoot()
        wave.setValue([force, 0, 0], forKey: "force")
        wave.setValue(frequency, forKey: "frequency")
        return wave
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
        let frames: Int
    }

    /// - Parameters:
    ///   - maxSizeScale: largest size multiplier any particle will use (images are drawn at it)
    ///   - screenScale: display backing scale factor
    init(maxSizeScale: CGFloat, screenScale: CGFloat) {
        pixelsPerPoint = max(maxSizeScale, 0.1) * screenScale
    }

    /// The shape, face on.
    func image(color: SIMD3<UInt8>, shape: ConfettiShape) -> CGImage {
        let key = Key(r: color.x, g: color.y, b: color.z, shape: shape, frames: 0)
        if let img = cache[key] { return img }
        let img = Self.draw(color: color, shape: shape, frames: 1, backShade: 1, k: pixelsPerPoint)
        cache[key] = img
        return img
    }

    /// `frames` copies of the shape side by side, turning once about its vertical axis:
    /// width × |cos θ|, shaded by `backShade` while the back faces the viewer.
    func flipStrip(color: SIMD3<UInt8>, shape: ConfettiShape, frames: Int, backShade: CGFloat) -> CGImage {
        let key = Key(r: color.x, g: color.y, b: color.z, shape: shape, frames: frames)
        if let img = cache[key] { return img }
        let img = Self.draw(color: color, shape: shape, frames: frames, backShade: backShade, k: pixelsPerPoint)
        cache[key] = img
        return img
    }

    private static func draw(color: SIMD3<UInt8>, shape: ConfettiShape, frames: Int, backShade: CGFloat,
                             k: CGFloat) -> CGImage {
        let base = BurstParameters.baseSize(shape)
        let w = max(1, Int((base.width * k).rounded(.up)))
        let h = max(1, Int((base.height * k).rounded(.up)))
        let n = max(1, frames)
        guard let ctx = CGContext(data: nil, width: w * n, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return ConfettiEmitter.fallbackImage
        }
        for f in 0..<n {
            let turn = cos(2 * Double.pi * Double(f) / Double(n))
            let shade = turn >= 0 ? 1 : backShade
            ctx.setFillColor(red: CGFloat(color.x) / 255 * shade, green: CGFloat(color.y) / 255 * shade,
                             blue: CGFloat(color.z) / 255 * shade, alpha: 1)
            let fw = max(1, CGFloat(w) * CGFloat(abs(turn)))
            let r = CGRect(x: CGFloat(f * w) + (CGFloat(w) - fw) / 2, y: 0, width: fw, height: CGFloat(h))
            switch shape {
            case .rectangle:
                let radius = min(k, r.width / 2, r.height / 2)
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
        }
        return ctx.makeImage() ?? ConfettiEmitter.fallbackImage
    }
}
