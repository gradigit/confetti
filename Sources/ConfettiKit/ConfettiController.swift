import AppKit
import SpriteKit

/// Controls confetti display across screens
public final class ConfettiController {

    /// Angles for the left and right cannons
    public struct CannonAngles {
        public let left: CGFloat
        public let right: CGFloat

        public static let `default` = CannonAngles(
            left: .pi * 0.47,   // ~85°
            right: .pi * 0.53  // ~95°
        )

        public init(left: CGFloat, right: CGFloat) {
            self.left = left
            self.right = right
        }
    }

    private var windows: [ConfettiWindow] = []
    private var blizzardWindows: [BlizzardWindow] = []
    private var emitters: [CAEmitterLayer] = []
    private var hasFired = false
    private var stopTimer: DispatchSourceTimer?
    private var completionTimer: DispatchSourceTimer?

    private var blizzardCompletedCount = 0

    /// Seconds from `fire()` until the last particle is gone. Set by `fire()`; 0 for blizzard.
    public private(set) var duration: TimeInterval = 0

    /// Called on the main thread once the confetti (`.cannons`) or snow (`.curtain`) has finished.
    /// Fires on a precise timer: `asyncAfter` on an idle app runs ~5% late, which kept an empty
    /// overlay on screen for ~220 ms. Not called for blizzard — use `onBlizzardComplete`.
    public var onComplete: (() -> Void)?

    public let config: ConfettiConfig
    public let angles: CannonAngles
    public let emissionDuration: TimeInterval
    public let intensity: Float
    public let windowLevel: WindowLevel

    /// Called when all blizzard scenes have finished their fade-out animation.
    /// Only relevant for `.blizzard` emission style.
    public var onBlizzardComplete: (() -> Void)?

    /// Creates a confetti controller
    /// - Parameters:
    ///   - config: Configuration for the confetti particles
    ///   - angles: Angles for the left and right cannons
    ///   - emissionDuration: How long to emit particles
    ///   - intensity: Multiplier for particle birth rate
    ///   - windowLevel: Window level for overlay windows
    public init(
        config: ConfettiConfig = .default,
        angles: CannonAngles = .default,
        emissionDuration: TimeInterval = 0.15,
        intensity: Float = 1.0,
        windowLevel: WindowLevel = .statusBar
    ) {
        self.config = config
        self.angles = angles
        self.emissionDuration = emissionDuration
        self.intensity = intensity
        self.windowLevel = windowLevel
    }

    /// Fires confetti on specified screens
    /// - Parameter screens: Screens to display confetti on. Defaults to all screens.
    public func fire(on screens: [NSScreen]? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !hasFired else { return }
        hasFired = true

        let targetScreens = screens ?? NSScreen.screens
        guard !targetScreens.isEmpty else { return }

        // Blizzard uses SpriteKit — separate code path
        if config.emissionStyle == .blizzard {
            for screen in targetScreens {
                let window = BlizzardWindow(screen: screen, windowLevel: windowLevel)
                window.orderFrontRegardless()
                blizzardWindows.append(window)
                window.blizzardScene.onComplete = { [weak self] in
                    self?.handleBlizzardSceneComplete()
                }
            }
            return
        }

        // Create windows
        for screen in targetScreens {
            let window = ConfettiWindow(screen: screen, windowLevel: windowLevel)
            window.orderFrontRegardless()
            windows.append(window)
        }

        // Force windows to render before adding emitters
        for window in windows {
            window.contentView?.layer?.display()
        }
        CATransaction.flush()

        switch config.emissionStyle {
        case .cannons:
            duration = addBursts()
        case .curtain:
            addCurtainEmitters()
            duration = emissionDuration + TimeInterval(config.lifetime)
        case .blizzard:
            return  // handled above
        }
        scheduleCompletion(after: duration)
    }

    /// Stops the blizzard gracefully. New snowflakes stop spawning, existing flakes
    /// settle, the pile fades out, then `onBlizzardComplete` is called.
    public func stopSnowing() {
        dispatchPrecondition(condition: .onQueue(.main))
        for window in blizzardWindows {
            window.blizzardScene.stopSnowing()
        }
    }

    /// Estimated particle count per screen based on current configuration
    /// - Parameter emitterCount: Number of emitters per screen (default: 2 for left/right cannons)
    public func estimatedParticleCount(emitterCount: Int = 2) -> Int {
        ConfettiEmitter.estimatedParticleCount(
            config: config,
            emissionDuration: emissionDuration,
            emitterCount: emitterCount,
            intensity: intensity
        )
    }

