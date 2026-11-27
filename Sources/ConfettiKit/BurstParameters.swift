import AppKit

/// Confetti physics for one burst, derived from a `ConfettiConfig`.
///
/// The burst uses velocity-proportional air drag (Core Animation's private `drag` emitter
/// behavior, see `EmitterBurst`), so the config's emitter units are mapped onto faster launches
/// and stronger gravity. The scale factors are calibrated so `ConfettiConfig.default` reproduces
/// the tuned look (`Prototypes/MetalConfetti`). `scaleSpeed` and `alphaSpeed` don't apply:
/// particles fade over their last `fadeTime` seconds.
struct BurstParameters {
    var perCannon: Int
    var gravity: Float          // pt/s², positive = down
    var drag: Float = 2.7       // 1/s; terminal fall speed ≈ gravity / drag
    var massRange: Float = 0.45 // per-particle mass ± this; drag acts less on heavier pieces
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
    var maxSpin: Float          // in-plane rotation speed range, rad/s
    /// Paper flip: pieces turn about their own axis at one of these rates (flips per second), each
    /// from a random starting point, showing a darker back face (`backShade`) half the time.
    var flipSpeeds: [Float] = [0.8, 1.3, 1.9]
    var flipFrames = 24
    var backShade: Float = 0.6
    /// Sideways sway, one frequency (Hz) per flip-speed group, so groups drift out of step.
    var swayFrequencies: [Float] = [0.55, 0.8, 1.05]
    var swayAmplitude: Float = 15   // pt, approximate
    var colors: [SIMD3<UInt8>]
    var shapes: [ConfettiShape]

    // Calibration: default config (velocity 1500 ± 450, gravity -750, emissionRange 0.4π, spin 12 ± 20,
    // scale 0.8 ± 0.2, lifetime 4.5) → tuned burst (speed 1827–3393, gravity 900, spread 25°,
    // spin ±5, size ×1.6 ± 25%, life 3.5–4.5). The emitter's cone is `spreadDegrees × emissionRangeFactor`
    // wide: 1.7 matched 1.3.0's on-screen spread best (pixel percentiles over 5 snapshots, 2026-11-27).
    static let speedFactor: Float = 1.74
    static let gravityFactor: Float = 1.2
    static let spreadFactor: Float = 25 / 72
    static let spinDivisor: Float = 6.4
    static let emissionRangeFactor: Float = 1.7
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

    /// Design size of each shape in points, before `sizeScale`.
    static func baseSize(_ shape: ConfettiShape) -> CGSize {
        switch shape {
        case .rectangle: return CGSize(width: 14, height: 7)
        case .triangle: return CGSize(width: 10, height: 10)
        case .circle: return CGSize(width: 8, height: 8)
        }
    }

    private static func srgbBytes(_ color: NSColor) -> SIMD3<UInt8> {
        let c = color.usingColorSpace(.sRGB) ?? NSColor.white
        func byte(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        return SIMD3(byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}
