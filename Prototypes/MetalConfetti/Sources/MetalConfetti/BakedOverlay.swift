import AppKit
import QuartzCore

/// Same simulation as LayerOverlay, but run to completion up front and handed to Core Animation
/// as animations, committed once. After that the app does no per-frame work at all: the render
/// server interpolates, the way it does for CAEmitterLayer. The main thread sleeps until exit.
///
/// Per particle: an outer layer (position path, z-rotation, opacity) holding an inner layer
/// (flutter = repeating x-scale following cos, plus a discrete front/back image swap).
final class BakedOverlay {

    let window: OverlayWindow
    let sim: ConfettiSim
    var cannons: (left: Bool, right: Bool) = (true, true)
    /// Seconds from commit until the last particle is gone. Valid after `fire()`.
    private(set) var duration: Double = 0

    private let stats: Stats
    private let scale: CGFloat
    private let width: Float
    private let fadeTime: Double

    /// Position samples per second. Catmull-Rom (`.cubic`) between them.
    static let sampleHz = 20  // 10 Hz measured: saves ~1.5 ms CPU, not worth the fidelity risk
    static let simHz = 60

    init(screen: NSScreen, params: ConfettiSim.Params, stats: Stats) {
        self.stats = stats
        scale = screen.backingScaleFactor
        window = OverlayWindow(screen: screen)
        width = Float(screen.frame.width)
        fadeTime = Double(params.fadeTime)
        sim = ConfettiSim(params: params, capacity: params.perCannon * 2,
                          width: width, height: Float(screen.frame.height))
    }

    // MARK: Bake

    private struct Track {
        var birthFrame = -1
        var endFrame = -1
        var times: [Int] = []          // frame numbers of samples
        var points: [CGPoint] = []
        var lastAlpha: Float = 1
        var pendingLast: (Int, CGPoint)?
    }

    private func bake() -> [Track] {
        let n = sim.count
        var tracks = [Track](repeating: Track(), count: n)
        let out = UnsafeMutablePointer<Instance>.allocate(capacity: n)
        defer { out.deallocate() }
        out.initialize(repeating: Instance(pos: .zero, size: .zero, rot: 0, tilt: 1, alpha: 0, packed: 0), count: n)
        let dt = 1 / Float(Self.simHz)
        let every = Self.simHz / Self.sampleHz
        var frame = 0
        var open = n

        while open > 0 && frame < Self.simHz * 30 {
            frame += 1
            _ = sim.step(dt: dt, into: out, compact: false)
            for i in 0..<n where tracks[i].endFrame < 0 {
                let p = out[i]
                if p.alpha > 0 {
                    if tracks[i].birthFrame < 0 { tracks[i].birthFrame = frame }
                    if (frame - tracks[i].birthFrame) % every == 0 {
                        tracks[i].times.append(frame)
                        tracks[i].points.append(CGPoint(x: CGFloat(p.pos.x), y: CGFloat(p.pos.y)))
                    }
                    tracks[i].lastAlpha = p.alpha
                    // remember the latest position in case it dies before the next sample
                    if tracks[i].times.last != frame {
                        tracks[i].pendingLast = (frame, CGPoint(x: CGFloat(p.pos.x), y: CGFloat(p.pos.y)))
                    } else {
                        tracks[i].pendingLast = nil
                    }
                } else if tracks[i].birthFrame >= 0 || sim.aliveCount == 0 {
                    if let last = tracks[i].pendingLast {
                        tracks[i].times.append(last.0)
                        tracks[i].points.append(last.1)
                    }
                    tracks[i].endFrame = tracks[i].times.last ?? frame
                    open -= 1
                }
            }
        }
        return tracks
    }

    // MARK: Fire