    /// Adds a new session layer to all blizzard scenes (multi-session escalation).
    public func escalateBlizzard(sessionID: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        for window in blizzardWindows {
            window.blizzardScene.addSessionLayer(sessionID: sessionID)
        }
    }

    /// Removes a session layer from all blizzard scenes (de-escalation).
    /// If no sessions remain, triggers stopSnowing → melt → onBlizzardComplete.
    public func deescalateBlizzard(sessionID: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        for window in blizzardWindows {
            window.blizzardScene.removeSessionLayer(sessionID: sessionID)
        }
    }

    private func handleBlizzardSceneComplete() {
        dispatchPrecondition(condition: .onQueue(.main))
        blizzardCompletedCount += 1
        if blizzardCompletedCount >= blizzardWindows.count {
            onBlizzardComplete?()
        }
    }

    // MARK: - Cannons (burst engine)

    /// Simulates each screen's burst up front and commits it as Core Animation animations.
    /// Returns seconds until the last particle on any screen is gone.
    private func addBursts() -> TimeInterval {
        let params = BurstParameters(config: config, angles: angles, intensity: intensity,
                                     burstWindow: emissionDuration)
        var rng = SystemRandomNumberGenerator()
        var longest: TimeInterval = 0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for window in windows {
            guard let root = window.contentView?.layer else { continue }
            let bounds = root.bounds
            let scale = window.screen?.backingScaleFactor ?? window.backingScaleFactor

            let sim = BurstSimulation(params: params, width: bounds.width, height: bounds.height)
            sim.fireCannon(from: CGPoint(x: 0, y: 0), aimDegrees: params.leftAimDegrees, using: &rng)
            sim.fireCannon(from: CGPoint(x: bounds.width, y: 0), aimDegrees: params.rightAimDegrees, using: &rng)
            let tracks = sim.bake()

            let images = ParticleImageCache(
                maxSizeScale: CGFloat(params.sizeScale * (1 + params.sizeJitter)), screenScale: scale)
            longest = max(longest, ConfettiBurst.addLayers(for: tracks, to: root, scale: scale, images: images))
        }
        CATransaction.commit()
        return longest
    }

    // MARK: - Curtain (CAEmitterLayer)

    private func addCurtainEmitters() {
        for window in windows {
            guard let layer = window.contentView?.layer else { continue }
            let bounds = layer.bounds

            // Line emitter across top edge, particles fall down
            let emitter = ConfettiEmitter.createEmitter(
                at: CGPoint(x: bounds.width / 2, y: bounds.height),
                angle: 0,  // along line's inward normal = downward
                in: bounds,
                config: config,
                intensity: intensity
            )
            emitter.emitterShape = .line
            emitter.emitterSize = CGSize(width: bounds.width, height: 1)
            emitter.emitterMode = .outline
            emitter.beginTime = CACurrentMediaTime()
            layer.addSublayer(emitter)
            emitters.append(emitter)
        }

        // Stop emission after the emission window (precise timer, see `onComplete`)
        stopTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + emissionDuration, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.stopTimer?.cancel()
            self?.stopTimer = nil
            self?.stopEmission()
        }
        stopTimer = timer
        timer.resume()
    }

    private func stopEmission() {
        dispatchPrecondition(condition: .onQueue(.main))
        for emitter in emitters {
            emitter.birthRate = 0
        }
    }

    private func scheduleCompletion(after seconds: TimeInterval) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + max(seconds, 0), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.completionTimer?.cancel()
            self?.completionTimer = nil
            self?.onComplete?()
        }
        completionTimer = timer
        timer.resume()
    }

    /// Removes all windows and cleans up
    public func cleanup() {
        dispatchPrecondition(condition: .onQueue(.main))
        stopTimer?.cancel()
        stopTimer = nil
        completionTimer?.cancel()
        completionTimer = nil
        duration = 0
        for window in windows {
            window.contentView?.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        }
        for emitter in emitters {
            emitter.removeFromSuperlayer()
        }
        for window in windows {
            window.orderOut(nil)
        }
        for window in blizzardWindows {
            window.orderOut(nil)
        }
        windows.removeAll()
        blizzardWindows.removeAll()
        emitters.removeAll()
        blizzardCompletedCount = 0
        hasFired = false
    }
}
