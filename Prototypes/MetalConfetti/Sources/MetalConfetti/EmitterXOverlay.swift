import AppKit
import QuartzCore

/// CAEmitterLayer confetti with Core Animation's private emitter behaviors:
/// `drag` (velocity-proportional air resistance), `wave` (sideways sway) and `valueOverLife`
/// (fade near end of life), plus private `plane` particles with random 3D orientation so `spin`
/// reads as tumbling. Everything runs in the render server like the stock emitter.
///
/// Private API: looked up at runtime; if `CAEmitterBehavior` is missing the burst still runs,
/// just without the behaviors.
final class EmitterXOverlay {

    struct Tuning {
        var drag: Double = 2.7
        var waveForce: Double = 60
        var waveFrequency: Double = 0.6
        var plane = true
        var spin: CGFloat = 0
        var spinRange: CGFloat = 8
        var massRange: CGFloat = 0
        var spreadScale: CGFloat = 1
        var speedScale: CGFloat = 1
        /// Paper flip as a sprite strip: each frame is the piece turned a little further about its
        /// own axis (width = |cos θ|, back face darker). The emitter plays the strip by particle
        /// age from a random starting frame (private `contentsFrameMode = "random"`), so every
        /// piece flips at its own phase. One cell per speed in `flipSpeeds` (flips per second).
        var flip = false
        var flipFrames = 24
        var flipSpeeds: [Double] = [0.7, 1.2, 1.8]
        var backShade: CGFloat = 0.6
    }

    let window: OverlayWindow
    private let stats: Stats
    private let tuning: Tuning
    private var emitters: [CAEmitterLayer] = []
    private let size: CGSize
    private let scale: CGFloat

    init(screen: NSScreen, stats: Stats, tuning: Tuning, opaqueBackground: Bool) {
        self.stats = stats
        self.tuning = tuning
        window = OverlayWindow(screen: screen)
        if opaqueBackground {
            window.isOpaque = true
            window.backgroundColor = .black
        }
        size = screen.frame.size
        scale = screen.backingScaleFactor
    }

    /// Fires both cannons; returns seconds until the last particle is gone.
    func fire(params: ConfettiSim.Params) -> Double {
        window.orderFrontRegardless()
        guard let root = window.contentView?.layer else { return 0 }
        root.display()
        CATransaction.flush()

        let lifetime = (params.lifeMin + params.lifeMax) / 2
        let lifetimeRange = (params.lifeMax - params.lifeMin) / 2
        let speedScale = CGFloat(size.height / 956) * tuning.speedScale
        let images = ParticleImageCache(sizeScale: CGFloat(params.sizeScale * 1.25), screenScale: scale)
        let plane = tuning.plane && !tuning.flip
        let speeds = tuning.flip ? tuning.flipSpeeds : [0]
        let cellCount = params.colors.count * 3 * speeds.count

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (x, aim) in [(CGFloat(0), 90 - params.inwardDeg), (size.width, 90 + params.inwardDeg)] {
            let e = CAEmitterLayer()
            e.frame = root.bounds
            e.emitterPosition = CGPoint(x: x, y: -10)
            e.emitterShape = .point
            e.renderMode = .oldestFirst
            if plane { e.preservesDepth = true }
            e.beginTime = CACurrentMediaTime()

            var cells: [CAEmitterCell] = []
            for color in params.colors {
                for shape in 0..<3 { for speed in speeds {
                    let c = CAEmitterCell()
                    if tuning.flip {
                        let n = tuning.flipFrames
                        c.contents = images.flipStrip(color: color, shape: shape, frames: n, backShade: tuning.backShade)
                        c.contentsRect = CGRect(x: 0, y: 0, width: 1 / CGFloat(n), height: 1)
                        c.setValue(n, forKey: "contentsFrameCount")
                        c.setValue(n, forKey: "contentsFramesPerRow")
                        c.setValue("random", forKey: "contentsFrameMode")
                        c.setValue(speed * Double(n), forKey: "contentsFramesPerSecond")
                    } else {
                        c.contents = images.image(color: color, shape: shape)
                    }
                    c.contentsScale = scale
                    c.birthRate = Float(params.perCannon) / Float(params.burstWindow) / Float(cellCount)
                    c.lifetime = lifetime
                    c.lifetimeRange = lifetimeRange
                    c.velocity = CGFloat(params.speedMin + params.speedMax) / 2 * speedScale
                    c.velocityRange = CGFloat(params.speedMax - params.speedMin) / 2 * speedScale
                    c.emissionLongitude = CGFloat(aim) * .pi / 180
                    c.emissionRange = CGFloat(params.spreadDeg) * .pi / 180 * tuning.spreadScale
                    if tuning.massRange > 0 { c.setValue(1.0, forKey: "mass"); c.setValue(tuning.massRange, forKey: "massRange") }
                    c.yAcceleration = -CGFloat(params.gravity)
                    c.spin = tuning.spin
                    c.spinRange = tuning.spinRange
                    c.scale = 1 / 1.25          // images are drawn at the largest size
                    c.scaleRange = 0.25 / 1.25
                    if plane {
                        c.setValue("plane", forKey: "particleType")
                        c.setValue(CGFloat.pi, forKey: "orientationRange")
                        c.setValue(CGFloat.pi / 2, forKey: "orientationLongitude")
                        c.setValue(CGFloat.pi / 2, forKey: "orientationLatitude")
                    }
                    cells.append(c)
                } }
            }
            e.emitterCells = cells

            var behaviors: [NSObject] = []
            if let drag = Self.behavior("drag") {
                drag.setValue(tuning.drag, forKey: "drag")
                behaviors.append(drag)
            }
            if tuning.waveForce > 0, let wave = Self.behavior("wave") {
                wave.setValue([tuning.waveForce, 0, 0], forKey: "force")
                wave.setValue(tuning.waveFrequency, forKey: "frequency")
                behaviors.append(wave)
            }
            if let fade = Self.behavior("valueOverLife") {
                let fadeStart = max(0, 1 - Double(params.fadeTime) / Double(lifetime))
                fade.setValue("color.alpha", forKey: "keyPath")
                fade.setValue([1, 1, 0], forKey: "values")
                fade.setValue([0, fadeStart, 1], forKey: "locations")
                behaviors.append(fade)
            }
            e.setValue(behaviors, forKey: "emitterBehaviors")

            root.addSublayer(e)
            emitters.append(e)
        }
        CATransaction.commit()
        stats.spawned += params.perCannon * 2

        let stop = DispatchSource.makeTimerSource(queue: .main)
        stop.schedule(deadline: .now() + Double(params.burstWindow), leeway: .milliseconds(1))
        stop.setEventHandler { [weak self] in
            self?.emitters.forEach { $0.birthRate = 0 }
            stop.cancel()
        }
        stop.resume()
        stopTimer = stop
        return Double(params.burstWindow) + Double(params.lifeMax)
    }

