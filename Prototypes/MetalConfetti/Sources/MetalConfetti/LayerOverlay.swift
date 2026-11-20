import AppKit
import QuartzCore

/// Same simulation as MetalOverlay, drawn as one small CALayer per particle.
/// The render server composites the particles directly (like CAEmitterLayer does);
/// there is no full-screen intermediate buffer. Flutter = affine x-scale by cos(tilt),
/// back face = a pre-darkened copy of the image.
final class LayerOverlay: NSObject {

    let window: OverlayWindow
    let sim: ConfettiSim
    var onFinished: (() -> Void)?
    var cannons: (left: Bool, right: Bool) = (true, true)

    private let stats: Stats
    private let scale: CGFloat
    private let width: Float
    private var layers: [CALayer] = []
    private var lastFace: [Int8] = []         // 1 front, -1 back, 0 unset
    private var lastAlpha: [Float] = []
    private let out: UnsafeMutablePointer<Instance>
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var finished = false

    init(screen: NSScreen, params: ConfettiSim.Params, stats: Stats) {
        self.stats = stats
        scale = screen.backingScaleFactor
        window = OverlayWindow(screen: screen)
        let size = screen.frame.size
        width = Float(size.width)
        let capacity = params.perCannon * 2
        sim = ConfettiSim(params: params, capacity: capacity, width: Float(size.width), height: Float(size.height))
        out = .allocate(capacity: capacity)
        out.initialize(repeating: Instance(pos: .zero, size: .zero, rot: 0, tilt: 1, alpha: 0, packed: 0), count: capacity)
        super.init()
    }

    deinit { out.deallocate() }

    func fire() {
        window.orderFrontRegardless()
        guard let root = window.contentView?.layer else { return }
        if cannons.left { sim.fireCannon(origin: SIMD2(0, 0), towardRight: true) }
        if cannons.right { sim.fireCannon(origin: SIMD2(width, 0), towardRight: false) }
        stats.spawned += sim.count

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for i in 0..<sim.count {
            let l = CALayer()
            let s = sim.baseSize(i)
            l.bounds = CGRect(x: 0, y: 0, width: CGFloat(s.x), height: CGFloat(s.y))
            l.contentsScale = scale
            l.opacity = 0
            root.addSublayer(l)
            layers.append(l)
        }
        CATransaction.commit()
        lastFace = .init(repeating: 0, count: layers.count)
        lastAlpha = .init(repeating: 0, count: layers.count)

        let link = window.contentView!.displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let t0 = CACurrentMediaTime()
        let dt: Float
        if lastTimestamp == 0 {
            dt = 1.0 / 60.0
        } else {
            let interval = link.timestamp - lastTimestamp
            stats.recordInterval(interval, expected: link.targetTimestamp - link.timestamp)
            dt = Float(min(interval, 1.0 / 30.0))
        }
        lastTimestamp = link.timestamp

        let n = sim.step(dt: dt, into: out, compact: false)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for i in 0..<n {
            let p = out[i]
            let l = layers[i]
            if p.alpha != lastAlpha[i] {
                l.opacity = p.alpha
                lastAlpha[i] = p.alpha
            }
            guard p.alpha > 0 else { continue }
            let face: Int8 = p.tilt >= 0 ? 1 : -1
            if face != lastFace[i] {
                l.contents = LayerImages.image(packed: p.packed, back: face < 0, scale: scale)
                lastFace[i] = face
            }
            // position stays at .zero; translation rides in the transform so each particle
            // changes one layer property per frame instead of two.
            let c = CGFloat(cos(p.rot)), s = CGFloat(sin(p.rot)), t = CGFloat(p.tilt)
            l.setAffineTransform(CGAffineTransform(a: c * t, b: s * t, c: -s, d: c,
                                                   tx: CGFloat(p.pos.x), ty: CGFloat(p.pos.y)))
        }
        CATransaction.commit()

        if stats.frames == 0 { stats.firstCommit = Date(); stats.mark("3_first_frame") }
        stats.frames += 1
        stats.cpuFrame.append(CACurrentMediaTime() - t0)

        if sim.aliveCount == 0 { finish() }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        link?.invalidate()
        link = nil
        onFinished?()
    }

    func close() {
        link?.invalidate()
        window.orderOut(nil)
    }
}

// MARK: - Images

/// White-free, pre-coloured shape images (colour × shape × face), drawn with CGContext at pixel scale.
enum LayerImages {
    private static var cache: [UInt64: CGImage] = [:]

    static func image(packed: UInt32, back: Bool, scale: CGFloat) -> CGImage {
        let key = UInt64(packed) | (back ? 1 << 32 : 0)
        if let img = cache[key] { return img }
        let shape = packed >> 24
        let base: CGSize = shape == 0 ? CGSize(width: 14, height: 7) : shape == 1 ? CGSize(width: 10, height: 10) : CGSize(width: 8, height: 8)
        // Drawn at the largest particle size (sizeScale 1.6 × 1.25) so downscaling stays sharp.
        let k = 1.6 * 1.25 * scale
        let wpx = Int((base.width * k).rounded(.up)), hpx = Int((base.height * k).rounded(.up))
        let ctx = CGContext(data: nil, width: wpx, height: hpx, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let shade: CGFloat = back ? 0.6 : 1.0
        ctx.setFillColor(red: CGFloat(packed & 255) / 255 * shade, green: CGFloat((packed >> 8) & 255) / 255 * shade,
                         blue: CGFloat((packed >> 16) & 255) / 255 * shade, alpha: 1)
        let r = CGRect(x: 0, y: 0, width: wpx, height: hpx)
        switch shape {
        case 0: ctx.addPath(CGPath(roundedRect: r, cornerWidth: k, cornerHeight: k, transform: nil))
        case 1:
            ctx.move(to: CGPoint(x: r.midX, y: r.maxY))
            ctx.addLine(to: CGPoint(x: r.minX, y: r.minY))
            ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            ctx.closePath()
        default: ctx.addEllipse(in: r)
        }
        ctx.fillPath()
        let img = ctx.makeImage()!
        cache[key] = img
        return img
    }
}
