import SpriteKit

// MARK: - Scene Mode

enum SceneMode {
    case snow
    case confetti
}

/// SpriteKit scene with physics-based falling particles.
/// Snow mode: gentle flakes from top, pile accumulation, mouse sweep.
/// Confetti mode: cannon bursts from bottom corners, identical to CAEmitterLayer version.
class SnowScene: SKScene {

    // MARK: - Textures

    private static let circleTexture: SKTexture = {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        return SKTexture(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    }()

    private static let rectangleTexture: SKTexture = {
        let image = NSImage(size: NSSize(width: 14, height: 7), flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            return true
        }
        return SKTexture(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    }()

    private static let triangleTexture: SKTexture = {
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 5, y: 10))
            path.line(to: NSPoint(x: 0, y: 0))
            path.line(to: NSPoint(x: 10, y: 0))
            path.close()
            NSColor.white.setFill()
            path.fill()
            return true
        }
        return SKTexture(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    }()

    private static let sparkleTexture: SKTexture = {
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
        return SKTexture(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    }()

    private static let confettiTextures: [SKTexture] = [circleTexture, rectangleTexture, triangleTexture]

    private static let confettiColors: [NSColor] = [
        .systemRed, .systemGreen, .systemBlue, .systemYellow,
        .systemOrange, .systemPurple, .systemPink, .cyan
    ]

    // MARK: - State

    let mode: SceneMode

    // Snow-specific state
    private var heightMap: HeightMap!
    private var pileNode: SKShapeNode!
    private var glowNode: SKShapeNode!
    private var puffEmitters: [SKEmitterNode] = []
    private var sparkleNodes: [SKSpriteNode] = []
    private var currentPuffIndex: Int = 0
    private var currentSparkleIndex: Int = 0
    private var landingCount: Int = 0

    // Shared state
    private var activeSnowflakes: [SKSpriteNode] = []
    private var repulsionField: SKFieldNode!
    private var lastUpdateTime: TimeInterval = 0
    private var pathUpdateAccumulator: TimeInterval = 0
    private let pathUpdateInterval: TimeInterval = 0.1 // 10 Hz

    private var spawnAccumulator: TimeInterval = 0
    private var spawnInterval: TimeInterval = 0.2

    // Confetti burst state
    // Original: 24 cells × 40 birthRate × 0.15s = 144 particles per cannon, 288 total
    private var confettiBurstRemaining: Int = 0

    // MARK: - Init

    init(size: CGSize, mode: SceneMode = .snow) {
        self.mode = mode
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        self.mode = .snow
        super.init(coder: aDecoder)
    }

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        anchorPoint = .zero
        backgroundColor = .clear

        setupRepulsionField()

        switch mode {
        case .snow:
            // Gentle gravity for floating snowflakes
            physicsWorld.gravity = CGVector(dx: 0.01, dy: -0.13)
            spawnInterval = 0.2

            heightMap = HeightMap(screenWidth: size.width, screenHeight: size.height)
            setupWindField()
            setupPile()
            setupGlow()
            pileNode.alpha = 0
            glowNode.alpha = 0
            setupPuffEmitters()
            setupSparkles()

        case .confetti:
            // SpriteKit gravity scale: snow uses -0.13 vs CA's -55, ratio ~423x
            // CA confetti gravity = -750 → SK ≈ -1.8, but tuned up for snappier feel
            physicsWorld.gravity = CGVector(dx: 0, dy: -5.0)
            // 144 spawns per side over 0.15 seconds
            confettiBurstRemaining = 288
            spawnInterval = 0.15 / 144.0
            // Stronger repulsion for fast-moving confetti
            repulsionField.strength = -8.0
        }
    }

    // MARK: - Frame Update

