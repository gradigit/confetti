import AppKit
import QuartzCore

/// NSView that renders snow accumulation using pure Core Animation layers.
/// Snow particles via CAEmitterLayer, pile via CAGradientLayer + CAShapeLayer mask.
final class SnowLayerView: NSView {

    // MARK: - Texture

    private static let snowTexture: CGImage = {
        let size = 8
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { fatalError("Failed to create snow texture context") }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))

        return ctx.makeImage()!
    }()

    // MARK: - State

    private var heightMap: HeightMap!
    private var snowEmitter: CAEmitterLayer!
    private var pileGradient: CAGradientLayer!
    private var pileMask: CAShapeLayer!
    private var glowLayer: CAShapeLayer!
    private var surfaceEmitter: CAEmitterLayer!
    private var updateTimer: DispatchSourceTimer?
    private var startTime: CFTimeInterval = 0

    /// Seconds before pile starts growing (time for first snowflakes to reach bottom)
    private let fallDelay: CFTimeInterval = 8.0

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = CGColor.clear

        heightMap = HeightMap(screenWidth: bounds.width, screenHeight: bounds.height)

        setupSnowEmitter()
        setupPile()
        setupGlow()
        setupSurfaceEmitter()

        CATransaction.flush()

        startUpdateTimer()
    }

    // MARK: - Snow Emitter

    private func setupSnowEmitter() {
        let cell = CAEmitterCell()
        cell.name = "snow"
        cell.contents = Self.snowTexture
        cell.birthRate = 5
        cell.lifetime = 12
        cell.lifetimeRange = 3
        cell.velocity = 40
        cell.velocityRange = 15
        cell.emissionLongitude = 0 // perpendicular to line = downward for top-edge line
        cell.emissionRange = .pi * 0.15
        cell.yAcceleration = -20
        cell.xAcceleration = 5
        cell.alphaSpeed = -0.04
        cell.scale = 0.3
        cell.scaleRange = 0.15
        cell.color = NSColor.white.cgColor

        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: bounds.width / 2, y: bounds.height)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: bounds.width, height: 1)
        emitter.emitterMode = .outline
        emitter.emitterCells = [cell]
        emitter.zPosition = 0
        emitter.beginTime = CACurrentMediaTime()

        layer?.addSublayer(emitter)
        snowEmitter = emitter
    }

    // MARK: - Pile

    private func setupPile() {
        let gradient = CAGradientLayer()
        gradient.frame = bounds
        gradient.colors = [
            NSColor(white: 0.95, alpha: 1.0).cgColor,       // top: off-white
            NSColor(red: 0.75, green: 0.8, blue: 0.88, alpha: 1.0).cgColor  // bottom: blue-gray
        ]
        // CAGradientLayer unit coords: (0,0) = top-left, (1,1) = bottom-right
        gradient.startPoint = CGPoint(x: 0.5, y: 0.0)  // off-white at top
        gradient.endPoint = CGPoint(x: 0.5, y: 1.0)    // blue-gray at bottom
        gradient.zPosition = 10
        gradient.opacity = 0

        let mask = CAShapeLayer()
        mask.path = heightMap.buildPath()
        gradient.mask = mask

        layer?.addSublayer(gradient)
        pileGradient = gradient
        pileMask = mask
    }

    // MARK: - Glow

    private func setupGlow() {
        let glow = CAShapeLayer()
        glow.frame = bounds
        glow.path = heightMap.buildSurfacePath()
        glow.fillColor = nil
        glow.strokeColor = NSColor(white: 1.0, alpha: 0.3).cgColor
        glow.lineWidth = 2
        glow.shadowColor = NSColor.white.cgColor
        glow.shadowRadius = 4
        glow.shadowOpacity = 0.3
        glow.shadowOffset = .zero
        glow.zPosition = 11
        glow.opacity = 0

        layer?.addSublayer(glow)
        glowLayer = glow
    }

    // MARK: - Surface Emitter (mist rising from pile)

    private func setupSurfaceEmitter() {
        let cell = CAEmitterCell()
        cell.name = "puff"
        cell.contents = Self.snowTexture
        cell.birthRate = 0 // dormant until pile grows
        cell.lifetime = 0.5
        cell.lifetimeRange = 0.2
        cell.velocity = 15
        cell.velocityRange = 10
        cell.emissionLongitude = 0 // upward from surface line
        cell.emissionRange = .pi * 0.6
        cell.scale = 0.15
        cell.scaleRange = 0.05
        cell.alphaSpeed = -2.0
        cell.color = NSColor.white.cgColor

        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: bounds.width / 2, y: 0)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: bounds.width, height: 1)
        emitter.emitterMode = .outline
        emitter.emitterCells = [cell]
        emitter.zPosition = 15
        emitter.beginTime = CACurrentMediaTime()

        layer?.addSublayer(emitter)
        surfaceEmitter = emitter
    }

    // MARK: - Update Timer

    private func startUpdateTimer() {
        startTime = CACurrentMediaTime()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + fallDelay, repeating: 0.1) // 10Hz after initial delay
        timer.setEventHandler { [weak self] in
            self?.updatePile()
        }
        timer.resume()
        updateTimer = timer
    }

    private func updatePile() {
        heightMap.update(deltaTime: 0.1)
        heightMap.smooth()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Update pile mask and gradient frame to match current pile extent
        let currentMaxHeight = max(heightMap.heights.max() ?? 1, 1)
        let pileFrame = CGRect(x: 0, y: 0, width: bounds.width, height: currentMaxHeight)
        pileGradient.frame = pileFrame
        pileMask.frame = CGRect(origin: .zero, size: pileFrame.size)
        pileMask.path = heightMap.buildPath()

        // Update glow
        glowLayer.path = heightMap.buildSurfacePath()

        // Fade in pile and glow
        let avgHeight = heightMap.averageHeight
        let fadeAlpha = Float(min(avgHeight / 8.0, 1.0))
        pileGradient.opacity = fadeAlpha
        glowLayer.opacity = fadeAlpha

        // Adjust snow particle lifetime to match fall distance to current pile surface
        let fallDistance = max(bounds.height - avgHeight, 100)
        let newLifetime = fallTimeForDistance(fallDistance)
        snowEmitter.setValue(
            NSNumber(value: Float(newLifetime)),
            forKeyPath: "emitterCells.snow.lifetime"
        )

        // Activate and reposition surface mist
        if avgHeight > 5 {
            let puffRate = Float(min(avgHeight / 100.0, 1.0) * 3)
            surfaceEmitter.setValue(
                NSNumber(value: puffRate),
                forKeyPath: "emitterCells.puff.birthRate"
            )
            surfaceEmitter.emitterPosition = CGPoint(x: bounds.width / 2, y: avgHeight)
        }

        CATransaction.commit()
    }

    // MARK: - Helpers

    /// Calculate fall time for a given distance using d = v*t + 0.5*a*t²
    /// where v = 40 (initial speed), a = 20 (gravity)
    private func fallTimeForDistance(_ d: CGFloat) -> CGFloat {
        // 10*t² + 40*t - d = 0 → t = (-40 + sqrt(1600 + 40*d)) / 20
        let discriminant = 1600 + 40 * d
        guard discriminant > 0 else { return 1 }
        return (-40 + sqrt(discriminant)) / 20
    }

    deinit {
        updateTimer?.cancel()
    }
}
