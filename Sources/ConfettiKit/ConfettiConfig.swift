import AppKit

/// Shape types for confetti particles
public enum ConfettiShape: CaseIterable {
    case rectangle, triangle, circle
}

/// Configuration for confetti emission
public struct ConfettiConfig {
    public let birthRate: Float
    public let lifetime: Float
    public let velocity: CGFloat
    public let velocityRange: CGFloat
    public let emissionRange: CGFloat
    public let gravity: CGFloat
    public let spin: CGFloat
    public let spinRange: CGFloat
    public let scale: CGFloat
    public let scaleRange: CGFloat
    public let scaleSpeed: CGFloat
    public let alphaSpeed: Float
    public let colors: [NSColor]
    public let shapes: [ConfettiShape]

    public static let `default` = ConfettiConfig()

    public init(
        birthRate: Float = 40,
        lifetime: Float = 4.5,
        velocity: CGFloat = 1500,
        velocityRange: CGFloat = 450,
        emissionRange: CGFloat = .pi * 0.4,
        gravity: CGFloat = -750,
        spin: CGFloat = 12.0,
        spinRange: CGFloat = 20.0,
        scale: CGFloat = 0.8,
        scaleRange: CGFloat = 0.2,
        scaleSpeed: CGFloat = -0.1,
        alphaSpeed: Float = -0.15,
        colors: [NSColor] = [.systemRed, .systemGreen, .systemBlue, .systemYellow,
                             .systemOrange, .systemPurple, .systemPink, .cyan],
        shapes: [ConfettiShape] = [.rectangle, .triangle, .circle]
    ) {
        precondition(birthRate > 0, "birthRate must be positive")
        precondition(lifetime > 0, "lifetime must be positive")
        precondition(!colors.isEmpty, "colors must not be empty")
        precondition(!shapes.isEmpty, "shapes must not be empty")

        self.birthRate = birthRate
        self.lifetime = lifetime
        self.velocity = velocity
        self.velocityRange = velocityRange
        self.emissionRange = emissionRange
        self.gravity = gravity
        self.spin = spin
        self.spinRange = spinRange
        self.scale = scale
        self.scaleRange = scaleRange
        self.scaleSpeed = scaleSpeed
        self.alphaSpeed = alphaSpeed
        self.colors = colors
        self.shapes = shapes
    }

    // MARK: - Presets

    /// Gentle, understated confetti — fewer particles, slower, smaller
    public static let subtle = ConfettiConfig(
        birthRate: 15,
        lifetime: 3.5,
        velocity: 800,
        velocityRange: 200,
        gravity: -400,
        spin: 4.0,
        spinRange: 8.0,
        scale: 0.6,
        scaleRange: 0.1,
        scaleSpeed: -0.05,
        alphaSpeed: -0.2
    )

    /// High-energy confetti — more particles, faster, bigger
    public static let intense = ConfettiConfig(
        birthRate: 80,
        lifetime: 5.0,
        velocity: 2000,
        velocityRange: 600,
        gravity: -900,
        spin: 16.0,
        spinRange: 24.0,
        scale: 1.0,
        scaleRange: 0.3,
        scaleSpeed: -0.15,
        alphaSpeed: -0.1
    )

    /// Gentle falling snow effect
    public static let snow = ConfettiConfig(
        birthRate: 25,
        lifetime: 8.0,
        velocity: 200,
        velocityRange: 100,
        emissionRange: .pi * 0.1,
        gravity: -50,
        spin: 2.0,
        spinRange: 4.0,
        scale: 0.4,
        scaleRange: 0.2,
        scaleSpeed: 0,
        alphaSpeed: -0.08,
        colors: [.white, .init(white: 0.9, alpha: 1.0)],
        shapes: [.circle]
    )

    /// Fast explosive burst with heavy gravity
    public static let fireworks = ConfettiConfig(
        birthRate: 100,
        lifetime: 3.0,
        velocity: 2500,
        velocityRange: 800,
        emissionRange: .pi * 0.6,
        gravity: -1200,
        spin: 20.0,
        spinRange: 30.0,
        scale: 0.7,
        scaleRange: 0.3,
        scaleSpeed: -0.2,
        alphaSpeed: -0.25
    )

    /// Returns a preset by name, or nil if not found
    public static func preset(named name: String) -> ConfettiConfig? {
        switch name.lowercased() {
        case "default", "celebration": return .default
        case "subtle": return .subtle
        case "intense": return .intense
        case "snow": return .snow
        case "fireworks": return .fireworks
        default: return nil
        }
    }

    /// All available preset names
    public static let presetNames = ["default", "subtle", "intense", "snow", "fireworks"]
}
