import AppKit
import Foundation
import simd

// MARK: - Parameters

/// Physics for one confetti burst, derived from a `ConfettiConfig`.
///
/// The burst engine uses velocity-proportional drag, which CAEmitterLayer can't do, so the
/// config's emitter units are mapped onto it. The scale factors are calibrated so that
/// `ConfettiConfig.default` reproduces the tuned prototype (`Prototypes/MetalConfetti`).
/// `scaleSpeed` and `alphaSpeed` don't apply: particles fade over their last `fadeTime` seconds.
struct BurstParameters {
    var perCannon: Int
    var gravity: Float          // pt/s², positive = down
    var dragMin: Float = 2.2    // 1/s; terminal fall speed = gravity / drag
    var dragMax: Float = 3.2
    var speedMin: Float         // launch speed at a 956 pt tall screen, scaled by screen height
    var speedMax: Float
    var spreadDegrees: Float    // ± around each cannon's aim
    var leftAimDegrees: Float   // from +x axis
    var rightAimDegrees: Float
    var burstWindow: Float      // particles are released over this many seconds
    var lifeMin: Float
    var lifeMax: Float
    var fadeTime: Float = 0.8
    var sizeScale: Float
    var sizeJitter: Float       // size varies by ± this fraction
    var maxSpin: Float          // 2D rotation speed, rad/s, ±
    var colors: [SIMD3<UInt8>]
    var shapes: [ConfettiShape]

    // Calibration: default config (velocity 1500 ± 450, gravity -750, emissionRange 0.4π, spin 12 ± 20,
    // scale 0.8 ± 0.2, lifetime 4.5) → prototype (speed 1827–3393, gravity 900, spread ±25°, spin ±5,
    // size ×1.6 ± 25%, life 3.5–4.5).
    static let speedFactor: Float = 1.74
    static let gravityFactor: Float = 1.2
    static let spreadFactor: Float = 25 / 72
    static let spinDivisor: Float = 6.4
    static let sizeFactor: Float = 2
    static let lifeMinFraction: Float = 3.5 / 4.5

    init(config: ConfettiConfig, angles: ConfettiController.CannonAngles, intensity: Float, burstWindow: Double) {
        let cells = Float(config.colors.count * config.shapes.count)
        perCannon = max(0, Int((config.birthRate * max(intensity, 0) * cells * Float(burstWindow)).rounded()))
        gravity = -Float(config.gravity) * Self.gravityFactor
        let v = Float(config.velocity), vr = abs(Float(config.velocityRange))
        speedMin = max(0, v - vr) * Self.speedFactor
        speedMax = max(speedMin, (v + vr) * Self.speedFactor)
        spreadDegrees = Float(config.emissionRange) * 180 / .pi * Self.spreadFactor
        leftAimDegrees = Float(angles.left) * 180 / .pi
        rightAimDegrees = Float(angles.right) * 180 / .pi
        self.burstWindow = Float(max(burstWindow, 0))
        lifeMax = config.lifetime
        lifeMin = config.lifetime * Self.lifeMinFraction
        sizeScale = Float(config.scale) * Self.sizeFactor
        sizeJitter = config.scale > 0 ? min(0.9, abs(Float(config.scaleRange / config.scale))) : 0
        maxSpin = abs(Float(config.spin) + Float(config.spinRange)) / Self.spinDivisor
        colors = config.colors.map(BurstParameters.srgbBytes)
        shapes = config.shapes
    }

