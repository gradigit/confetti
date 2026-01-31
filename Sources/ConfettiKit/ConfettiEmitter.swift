import AppKit

/// Creates and manages confetti particle emitters
public enum ConfettiEmitter {

    // MARK: - Cached Textures

    private static let cachedImages: [ConfettiShape: CGImage] = {
        var cache: [ConfettiShape: CGImage] = [:]
        for shape in ConfettiShape.allCases {
            if let image = createImage(for: shape) {
                cache[shape] = image
            } else {
                assertionFailure("Failed to create texture for shape: \(shape)")
                cache[shape] = fallbackImage
            }
        }
        return cache
    }()

    private static let fallbackImage: CGImage = {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 4, height: 4,
            bitsPerComponent: 8, bytesPerRow: 16,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("Cannot create CGContext for fallback confetti texture")
        }
        ctx.setFillColor(CGColor.white)
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        guard let image = ctx.makeImage() else {
            fatalError("Cannot create CGImage for fallback confetti texture")
        }
        return image
    }()

    // MARK: - Public API

    /// Creates a CAEmitterLayer configured for confetti emission
    /// - Parameters:
    ///   - position: The position where particles will spawn
    ///   - angle: The primary emission angle in radians
    ///   - bounds: The bounds of the containing layer
    ///   - config: Configuration for the emitter
    ///   - intensity: Multiplier for birth rate (typically 0.0 - 1.0)
    /// - Returns: A configured CAEmitterLayer
    public static func createEmitter(
        at position: CGPoint,
        angle: CGFloat,
        in bounds: CGRect,
        config: ConfettiConfig = .default,
        intensity: Float = 1.0
    ) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.frame = bounds
        emitter.emitterPosition = position
        emitter.emitterShape = .point
        emitter.emitterSize = .zero
        emitter.emitterMode = .points
        emitter.renderMode = .oldestFirst
        emitter.drawsAsynchronously = true
        emitter.seed = arc4random()

        var cells: [CAEmitterCell] = []
        for color in config.colors {
            for shape in config.shapes {
                cells.append(createCell(
                    color: color,
                    angle: angle,
                    config: config,
                    intensity: intensity,
                    shape: shape
                ))
            }
        }

        emitter.emitterCells = cells
        return emitter
    }

    /// Returns the number of cell types that will be created for a given config
    public static func cellCount(for config: ConfettiConfig) -> Int {
        return config.colors.count * config.shapes.count
    }

    /// Estimates total particles for given config and emission duration
    public static func estimatedParticleCount(
        config: ConfettiConfig,
        emissionDuration: TimeInterval,
        emitterCount: Int = 2,
        intensity: Float = 1.0
    ) -> Int {
        let cellTypes = cellCount(for: config)
        let particlesPerCell = Double(config.birthRate * intensity) * emissionDuration
        return Int(particlesPerCell * Double(cellTypes) * Double(emitterCount))
    }

    // MARK: - Private Implementation

    private static func createCell(
        color: NSColor,
        angle: CGFloat,
        config: ConfettiConfig,
        intensity: Float,
        shape: ConfettiShape
    ) -> CAEmitterCell {
        let cell = CAEmitterCell()

        cell.birthRate = config.birthRate * intensity
        cell.lifetime = config.lifetime
        cell.velocity = config.velocity
        cell.velocityRange = config.velocityRange
        cell.emissionLongitude = angle
        cell.emissionRange = config.emissionRange
        cell.yAcceleration = config.gravity
        cell.spin = config.spin
        cell.spinRange = config.spinRange
        cell.scale = config.scale
        cell.scaleRange = config.scaleRange
        cell.scaleSpeed = config.scaleSpeed
        cell.alphaSpeed = config.alphaSpeed
        cell.color = color.cgColor
        cell.contents = cachedImages[shape]

        return cell
    }

    private static func createImage(for shape: ConfettiShape) -> CGImage? {
        let size: NSSize
        let drawBlock: (NSRect) -> Void

        switch shape {
        case .rectangle:
            size = NSSize(width: 14, height: 7)
            drawBlock = { rect in
                NSColor.white.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            }
        case .triangle:
            size = NSSize(width: 10, height: 10)
            drawBlock = { _ in
                let path = NSBezierPath()
                path.move(to: NSPoint(x: 5, y: 10))
                path.line(to: NSPoint(x: 0, y: 0))
                path.line(to: NSPoint(x: 10, y: 0))
                path.close()
                NSColor.white.setFill()
                path.fill()
            }
        case .circle:
            size = NSSize(width: 8, height: 8)
            drawBlock = { rect in
                NSColor.white.setFill()
                NSBezierPath(ovalIn: rect).fill()
            }
        }

        let image = NSImage(size: size, flipped: false) { rect in
            drawBlock(rect)
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
