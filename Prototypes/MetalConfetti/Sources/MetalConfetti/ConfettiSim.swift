import Foundation
import simd

// MARK: - GPU Instance

/// One particle as the GPU sees it. 32 bytes; layout must match `Instance` in Shaders.swift.
struct Instance {
    var pos: SIMD2<Float>      // points, y-up, origin bottom-left
    var size: SIMD2<Float>     // points (unrotated, unforeshortened)
    var rot: Float             // 2D rotation, radians
    var tilt: Float            // cos(3D flip angle): 1 = face-on, 0 = edge-on, <0 = back face
    var alpha: Float
    var packed: UInt32         // r | g<<8 | b<<16 | shape<<24
}

// MARK: - Simulation

/// Struct-of-arrays confetti simulation with velocity-proportional drag, sway and 3D flutter.
/// No AppKit, no allocation after init: `step` writes visible particles straight into a GPU buffer.
final class ConfettiSim {

    struct Params {
        var gravity: Float = 900          // pt/s², downward
        var dragMin: Float = 2.2          // 1/s; terminal fall speed = gravity / drag
        var dragMax: Float = 3.2
        var speedMin: Float = 1800        // launch speed, pt/s, at 956pt screen height
        var speedMax: Float = 3400
        var spreadDeg: Float = 25         // ± around the cannon angle
        var inwardDeg: Float = 10         // cannon aim, degrees off vertical toward screen centre
        var perCannon: Int = 144          // matches CA default: 24 cells × 40/s × 0.15s
        var burstWindow: Float = 0.15     // spawn spread, seconds (CA default emits for 0.15s)
        var lifeMin: Float = 3.5
        var lifeMax: Float = 4.5
        var fadeTime: Float = 0.8
        var sizeScale: Float = 1.6
        var colors: [SIMD3<UInt8>] = []
    }

    let params: Params
    let capacity: Int
    private(set) var count = 0
    private(set) var aliveCount = 0
    private let width: Float
    private let height: Float

    // SoA state
    private var px, py, vx, vy, drag: [Float]
    private var swayPhase, swaySpeed, swayAmp: [Float]
    private var tiltPhase, tiltSpeed, rot, rotSpeed: [Float]
    private var age, life, w, h: [Float]
    private var packed: [UInt32]

    init(params: Params, capacity: Int, width: Float, height: Float) {
        self.params = params
        self.capacity = capacity
        self.width = width
        self.height = height
        let z = [Float](repeating: 0, count: capacity)
        px = z; py = z; vx = z; vy = z; drag = z
        swayPhase = z; swaySpeed = z; swayAmp = z
        tiltPhase = z; tiltSpeed = z; rot = z; rotSpeed = z
        age = z; life = z; w = z; h = z
        packed = [UInt32](repeating: 0, count: capacity)
    }

    // MARK: Emission

    /// Fire a cannon from `origin`. `towardRight` aims it up-and-right (left cannon).
    func fireCannon(origin: SIMD2<Float>, towardRight: Bool) {
        let p = params
        let speedScale = height / 956
        let base: Float = towardRight ? 90 - p.inwardDeg : 90 + p.inwardDeg
        var rng = SystemRandomNumberGenerator()
        let n = min(p.perCannon, capacity - count)
        for _ in 0..<n {
            let i = count
            count += 1
            aliveCount += 1

            let angle = (base + .random(in: -p.spreadDeg...p.spreadDeg, using: &rng)) * .pi / 180
            let speed = Float.random(in: p.speedMin...p.speedMax, using: &rng) * speedScale
            px[i] = origin.x
            py[i] = origin.y - 10
            vx[i] = cos(angle) * speed
            vy[i] = sin(angle) * speed
            drag[i] = .random(in: p.dragMin...p.dragMax, using: &rng)
            swayPhase[i] = .random(in: 0...(2 * .pi), using: &rng)
            swaySpeed[i] = .random(in: 3...7, using: &rng)
            swayAmp[i] = .random(in: 8...22, using: &rng)
            tiltPhase[i] = .random(in: 0...(2 * .pi), using: &rng)
            tiltSpeed[i] = .random(in: 4...13, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
            rot[i] = .random(in: 0...(2 * .pi), using: &rng)
            rotSpeed[i] = .random(in: -5...5, using: &rng)
            age[i] = -Float.random(in: 0...max(p.burstWindow, 0.0001), using: &rng)
            life[i] = .random(in: p.lifeMin...p.lifeMax, using: &rng)

            let shape = UInt32.random(in: 0...2, using: &rng)
            let s = p.sizeScale * .random(in: 0.75...1.25, using: &rng)
            switch shape {
            case 0: w[i] = 14 * s; h[i] = 7 * s     // rectangle
            case 1: w[i] = 10 * s; h[i] = 10 * s    // triangle
            default: w[i] = 8 * s; h[i] = 8 * s     // circle
            }
            let c = p.colors.isEmpty ? SIMD3<UInt8>(255, 255, 255) : p.colors.randomElement(using: &rng)!
            packed[i] = UInt32(c.x) | UInt32(c.y) << 8 | UInt32(c.z) << 16 | shape << 24
        }
    }

    // MARK: Step

    /// Advance by `dt` seconds and write visible particles into `out`. Returns the number written.
    /// `compact: false` keeps particle i in slot i (dead/unborn get alpha 0) and returns `count`;
    /// the CALayer engine needs that so layer i always shows particle i.
    func step(dt: Float, into out: UnsafeMutablePointer<Instance>, compact: Bool = true) -> Int {
        let g = params.gravity
        let fade = params.fadeTime
        let minX: Float = -200, maxX = width + 200
        var written = 0
        var alive = 0

        for i in 0..<count {
            guard life[i] > 0 else { if !compact { out[i].alpha = 0 }; continue }  // dead
            age[i] += dt
            guard age[i] >= 0 else { alive += 1; if !compact { out[i].alpha = 0 }; continue }  // not born yet

            let e = exp(-drag[i] * dt)
            vx[i] *= e
            vy[i] = (vy[i] - g * dt) * e
            swayPhase[i] += swaySpeed[i] * dt
            tiltPhase[i] += tiltSpeed[i] * dt
            rot[i] += rotSpeed[i] * dt
            px[i] += (vx[i] + swayAmp[i] * swaySpeed[i] * cos(swayPhase[i])) * dt
            py[i] += vy[i] * dt

            let remaining = life[i] - age[i]
            if remaining <= 0 || (py[i] < -30 && vy[i] < 0) || px[i] < minX || px[i] > maxX {
                life[i] = 0
                if !compact { out[i].alpha = 0 }
                continue
            }
            alive += 1

            out[compact ? written : i] = Instance(
                pos: SIMD2(px[i], py[i]),
                size: SIMD2(w[i], h[i]),
                rot: rot[i],
                tilt: cos(tiltPhase[i]),
                alpha: min(1, remaining / fade),
                packed: packed[i]
            )
            written += 1
        }
        aliveCount = alive
        return compact ? written : count
    }

    /// Spin and flutter are analytic (constant rates), so the baked engine hands them to
    /// Core Animation as rates instead of samples. Read before the first `step`.
    struct Spin { var rot, rotSpeed, tiltPhase, tiltSpeed: Float }
    func spin(_ i: Int) -> Spin { Spin(rot: rot[i], rotSpeed: rotSpeed[i], tiltPhase: tiltPhase[i], tiltSpeed: tiltSpeed[i]) }

    func baseSize(_ i: Int) -> SIMD2<Float> { SIMD2(w[i], h[i]) }
    func packedValue(_ i: Int) -> UInt32 { packed[i] }
}
