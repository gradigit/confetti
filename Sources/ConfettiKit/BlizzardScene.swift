import SpriteKit

/// SpriteKit scene with physics-based falling snow, pile accumulation, and mouse interaction.
/// Supports multiple session layers with distinct visual styles for escalating blizzard.
/// Ends naturally when pile reaches max height, or when the user sweeps enough snow away.
/// Can also be stopped programmatically via `stopSnowing()`.
class BlizzardScene: SKScene {

    private enum Constants {
        static let pathUpdateInterval: TimeInterval = 0.1 // 10 Hz
        static let meltDuration: TimeInterval = 2.0
        static let repulsionBitmask: UInt32 = 0x80000000
        static let gravity = CGVector(dx: 0.01, dy: -0.25)
        static let sweepThresholdFactor: CGFloat = 0.08
        static let sweepRadiusFactor: CGFloat = 0.04
        static let sweepRateFactor: CGFloat = 0.15
        static let fadeOutDuration: TimeInterval = 1.0
        static let meltDecayFactor: CGFloat = 0.97
        static let glowPulseBase: CGFloat = 0.15
        static let glowPulseAmplitude: CGFloat = 0.05
    }

    // MARK: - Completion

    /// Called when the blizzard finishes (pile fade-out complete). Always called on main thread.
    var onComplete: (() -> Void)?

    // MARK: - State

    private var heightMap: HeightMap
    private var pileNode: SKShapeNode
    private var glowNode: SKShapeNode
    private var repulsionField: SKFieldNode

    private var sessionLayers: [BlizzardSessionLayer] = []
    private var nextSessionIndex: Int = 0

    private var lastUpdateTime: TimeInterval = 0
    private var pathUpdateAccumulator: TimeInterval = 0

    /// Whether the scene is winding down (fading out pile after all flakes settled)
    private var isWindingDown = false
    /// Whether onComplete has already fired (guards against repeated calls)
    private var hasCompleted = false

    /// Sweep area threshold: 8% of max pile area (scales with screen size)
    private let sweepThreshold: CGFloat
    private let sweepRadius: CGFloat
    private let sweepRate: CGFloat

    private var meltAccumulator: TimeInterval = 0

    // MARK: - Init