    private var stopTimer: DispatchSourceTimer?

    func close() { window.orderOut(nil) }

    /// `[CAEmitterBehavior behaviorWithType:]`, looked up at runtime (private API).
    static func behavior(_ type: String) -> NSObject? {
        guard let cls = NSClassFromString("CAEmitterBehavior") as? NSObject.Type else { return nil }
        let sel = NSSelectorFromString("behaviorWithType:")
        guard let m = class_getClassMethod(cls, sel) else { return nil }
        typealias Fn = @convention(c) (AnyClass, Selector, NSString) -> NSObject?
        return unsafeBitCast(method_getImplementation(m), to: Fn.self)(cls, sel, type as NSString)
    }
}

/// Coloured shape images for emitter cells (shape 0 rectangle, 1 triangle, 2 circle), drawn at
/// pixel scale. Cell `contentsScale` = screen scale, so 1 image point = 1 screen point.
final class ParticleImageCache {
    private let k: CGFloat
    init(sizeScale: CGFloat, screenScale: CGFloat) { k = sizeScale * screenScale }

    private static func baseSize(_ shape: Int) -> CGSize {
        shape == 0 ? CGSize(width: 14, height: 7) : shape == 1 ? CGSize(width: 10, height: 10) : CGSize(width: 8, height: 8)
    }

    private static func addShape(_ ctx: CGContext, _ shape: Int, in r: CGRect, k: CGFloat) {
        switch shape {
        case 0: ctx.addPath(CGPath(roundedRect: r, cornerWidth: min(k, r.height / 2, r.width / 2), cornerHeight: min(k, r.height / 2, r.width / 2), transform: nil))
        case 1:
            ctx.move(to: CGPoint(x: r.midX, y: r.maxY)); ctx.addLine(to: CGPoint(x: r.minX, y: r.minY))
            ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY)); ctx.closePath()
        default: ctx.addEllipse(in: r)
        }
    }

    /// `frames` copies of the shape side by side, turning about the vertical axis through one full
    /// flip: width × |cos θ|, darker while the back faces the viewer.
    func flipStrip(color: SIMD3<UInt8>, shape: Int, frames: Int, backShade: CGFloat) -> CGImage {
        let base = Self.baseSize(shape)
        let w = Int((base.width * k).rounded(.up)), h = Int((base.height * k).rounded(.up))
        let ctx = CGContext(data: nil, width: w * frames, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for f in 0..<frames {
            let c = cos(2 * Double.pi * Double(f) / Double(frames))
            let shade = c >= 0 ? 1 : backShade
            ctx.setFillColor(red: CGFloat(color.x) / 255 * shade, green: CGFloat(color.y) / 255 * shade,
                             blue: CGFloat(color.z) / 255 * shade, alpha: 1)
            let fw = max(1, CGFloat(w) * CGFloat(abs(c)))
            let r = CGRect(x: CGFloat(f * w) + (CGFloat(w) - fw) / 2, y: 0, width: fw, height: CGFloat(h))
            Self.addShape(ctx, shape, in: r, k: k)
            ctx.fillPath()
        }
        return ctx.makeImage()!
    }

    func image(color: SIMD3<UInt8>, shape: Int) -> CGImage {
        let base: CGSize = shape == 0 ? CGSize(width: 14, height: 7) : shape == 1 ? CGSize(width: 10, height: 10) : CGSize(width: 8, height: 8)
        let w = Int((base.width * k).rounded(.up)), h = Int((base.height * k).rounded(.up))
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: CGFloat(color.x) / 255, green: CGFloat(color.y) / 255, blue: CGFloat(color.z) / 255, alpha: 1)
        let r = CGRect(x: 0, y: 0, width: w, height: h)
        switch shape {
        case 0: ctx.addPath(CGPath(roundedRect: r, cornerWidth: min(k, r.height / 2), cornerHeight: min(k, r.height / 2), transform: nil))
        case 1:
            ctx.move(to: CGPoint(x: r.midX, y: r.maxY)); ctx.addLine(to: CGPoint(x: r.minX, y: r.minY))
            ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY)); ctx.closePath()
        default: ctx.addEllipse(in: r)
        }
        ctx.fillPath()
        return ctx.makeImage()!
    }
}