    override func update(_ currentTime: TimeInterval) {
        let deltaTime: TimeInterval
        if lastUpdateTime == 0 {
            deltaTime = 1.0 / 30.0
        } else {
            deltaTime = min(currentTime - lastUpdateTime, 0.1)
        }
        lastUpdateTime = currentTime

        updateMouseInteraction(deltaTime: deltaTime)

        // Spawn particles on a timer
        spawnAccumulator += deltaTime
        while spawnAccumulator >= spawnInterval {
            switch mode {
            case .snow:
                spawnSnowflake()
            case .confetti:
                if confettiBurstRemaining > 0 {
                    spawnConfettiPiece(fromLeft: true)
                    spawnConfettiPiece(fromLeft: false)
                    confettiBurstRemaining -= 2
                }
            }
            spawnAccumulator -= spawnInterval
        }

        // Snow-specific: check for landings and update pile
        if mode == .snow {
            for i in stride(from: activeSnowflakes.count - 1, through: 0, by: -1) {
                let flake = activeSnowflakes[i]
                let surfaceY = heightMap.heightAt(x: flake.position.x)

                if flake.position.y <= surfaceY {
                    let landingPoint = CGPoint(x: flake.position.x, y: surfaceY)
                    heightMap.depositSnow(atX: flake.position.x)
                    triggerPuff(at: landingPoint)
                    landingCount += 1
                    if landingCount % 3 == 0 {
                        triggerSparkle(at: landingPoint)
                    }
                    flake.removeFromParent()
                    activeSnowflakes.remove(at: i)
                } else if flake.position.x < -100 || flake.position.x > size.width + 100 {
                    flake.removeFromParent()
                    activeSnowflakes.remove(at: i)
                }
            }

            pathUpdateAccumulator += deltaTime
            if pathUpdateAccumulator >= pathUpdateInterval {
                heightMap.smooth()
                pileNode.path = heightMap.buildPath()
                glowNode.path = heightMap.buildSurfacePath()
                let fadeAlpha = min(heightMap.averageHeight / 8.0, 1.0)
                pileNode.alpha = CGFloat(fadeAlpha)
                glowNode.alpha = CGFloat(fadeAlpha)
                pathUpdateAccumulator = 0
            }
        }
    }

    // MARK: - Snowflake Spawning

    private func spawnSnowflake() {
        let flake = SKSpriteNode(texture: SnowScene.circleTexture)
        flake.setScale(CGFloat.random(in: 0.15...0.45))
        flake.color = .white
        flake.colorBlendFactor = 1.0
        flake.alpha = CGFloat.random(in: 0.6...1.0)
        flake.zPosition = 5

        let x = CGFloat.random(in: 0...size.width)
        flake.position = CGPoint(x: x, y: size.height + 20)

        let body = SKPhysicsBody(circleOfRadius: 2)
        body.mass = 0.05
        body.linearDamping = 0.3
        body.affectedByGravity = true
        body.allowsRotation = false
        body.fieldBitMask = 0x1
        body.collisionBitMask = 0
        body.contactTestBitMask = 0
        flake.physicsBody = body

        body.velocity = CGVector(
            dx: CGFloat.random(in: -5...5),
            dy: CGFloat.random(in: -45 ... -25)
        )

        addChild(flake)
        activeSnowflakes.append(flake)
    }

    // MARK: - Confetti Spawning