    func fire() {
        window.orderFrontRegardless()
        guard let root = window.contentView?.layer else { return }
        if cannons.left { sim.fireCannon(origin: SIMD2(0, 0), towardRight: true) }
        if cannons.right { sim.fireCannon(origin: SIMD2(width, 0), towardRight: false) }
        stats.spawned += sim.count

        let spins = (0..<sim.count).map { sim.spin($0) }
        let sizes = (0..<sim.count).map { sim.baseSize($0) }
        let packed = (0..<sim.count).map { sim.packedValue($0) }
        let tracks = bake()
        stats.mark("2b_baked")

        let dt = 1 / Double(Self.simHz)
        let t0 = root.convertTime(CACurrentMediaTime(), from: nil) + dt
        var lastEnd = 0.0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for i in 0..<tracks.count {
            let tr = tracks[i]
            guard tr.birthFrame >= 0, tr.points.count >= 2 else { continue }
            let begin = t0 + Double(tr.birthFrame) * dt
            let dur = Double(tr.endFrame - tr.birthFrame) * dt
            guard dur > 0 else { continue }
            lastEnd = max(lastEnd, Double(tr.endFrame) * dt)

            // Outer: position path, z-rotation, opacity
            let outer = CALayer()
            outer.bounds = .zero
            outer.opacity = 0                     // hidden outside its animation window

            let pos = CAKeyframeAnimation(keyPath: "position")
            pos.values = tr.points.map { NSValue(point: $0) }
            pos.keyTimes = tr.times.map { NSNumber(value: Double($0 - tr.birthFrame) * dt / dur) }
            pos.calculationMode = .cubic

            let sp = spins[i]
            let rot = CABasicAnimation(keyPath: "transform.rotation.z")
            rot.fromValue = sp.rot
            rot.toValue = Double(sp.rot) + Double(sp.rotSpeed) * dur

            let fadeStart = max(0, (dur - fadeTime) / dur)
            let alpha = CAKeyframeAnimation(keyPath: "opacity")
            alpha.values = [1, 1, tr.lastAlpha]
            alpha.keyTimes = [0, NSNumber(value: fadeStart), 1]

            let outerGroup = CAAnimationGroup()
            for a in [pos, rot, alpha] as [CAAnimation] { a.duration = dur }  // children don't inherit group duration
            outerGroup.animations = [pos, rot, alpha]
            outerGroup.beginTime = begin
            outerGroup.duration = dur
            // Keep finished animations attached: otherwise the app wakes to remove each one
            // as it ends (1,440 staggered removals), which was ~40 ms of CPU in the idle phase.
            outerGroup.isRemovedOnCompletion = false
            outerGroup.fillMode = .forwards
            outer.add(outerGroup, forKey: "p")

            // Inner: shape image, flutter (x-scale = cos(phase)), back-face image swap
            let inner = CALayer()
            let sz = sizes[i]
            inner.bounds = CGRect(x: 0, y: 0, width: CGFloat(sz.x), height: CGFloat(sz.y))
            inner.position = .zero
            inner.contentsScale = scale
            let front = LayerImages.image(packed: packed[i], back: false, scale: scale)
            let back = LayerImages.image(packed: packed[i], back: true, scale: scale)
            inner.contents = front

            // cos(φ + ωt) with ω possibly negative == cos(-φ + |ω|t)
            let omega = Double(abs(sp.tiltSpeed))
            let phase = Double(sp.tiltSpeed >= 0 ? sp.tiltPhase : -sp.tiltPhase)
            let period = 2 * Double.pi / omega
            let offset = (phase / omega).truncatingRemainder(dividingBy: period)
            let offsetPos = offset < 0 ? offset + period : offset

            let steps = 16
            let flutter = CAKeyframeAnimation(keyPath: "transform.scale.x")
            flutter.values = (0...steps).map { NSNumber(value: cos(2 * Double.pi * Double($0) / Double(steps))) }
            flutter.calculationMode = .cubic

            let face = CAKeyframeAnimation(keyPath: "contents")
            face.values = [front, back, front]
            face.keyTimes = [0, 0.25, 0.75, 1]    // cos < 0 between a quarter and three quarters of a turn
            face.calculationMode = .discrete

            for a in [flutter, face] as [CAKeyframeAnimation] {
                a.duration = period
                a.repeatDuration = dur + offsetPos
                a.timeOffset = offsetPos
                a.beginTime = begin
                a.isRemovedOnCompletion = false
                a.fillMode = .forwards
            }
            inner.add(flutter, forKey: "f")
            inner.add(face, forKey: "b")

            outer.addSublayer(inner)
            root.addSublayer(outer)
        }
        CATransaction.commit()
        CATransaction.flush()
        duration = lastEnd + dt
    }

    func close() { window.orderOut(nil) }
}
