import SpriteKit

// MARK: - Session Style

/// Visual parameters for a single blizzard session layer.
struct BlizzardSessionStyle {
    let tint: NSColor
    let scaleRange: ClosedRange<CGFloat>
    let linearDamping: CGFloat
    let velocityDxSpread: CGFloat
    let windAnimationSpeed: CGFloat
    let windStrengthMultiplier: Float
    let angularVelocityRange: ClosedRange<CGFloat>
    let allowsRotation: Bool
    let texture: SKTexture

    /// Gravity dx bias applied to initial snowflake velocity
    let gravityDxBias: CGFloat
}

// MARK: - Session Palette

/// Four pastel preset slots with cycling for 5+ sessions.
enum BlizzardSessionPalette {

    /// Ice Blue (#BFE0FF) — vertical, normal size, no spin
    static let iceBlue = BlizzardSessionStyle(
        tint: NSColor(red: 0.75, green: 0.88, blue: 1.0, alpha: 1.0),
        scaleRange: 0.15...0.45,
        linearDamping: 0.15,
        velocityDxSpread: 5.0,
        windAnimationSpeed: 0.8,
        windStrengthMultiplier: 1.0,
        angularVelocityRange: 0.0...0.0,
        allowsRotation: false,
        texture: BlizzardTextures.circle,
        gravityDxBias: 0.0
    )

    /// Lavender (#D6C7FF) — slight left drift, smaller, gentle spin
    static let lavender = BlizzardSessionStyle(
        tint: NSColor(red: 0.84, green: 0.78, blue: 1.0, alpha: 1.0),
        scaleRange: 0.10...0.35,
        linearDamping: 0.18,
        velocityDxSpread: 8.0,
        windAnimationSpeed: 1.0,
        windStrengthMultiplier: 1.3,
        angularVelocityRange: -1.0...1.0,
        allowsRotation: true,
        texture: BlizzardTextures.hexagon,
        gravityDxBias: -2.0
    )

    /// Mint (#BFFFDF) — rightward drift, larger, slow tumble
    static let mint = BlizzardSessionStyle(
        tint: NSColor(red: 0.75, green: 1.0, blue: 0.87, alpha: 1.0),
        scaleRange: 0.20...0.55,
        linearDamping: 0.22,
        velocityDxSpread: 6.0,
        windAnimationSpeed: 0.6,
        windStrengthMultiplier: 0.8,
        angularVelocityRange: -0.5...0.5,
        allowsRotation: true,
        texture: BlizzardTextures.star,
        gravityDxBias: 2.5
    )

    /// Rose (#FFCCDA) — wide drift, gusty, fast tumble
    static let rose = BlizzardSessionStyle(
        tint: NSColor(red: 1.0, green: 0.80, blue: 0.85, alpha: 1.0),
        scaleRange: 0.12...0.40,
        linearDamping: 0.10,
        velocityDxSpread: 12.0,
        windAnimationSpeed: 1.4,
        windStrengthMultiplier: 1.5,
        angularVelocityRange: -2.0...2.0,
        allowsRotation: true,
        texture: BlizzardTextures.diamond,
        gravityDxBias: 0.0
    )

    static let all: [BlizzardSessionStyle] = [iceBlue, lavender, mint, rose]

    /// Returns the style for a given session index, cycling for 5+.
    static func style(forSession index: Int) -> BlizzardSessionStyle {
        return all[index % all.count]
    }
}

// MARK: - Textures

/// Pre-generated snowflake shape textures (one-time cost at startup).
enum BlizzardTextures {