    /// Spawns a single confetti piece matching the original CAEmitterLayer behavior.
    /// Cannon angles: left = π*0.47 (~85°), right = π*0.53 (~95°)
    /// Velocity: 1500 ± 450, emission cone: ±π*0.4
    /// Particles self-remove after 4.5s lifetime via SKAction.
    private func spawnConfettiPiece(fromLeft: Bool) {
        let texture = SnowScene.confettiTextures.randomElement()!
        let color = SnowScene.confettiColors.randomElement()!

        let piece = SKSpriteNode(texture: texture)
        // scale: 0.8 ± 0.2 → range 0.6...1.0
        let initialScale = CGFloat.random(in: 0.6...1.0)
        piece.setScale(initialScale)
        piece.color = color
        piece.colorBlendFactor = 1.0
        piece.alpha = 1.0
        piece.zPosition = 5

        // Cannons fire from bottom corners, matching ConfettiController
        piece.position = CGPoint(x: fromLeft ? 0 : size.width, y: 0)

        let body = SKPhysicsBody(circleOfRadius: 3)
        body.mass = 0.01
        body.linearDamping = 0      // pure ballistic, no air drag
        body.angularDamping = 0     // spin doesn't decay
        body.affectedByGravity = true
        body.allowsRotation = true
        body.fieldBitMask = 0x1
        body.collisionBitMask = 0
        body.contactTestBitMask = 0
        piece.physicsBody = body

        // Emission angle: base ± emissionRange (π*0.4)
        let baseAngle: CGFloat = fromLeft ? .pi * 0.47 : .pi * 0.53
        let emissionRange: CGFloat = .pi * 0.4
        let angle = baseAngle + CGFloat.random(in: -emissionRange...emissionRange)
        // CA velocity 1500 / ~423 scale factor ≈ 3.5, tuned up for visual match
        let speed: CGFloat = 350.0 + CGFloat.random(in: -100...100)

        body.velocity = CGVector(
            dx: speed * cos(angle),
            dy: speed * sin(angle)
        )

        // Spin: scaled down from CA values
        body.angularVelocity = CGFloat.random(in: -2...8)

        // Lifetime behavior matching CAEmitterLayer:
        // alphaSpeed: -0.15/s → 1.0 to ~0.325 over 4.5s
        // scaleSpeed: -0.1/s → initial to (initial - 0.45) over 4.5s
        let lifetime: TimeInterval = 4.5
        let finalAlpha: CGFloat = 0.325
        let finalScale = max(initialScale - 0.45, 0.05)

        piece.run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeAlpha(to: finalAlpha, duration: lifetime),
                SKAction.scale(to: finalScale, duration: lifetime),
            ]),
            SKAction.removeFromParent(),
        ]))

        addChild(piece)
        // Not tracked in activeSnowflakes — confetti self-removes via SKAction
        if confettiBurstRemaining % 50 == 0 {
            print("Confetti spawned: pos=\(piece.position) vel=\(body.velocity) remaining=\(confettiBurstRemaining) children=\(children.count)")
        }
    }

    // MARK: - Wind Field

    private func setupWindField() {
        let wind = SKFieldNode.noiseField(withSmoothness: 0.8, animationSpeed: 0.8)
        wind.strength = 0.15
        wind.position = CGPoint(x: size.width / 2, y: size.height / 2)
        wind.region = SKRegion(size: CGSize(width: size.width * 2, height: size.height * 2))
        wind.categoryBitMask = 0x1
        addChild(wind)
    }

    // MARK: - Mouse Interaction

    private func setupRepulsionField() {
        let field = SKFieldNode.radialGravityField()
        field.strength = -3.0
        field.falloff = 2.0
        field.region = SKRegion(radius: 80)
        field.minimumRadius = 10
        field.isEnabled = true
        field.categoryBitMask = 0x1
        field.position = CGPoint(x: -1000, y: -1000)
        addChild(field)
        repulsionField = field
    }

    private func updateMouseInteraction(deltaTime: TimeInterval) {
        guard let window = view?.window else { return }

        let mouseInScreen = NSEvent.mouseLocation
        let mouseInWindow = window.convertPoint(fromScreen: mouseInScreen)
        guard let viewPoint = view?.convert(mouseInWindow, from: nil) else { return }
        let mouseInScene = convertPoint(fromView: viewPoint)

        repulsionField.position = mouseInScene

        // Pile sweep only in snow mode
        if mode == .snow {
            let surfaceY = heightMap.heightAt(x: mouseInScene.x)
            if mouseInScene.y < surfaceY + 30 && surfaceY > 2 {
                heightMap.sweepSnow(atX: mouseInScene.x, radius: 60, amount: CGFloat(deltaTime) * 200)
            }
        }
    }

    // MARK: - Pile (snow only)

    private func setupPile() {
        let node = SKShapeNode()
        node.fillColor = .white
        node.fillTexture = SnowScene.createGradientTexture(height: Int(size.height))
        node.strokeColor = .clear
        node.lineWidth = 0
        node.zPosition = 10
        node.path = heightMap.buildPath()
        addChild(node)
        pileNode = node
    }

    private static func createGradientTexture(height: Int) -> SKTexture {
        let w = 1
        let h = max(height, 1)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return SKTexture(cgImage: fallbackImage())
        }

        let topColor = NSColor(white: 0.95, alpha: 1.0).cgColor
        let bottomColor = NSColor(red: 0.75, green: 0.8, blue: 0.88, alpha: 1.0).cgColor

        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [bottomColor, topColor] as CFArray,
            locations: [0.0, 1.0]
        ) else {
            return SKTexture(cgImage: fallbackImage())
        }

        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: h),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )

        guard let cgImage = ctx.makeImage() else {
            return SKTexture(cgImage: fallbackImage())
        }
        return SKTexture(cgImage: cgImage)
    }

    private static func fallbackImage() -> CGImage {
        let img = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }

    // MARK: - Glow (snow only)

    private func setupGlow() {
        let node = SKShapeNode()
        node.strokeColor = NSColor(white: 1.0, alpha: 0.3)
        node.lineWidth = 6
        node.glowWidth = 4
        node.fillColor = .clear
        node.zPosition = 11
        node.path = heightMap.buildSurfacePath()
        addChild(node)
        glowNode = node
    }

    // MARK: - Landing Puffs (snow only)

    private func setupPuffEmitters() {
        for _ in 0..<3 {
            let emitter = SKEmitterNode()
            emitter.numParticlesToEmit = 4
            emitter.particleBirthRate = 0
            emitter.particleLifetime = 0.3
            emitter.particleLifetimeRange = 0.1
            emitter.particleSpeed = 20
            emitter.particleSpeedRange = 10
            emitter.emissionAngle = .pi / 2
            emitter.emissionAngleRange = .pi * 0.6
            emitter.particleScale = 0.15
            emitter.particleAlpha = 0.7
            emitter.particleAlphaSpeed = -2.0
            emitter.particleColor = .white
            emitter.particleColorBlendFactor = 1.0
            emitter.particleTexture = SnowScene.circleTexture
            emitter.zPosition = 15
            emitter.fieldBitMask = 0x0

            addChild(emitter)
            puffEmitters.append(emitter)
        }
    }

    private func triggerPuff(at point: CGPoint) {
        let emitter = puffEmitters[currentPuffIndex]
        currentPuffIndex = (currentPuffIndex + 1) % puffEmitters.count

        emitter.position = point
        emitter.resetSimulation()
        emitter.particleBirthRate = 200
        emitter.numParticlesToEmit = 4
    }

    // MARK: - Landing Sparkles (snow only)

    private func setupSparkles() {
        for _ in 0..<5 {
            let sparkle = SKSpriteNode(texture: SnowScene.sparkleTexture)
            sparkle.blendMode = .add
            sparkle.zPosition = 12
            sparkle.alpha = 0
            sparkle.setScale(1.5)
            addChild(sparkle)
            sparkleNodes.append(sparkle)
        }
    }

    private func triggerSparkle(at point: CGPoint) {
        let sparkle = sparkleNodes[currentSparkleIndex]
        currentSparkleIndex = (currentSparkleIndex + 1) % sparkleNodes.count

        sparkle.position = point
        sparkle.removeAllActions()
        sparkle.alpha = 1.0
        sparkle.run(SKAction.fadeOut(withDuration: 0.3))
    }
}