    override init(size: CGSize) {
        // Initialize logic helpers
        self.heightMap = HeightMap(screenWidth: size.width, screenHeight: size.height)
        self.sweepThreshold = Constants.sweepThresholdFactor * size.width * heightMap.maxHeight
        self.sweepRadius = Constants.sweepRadiusFactor * size.width
        self.sweepRate = Constants.sweepRateFactor * size.height

        // Initialize visual nodes
        self.pileNode = SKShapeNode()
        self.glowNode = SKShapeNode()
        self.repulsionField = SKFieldNode.radialGravityField()

        super.init(size: size)

        setupScene()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupScene() {
        anchorPoint = .zero
        backgroundColor = .clear
        physicsWorld.gravity = Constants.gravity

        setupRepulsionField()
        setupPile()
        setupGlow()
        pileNode.alpha = 0
        glowNode.alpha = 0
    }

    // MARK: - Public API

    /// Stops the blizzard. All snowflakes and pile fade out together.
    func stopSnowing() {
        guard !isWindingDown else { return }
        for layer in sessionLayers {
            layer.isSpawning = false
        }
        beginFadeOut()
    }

    /// Adds a new session layer with distinct visuals. Returns the session ID.
    @discardableResult
    func addSessionLayer(sessionID: String) -> BlizzardSessionLayer {
        let style: BlizzardSessionStyle
        let index = nextSessionIndex

        if sessionLayers.isEmpty && nextSessionIndex == 0 {
            // First session uses white (backward compat), will transition to ice blue if escalated
            style = BlizzardSessionPalette.style(forSession: 0)
        } else {
            style = BlizzardSessionPalette.style(forSession: index)
        }

        // If this is the second session being added, transition the first session from white to ice blue
        if sessionLayers.count == 1 && sessionLayers[0].sessionIndex == 0 {
            transitionFirstSessionToIceBlue()
        }

        let layer = BlizzardSessionLayer(sessionID: sessionID, sessionIndex: index, style: style)
        nextSessionIndex += 1

        setupLayerNodes(layer)
        sessionLayers.append(layer)

        return layer
    }

    /// Removes a specific session layer — stops spawning, fades its flakes, removes wind.
    /// Does NOT trigger pile melt. Call `stopSnowing()` for full shutdown.
    func removeSessionLayer(sessionID: String) {
        guard let layer = sessionLayers.first(where: { $0.sessionID == sessionID }) else { return }
        guard !layer.isFadingOut else { return }

        layer.isSpawning = false
        layer.isFadingOut = true

        // Fade out this session's airborne flakes
        let fadeOut = SKAction.fadeOut(withDuration: Constants.fadeOutDuration)
        for flake in layer.snowflakes {
            flake.run(fadeOut) {
                flake.removeFromParent()
            }
        }

        // Remove wind field after flakes finish fading (so they don't suddenly go straight)
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.fadeOutDuration) { [weak self, weak layer] in
            guard let layer = layer else { return }
            layer.windField?.removeFromParent()
            layer.windField = nil
            // Remove puffs and sparkles
            for emitter in layer.puffEmitters { emitter.removeFromParent() }
            for sparkle in layer.sparkleNodes { sparkle.removeFromParent() }
            layer.puffEmitters.removeAll()
            layer.sparkleNodes.removeAll()
            layer.snowflakes.removeAll()

            // Remove layer from list
            self?.sessionLayers.removeAll { $0.sessionID == sessionID }

            // If no sessions left, trigger full stop
            if self?.sessionLayers.isEmpty == true && self?.isWindingDown == false {
                self?.stopSnowing()
            }

            // Regenerate pile gradient with remaining sessions
            self?.updatePileGradient()
        }
    }

    /// Number of active (non-fading) session layers
    var activeSessionCount: Int {
        sessionLayers.filter { !$0.isFadingOut }.count
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

        // Melt phase: shrink pile heights + fade alpha, then complete
        if isWindingDown {
            meltAccumulator += deltaTime
            let progress = min(meltAccumulator / Constants.meltDuration, 1.0)
            let melted = heightMap.melt(factor: Constants.meltDecayFactor)
            pileNode.path = heightMap.buildPath()
            glowNode.path = heightMap.buildSurfacePath()
            let alpha = CGFloat(1.0 - progress)
            pileNode.alpha = alpha
            glowNode.alpha = alpha
            if !hasCompleted && (melted || progress >= 1.0) {
                hasCompleted = true
                DispatchQueue.main.async { [weak self] in
                    self?.onComplete?()
                }
            }
            return
        }

        updateMouseInteraction(deltaTime: deltaTime)

        // Per-session spawn and landing
        var anySpawning = false
        for layer in sessionLayers {
            if layer.isFadingOut { continue }

            if layer.isSpawning {
                anySpawning = true
                layer.spawnAccumulator += deltaTime
                while layer.spawnAccumulator >= layer.spawnInterval {
                    spawnSnowflake(for: layer)
                    layer.spawnAccumulator -= layer.spawnInterval
                }
            }

            // Check for landings
            var retained: [SKSpriteNode] = []
            retained.reserveCapacity(layer.snowflakes.count)
            for flake in layer.snowflakes {
                let surfaceY = heightMap.heightAt(x: flake.position.x)

                if flake.position.y <= surfaceY {
                    let landingPoint = CGPoint(x: flake.position.x, y: surfaceY)
                    heightMap.depositSnow(atX: flake.position.x, session: layer.sessionIndex)
                    triggerPuff(at: landingPoint, layer: layer)
                    layer.landingCount += 1
                    if layer.landingCount % 3 == 0 {
                        triggerSparkle(at: landingPoint, layer: layer)
                    }
                    flake.removeFromParent()
                } else if flake.position.x < -100 || flake.position.x > size.width + 100 {
                    flake.removeFromParent()
                } else {
                    retained.append(flake)
                }
            }
            layer.snowflakes = retained
        }

        // Auto-stop: pile is full
        if anySpawning && heightMap.isCapped {
            stopSnowing()
        }

        // Auto-stop: user swept enough snow away
        if anySpawning && heightMap.totalSweptArea >= sweepThreshold {
            stopSnowing()
        }

        // Update pile visuals
        pathUpdateAccumulator += deltaTime
        if pathUpdateAccumulator >= Constants.pathUpdateInterval {
            heightMap.smooth()
            pileNode.path = heightMap.buildPath()
            glowNode.path = heightMap.buildSurfacePath()
            let fadeAlpha = min(heightMap.averageHeight / 8.0, 1.0)
            pileNode.alpha = CGFloat(fadeAlpha)
            glowNode.alpha = CGFloat(fadeAlpha)

            // Glow pulse — subtle sine wave
            let pulse = Constants.glowPulseBase + Constants.glowPulseAmplitude * sin(currentTime * .pi)
            glowNode.strokeColor = blendedGlowColor().withAlphaComponent(pulse)

            pathUpdateAccumulator = 0
        }
    }