    static let circle: SKTexture = {
        let size = 8
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) ?? fallbackCGImage
        return SKTexture(cgImage: cgImage)
    }()

    static let hexagon: SKTexture = {
        let size: CGFloat = 8
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let path = NSBezierPath()
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = rect.width / 2
            for i in 0..<6 {
                let angle = CGFloat(i) * .pi / 3.0 - .pi / 6.0
                let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                if i == 0 { path.move(to: point) } else { path.line(to: point) }
            }
            path.close()
            NSColor.white.setFill()
            path.fill()
            return true
        }
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) ?? fallbackCGImage
        return SKTexture(cgImage: cgImage)
    }()

    static let star: SKTexture = {
        let size: CGFloat = 10
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let path = NSBezierPath()
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let outerRadius = rect.width / 2
            let innerRadius = outerRadius * 0.4
            for i in 0..<10 {
                let angle = CGFloat(i) * .pi / 5.0 - .pi / 2.0
                let radius = (i % 2 == 0) ? outerRadius : innerRadius
                let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                if i == 0 { path.move(to: point) } else { path.line(to: point) }
            }
            path.close()
            NSColor.white.setFill()
            path.fill()
            return true
        }
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) ?? fallbackCGImage
        return SKTexture(cgImage: cgImage)
    }()

    static let diamond: SKTexture = {
        let size: CGFloat = 8
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let path = NSBezierPath()
            let cx = rect.midX, cy = rect.midY
            let hw = rect.width / 2, hh = rect.height / 2
            path.move(to: CGPoint(x: cx, y: cy + hh))
            path.line(to: CGPoint(x: cx + hw, y: cy))
            path.line(to: CGPoint(x: cx, y: cy - hh))
            path.line(to: CGPoint(x: cx - hw, y: cy))
            path.close()
            NSColor.white.setFill()
            path.fill()
            return true
        }
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) ?? fallbackCGImage
        return SKTexture(cgImage: cgImage)
    }()

    static let sparkle: SKTexture = {
        let sz = 6
        let image = NSImage(size: NSSize(width: sz, height: sz), flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = rect.width / 2
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let ctx = NSGraphicsContext.current?.cgContext,
                  let gradient = CGGradient(
                      colorsSpace: colorSpace,
                      colors: [
                          NSColor(white: 1.0, alpha: 1.0).cgColor,
                          NSColor(white: 1.0, alpha: 0.0).cgColor
                      ] as CFArray,
                      locations: [0.0, 1.0]
                  ) else { return true }
            ctx.drawRadialGradient(gradient,
                                   startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: radius,
                                   options: .drawsAfterEndLocation)
            return true
        }
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) ?? fallbackCGImage
        return SKTexture(cgImage: cgImage)
    }()

    static let fallbackCGImage: CGImage = {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("Cannot create CGContext for fallback texture")
        }
        ctx.setFillColor(CGColor.white)
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let image = ctx.makeImage() else {
            fatalError("Cannot create CGImage for fallback texture")
        }
        return image
    }()
}

// MARK: - Session Layer

/// Per-session runtime state within a BlizzardScene.
class BlizzardSessionLayer {
    let sessionID: String
    let sessionIndex: Int
    let style: BlizzardSessionStyle

    var snowflakes: [SKSpriteNode] = []
    var spawnAccumulator: TimeInterval = 0
    let spawnInterval: TimeInterval = 0.12

    var windField: SKFieldNode?
    var puffEmitters: [SKEmitterNode] = []
    var sparkleNodes: [SKSpriteNode] = []
    var currentPuffIndex: Int = 0
    var currentSparkleIndex: Int = 0
    var landingCount: Int = 0

    /// Whether this layer is actively spawning snowflakes
    var isSpawning: Bool = true
    /// Whether this layer's flakes are fading out (removal in progress)
    var isFadingOut: Bool = false

    init(sessionID: String, sessionIndex: Int, style: BlizzardSessionStyle) {
        self.sessionID = sessionID
        self.sessionIndex = sessionIndex
        self.style = style
    }
}

// MARK: - Color Deposit Tracking

/// Tracks which session contributed what height to each column.
struct ColorDeposit {
    /// Height contributed by each session (keyed by session index).
    var sessionHeights: [Int: CGFloat] = [:]

    /// Total deposited height at this column.
    var total: CGFloat {
        sessionHeights.values.reduce(0, +)
    }

    /// Blended color based on session contributions.
    func blendedColor(styles: [Int: BlizzardSessionStyle]) -> NSColor {
        let t = total
        guard t > 0 else { return NSColor(red: 1, green: 1, blue: 1, alpha: 1) }

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        for (sessionIdx, height) in sessionHeights {
            let weight = height / t
            if let style = styles[sessionIdx] {
                let srgb = style.tint.usingColorSpace(.sRGB) ?? style.tint
                var sr: CGFloat = 0, sg: CGFloat = 0, sb: CGFloat = 0, sa: CGFloat = 0
                srgb.getRed(&sr, green: &sg, blue: &sb, alpha: &sa)
                r += sr * weight
                g += sg * weight
                b += sb * weight
            }
        }
        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    /// Decay session heights by a factor (for melt).
    mutating func melt(factor: CGFloat) {
        for key in sessionHeights.keys {
            sessionHeights[key]! *= factor
            if sessionHeights[key]! < 0.1 {
                sessionHeights.removeValue(forKey: key)
            }
        }
    }
}