    private static func srgbBytes(_ color: NSColor) -> SIMD3<UInt8> {
        let c = color.usingColorSpace(.sRGB) ?? NSColor.white
        func byte(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        return SIMD3(byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}

// MARK: - Track

/// One particle's whole life, ready to become Core Animation animations.
struct ParticleTrack {
    var birth: Double = 0               // seconds after the burst starts
    var duration: Double = 0            // seconds alive
    var keyTimes: [Double] = []         // 0...1, one per point
    var points: [CGPoint] = []
    var endAlpha: Float = 1             // opacity at death (≈0 if it died of old age on screen)
    var rotation: Float = 0             // at birth, radians
    var spinSpeed: Float = 0            // rad/s
    var flutterPhase: Float = 0         // flutter = cos(flutterPhase + flutterSpeed · t)
    var flutterSpeed: Float = 0         // rad/s, may be negative
    var size = CGSize.zero              // points
    var color = SIMD3<UInt8>(255, 255, 255)
    var shape = ConfettiShape.rectangle
}

// MARK: - Simulation

/// Struct-of-arrays confetti simulation: drag, gravity, sway. Spin and flutter are constant
/// rates, handed to Core Animation as such rather than simulated. No AppKit.
final class BurstSimulation {

    let params: BurstParameters
    let width: Float
    let height: Float
    private(set) var count = 0

    private var px: [Float] = [], py: [Float] = [], vx: [Float] = [], vy: [Float] = []
    private var drag: [Float] = [], age: [Float] = [], life: [Float] = []
    private var swayPhase: [Float] = [], swaySpeed: [Float] = [], swayAmp: [Float] = []
    private var tracks: [ParticleTrack] = []

    init(params: BurstParameters, width: CGFloat, height: CGFloat) {
        self.params = params
        self.width = Float(width)
        self.height = Float(height)
    }

    // MARK: Emission

    /// Releases one cannon's particles from `origin` (points, y-up), aimed at `aimDegrees`.
    func fireCannon<R: RandomNumberGenerator>(from origin: CGPoint, aimDegrees: Float, using rng: inout R) {
        let p = params
        guard p.perCannon > 0, !p.colors.isEmpty, !p.shapes.isEmpty else { return }
        let speedScale = height / 956
        for _ in 0..<p.perCannon {
            let angle = (aimDegrees + .random(in: -p.spreadDegrees...p.spreadDegrees, using: &rng)) * .pi / 180
            let speed = Float.random(in: p.speedMin...p.speedMax, using: &rng) * speedScale
            px.append(Float(origin.x))
            py.append(Float(origin.y) - 10)
            vx.append(cos(angle) * speed)
            vy.append(sin(angle) * speed)
            drag.append(.random(in: p.dragMin...p.dragMax, using: &rng))
            age.append(-Float.random(in: 0...max(p.burstWindow, 0.0001), using: &rng))
            life.append(.random(in: p.lifeMin...max(p.lifeMin, p.lifeMax), using: &rng))
            swayPhase.append(.random(in: 0...(2 * .pi), using: &rng))
            swaySpeed.append(.random(in: 3...7, using: &rng))
            swayAmp.append(.random(in: 8...22, using: &rng))

            var t = ParticleTrack()
            t.rotation = .random(in: 0...(2 * .pi), using: &rng)
            t.spinSpeed = .random(in: -p.maxSpin...p.maxSpin, using: &rng)
            t.flutterPhase = .random(in: 0...(2 * .pi), using: &rng)
            t.flutterSpeed = .random(in: 4...13, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
            t.shape = p.shapes.randomElement(using: &rng)!
            t.color = p.colors.randomElement(using: &rng)!
            let s = p.sizeScale * .random(in: (1 - p.sizeJitter)...(1 + p.sizeJitter), using: &rng)
            let base = BurstSimulation.baseSize(t.shape)
            t.size = CGSize(width: base.width * CGFloat(s), height: base.height * CGFloat(s))
            tracks.append(t)
            count += 1
        }
    }

    /// Design size of each shape in points, before `sizeScale`.
    static func baseSize(_ shape: ConfettiShape) -> CGSize {
        switch shape {
        case .rectangle: return CGSize(width: 14, height: 7)
        case .triangle: return CGSize(width: 10, height: 10)
        case .circle: return CGSize(width: 8, height: 8)
        }
    }

    // MARK: Bake

    /// Runs the whole burst at `simHz` and samples positions at `sampleHz`.
    /// Returns one track per particle that was ever on screen for at least two samples.
    func bake(simHz: Int = 60, sampleHz: Int = 20, maxSeconds: Float = 30) -> [ParticleTrack] {
        let dt = 1 / Float(simHz)
        let every = max(1, simHz / sampleHz)
        let g = params.gravity
        let fade = params.fadeTime
        let minX: Float = -200, maxX = width + 200

        var birthFrame = [Int](repeating: -1, count: count)
        var lastFrame = [Int](repeating: -1, count: count)
        var lastPoint = [CGPoint](repeating: .zero, count: count)
        var sampleFrames = [[Int]](repeating: [], count: count)
        var dead = [Bool](repeating: false, count: count)
        var open = count
        var frame = 0
        let maxFrames = Int(maxSeconds * Float(simHz))

        while open > 0 && frame < maxFrames {
            frame += 1
            for i in 0..<count where !dead[i] {
                age[i] += dt
                guard age[i] >= 0 else { continue }
                if birthFrame[i] < 0 { birthFrame[i] = frame }

                let e = exp(-drag[i] * dt)
                vx[i] *= e
                vy[i] = (vy[i] - g * dt) * e
                swayPhase[i] += swaySpeed[i] * dt
                px[i] += (vx[i] + swayAmp[i] * swaySpeed[i] * cos(swayPhase[i])) * dt
                py[i] += vy[i] * dt

                let remaining = life[i] - age[i]
                if remaining <= 0 || (py[i] < -30 && vy[i] < 0) || px[i] < minX || px[i] > maxX {
                    dead[i] = true
                    open -= 1
                    continue
                }
                let point = CGPoint(x: CGFloat(px[i]), y: CGFloat(py[i]))
                lastFrame[i] = frame
                lastPoint[i] = point
                tracks[i].endAlpha = min(1, remaining / fade)
                if (frame - birthFrame[i]) % every == 0 {
                    sampleFrames[i].append(frame)
                    tracks[i].points.append(point)
                }
            }
        }

        var result: [ParticleTrack] = []
        result.reserveCapacity(count)
        for i in 0..<count where lastFrame[i] > birthFrame[i] && birthFrame[i] >= 0 {
            var t = tracks[i]
            var frames = sampleFrames[i]
            if frames.last != lastFrame[i] {        // always end exactly where it was last seen
                frames.append(lastFrame[i])
                t.points.append(lastPoint[i])
            }
            guard frames.count >= 2 else { continue }
            let span = Double(lastFrame[i] - birthFrame[i])
            t.birth = Double(birthFrame[i]) * Double(dt)
            t.duration = span * Double(dt)
            t.keyTimes = frames.map { Double($0 - birthFrame[i]) / span }
            result.append(t)
        }
        return result
    }
}

// MARK: - Seeded RNG

/// SplitMix64: small, fast, seedable. Used for reproducible bursts in tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