    // MARK: - Fade Out

    private func beginFadeOut() {
        isWindingDown = true
        meltAccumulator = 0
        // Fade out any remaining airborne flakes across all sessions
        let fadeOut = SKAction.fadeOut(withDuration: 1.5)
        for layer in sessionLayers {
            for flake in layer.snowflakes {
                flake.run(fadeOut) {
                    flake.removeFromParent()
                }
            }
            layer.snowflakes.removeAll()
        }
    }

    // MARK: - Snowflake Spawning (per-session)

    private func spawnSnowflake(for layer: BlizzardSessionLayer) {
        let style = layer.style
        let flake = SKSpriteNode(texture: style.texture)
        flake.setScale(CGFloat.random(in: style.scaleRange))

        // Use session tint if multi-session, white for single default session
        if sessionLayers.count == 1 && layer.sessionIndex == 0 {
            flake.color = .white
        } else {
            flake.color = style.tint
        }
        flake.colorBlendFactor = 1.0
        flake.alpha = CGFloat.random(in: 0.6...1.0)
        flake.zPosition = 5

        let x = CGFloat.random(in: 0...size.width)
        flake.position = CGPoint(x: x, y: size.height + 20)

        let body = SKPhysicsBody(circleOfRadius: 2)
        body.mass = 0.05
        body.linearDamping = style.linearDamping
        body.affectedByGravity = true
        body.allowsRotation = style.allowsRotation
        // Respond to this session's wind + shared repulsion
        body.fieldBitMask = (1 << UInt32(layer.sessionIndex % 30)) | Constants.repulsionBitmask
        body.collisionBitMask = 0
        body.contactTestBitMask = 0

        if style.allowsRotation {
            body.angularVelocity = CGFloat.random(in: style.angularVelocityRange)
        }

        flake.physicsBody = body

        body.velocity = CGVector(
            dx: CGFloat.random(in: -style.velocityDxSpread...style.velocityDxSpread) + style.gravityDxBias,
            dy: CGFloat.random(in: -45 ... -25)
        )

        addChild(flake)
        layer.snowflakes.append(flake)
    }

    // MARK: - Wind Fields (per-session)

    private func setupLayerNodes(_ layer: BlizzardSessionLayer) {
        let style = layer.style

        // Wind field isolated to this session's particles
        let wind = SKFieldNode.noiseField(withSmoothness: 0.8, animationSpeed: style.windAnimationSpeed)
        wind.strength = 0.15 * style.windStrengthMultiplier
        wind.position = CGPoint(x: size.width / 2, y: size.height / 2)
        wind.region = SKRegion(size: CGSize(width: size.width * 2, height: size.height * 2))
        wind.categoryBitMask = 1 << UInt32(layer.sessionIndex % 30)
        addChild(wind)
        layer.windField = wind

        // Puff emitters (3 per session)
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
            emitter.particleColor = style.tint
            emitter.particleColorBlendFactor = 1.0
            emitter.particleTexture = BlizzardTextures.circle
            emitter.zPosition = 15
            emitter.fieldBitMask = 0x0

            addChild(emitter)
            layer.puffEmitters.append(emitter)
        }

        // Sparkle nodes (5 per session)
        for _ in 0..<5 {
            let sparkle = SKSpriteNode(texture: BlizzardTextures.sparkle)
            sparkle.blendMode = .add
            sparkle.zPosition = 12
            sparkle.alpha = 0
            sparkle.setScale(1.5)
            sparkle.color = style.tint
            sparkle.colorBlendFactor = 0.3
            addChild(sparkle)
            layer.sparkleNodes.append(sparkle)
        }
    }

    // MARK: - Mouse Interaction

    private func setupRepulsionField() {
        repulsionField.strength = -3.0
        repulsionField.falloff = 2.0
        repulsionField.region = SKRegion(radius: 80)
        repulsionField.minimumRadius = 10
        repulsionField.isEnabled = true
        repulsionField.categoryBitMask = Constants.repulsionBitmask
        repulsionField.position = CGPoint(x: -1000, y: -1000)
        addChild(repulsionField)
    }

    private func updateMouseInteraction(deltaTime: TimeInterval) {
        guard let window = view?.window else { return }

        let mouseInScreen = NSEvent.mouseLocation
        let mouseInWindow = window.convertPoint(fromScreen: mouseInScreen)
        guard let viewPoint = view?.convert(mouseInWindow, from: nil) else { return }
        let mouseInScene = convertPoint(fromView: viewPoint)

        repulsionField.position = mouseInScene

        // Pile sweep (only while any session is spawning — no sweeping during wind-down)
        let anySpawning = sessionLayers.contains { $0.isSpawning }
        if anySpawning {
            let surfaceY = heightMap.heightAt(x: mouseInScene.x)
            if mouseInScene.y < surfaceY + 30 && surfaceY > 2 {
                heightMap.sweepSnow(atX: mouseInScene.x, radius: sweepRadius, amount: CGFloat(deltaTime) * sweepRate)
            }
        }
    }

    // MARK: - Pile

    private func setupPile() {
        pileNode.fillColor = .white
        pileNode.fillTexture = BlizzardScene.createGradientTexture(height: Int(size.height), r: 1, g: 1, b: 1)
        pileNode.strokeColor = .clear
        pileNode.lineWidth = 0
        pileNode.zPosition = 10
        pileNode.path = heightMap.buildPath()
        addChild(pileNode)
    }

    private func updatePileGradient() {
        guard !sessionLayers.isEmpty else { return }
        let (r, g, b) = blendedSessionTintRGB()
        pileNode.fillTexture = BlizzardScene.createGradientTexture(height: Int(size.height), r: r, g: g, b: b)
    }

    /// Returns blended (r, g, b) tuple of active session tints.
    private func blendedSessionTintRGB() -> (CGFloat, CGFloat, CGFloat) {
        let active = sessionLayers.filter { !$0.isFadingOut }
        guard !active.isEmpty else { return (1.0, 1.0, 1.0) }
        if active.count == 1 && active[0].sessionIndex == 0 { return (1.0, 1.0, 1.0) }

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        for layer in active {
            // Session tints are already defined in sRGB, getRed is safe
            let srgb = layer.style.tint.usingColorSpace(.sRGB) ?? layer.style.tint
            var sr: CGFloat = 0, sg: CGFloat = 0, sb: CGFloat = 0, sa: CGFloat = 0
            srgb.getRed(&sr, green: &sg, blue: &sb, alpha: &sa)
            r += sr; g += sg; b += sb
        }
        let count = CGFloat(active.count)
        return (r / count, g / count, b / count)
    }

    private func blendedGlowColor() -> NSColor {
        let (r, g, b) = blendedSessionTintRGB()
        return NSColor(red: min(r + 0.2, 1.0), green: min(g + 0.2, 1.0), blue: min(b + 0.2, 1.0), alpha: 0.3)
    }

    static func createGradientTexture(height: Int, tint: NSColor) -> SKTexture {
        // Convert NSColor to sRGB to avoid color space conversion deadlocks during presentScene
        let srgb = tint.usingColorSpace(.sRGB) ?? tint
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        srgb.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        return createGradientTexture(height: height, r: tr, g: tg, b: tb)
    }

    static func createGradientTexture(height: Int, r: CGFloat, g: CGFloat, b: CGFloat) -> SKTexture {
        let w = 1
        let h = max(height, 1)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return SKTexture(cgImage: BlizzardTextures.fallbackCGImage)
        }

        // Top is brighter (near-white), bottom is tinted
        let topColor = NSColor(
            red: min(r * 0.3 + 0.7, 1.0),
            green: min(g * 0.3 + 0.7, 1.0),
            blue: min(b * 0.3 + 0.7, 1.0),
            alpha: 1.0
        ).cgColor
        let bottomColor = NSColor(
            red: r * 0.7 + 0.15,
            green: g * 0.7 + 0.15,
            blue: b * 0.7 + 0.15,
            alpha: 1.0
        ).cgColor

        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [bottomColor, topColor] as CFArray,
            locations: [0.0, 1.0]
        ) else {
            return SKTexture(cgImage: BlizzardTextures.fallbackCGImage)
        }

        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: h),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )

        guard let cgImage = ctx.makeImage() else {
            return SKTexture(cgImage: BlizzardTextures.fallbackCGImage)
        }
        return SKTexture(cgImage: cgImage)
    }

    // MARK: - Glow

    private func setupGlow() {
        glowNode.strokeColor = NSColor(white: 1.0, alpha: 0.15)
        glowNode.lineWidth = 12
        glowNode.glowWidth = 0
        glowNode.fillColor = .clear
        glowNode.zPosition = 11
        glowNode.path = heightMap.buildSurfacePath()
        addChild(glowNode)
    }

    // MARK: - Landing Puffs (per-session)

    private func triggerPuff(at point: CGPoint, layer: BlizzardSessionLayer) {
        guard !layer.puffEmitters.isEmpty else { return }
        let emitter = layer.puffEmitters[layer.currentPuffIndex]
        layer.currentPuffIndex = (layer.currentPuffIndex + 1) % layer.puffEmitters.count

        emitter.position = point
        emitter.resetSimulation()
        emitter.particleBirthRate = 200
        emitter.numParticlesToEmit = 4
    }

    // MARK: - Landing Sparkles (per-session)

    private func triggerSparkle(at point: CGPoint, layer: BlizzardSessionLayer) {
        guard !layer.sparkleNodes.isEmpty else { return }
        let sparkle = layer.sparkleNodes[layer.currentSparkleIndex]
        layer.currentSparkleIndex = (layer.currentSparkleIndex + 1) % layer.sparkleNodes.count

        sparkle.position = point
        sparkle.removeAllActions()
        sparkle.alpha = 1.0
        sparkle.run(SKAction.fadeOut(withDuration: 0.3))
    }

    // MARK: - Session Transition

    /// Retroactively tint the first session's flakes from white to ice blue.
    private func transitionFirstSessionToIceBlue() {
        guard let first = sessionLayers.first, first.sessionIndex == 0 else { return }
        let iceBlue = BlizzardSessionPalette.iceBlue.tint
        let colorize = SKAction.colorize(with: iceBlue, colorBlendFactor: 1.0, duration: 0.5)
        for flake in first.snowflakes {
            flake.run(colorize)
        }
        // Update puffs/sparkles too
        for emitter in first.puffEmitters {
            emitter.particleColor = iceBlue
        }
        for sparkle in first.sparkleNodes {
            sparkle.color = iceBlue
            sparkle.colorBlendFactor = 0.3
        }
        updatePileGradient()
    }
}
