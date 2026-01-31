import AppKit

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
    private var emitters: [CAEmitterLayer] = []
    private var hasFired = false
    private var stopWorkItem: DispatchWorkItem?

    public let config: ConfettiConfig
    public let angles: CannonAngles
    public let emissionDuration: TimeInterval
    public let intensity: Float

    /// Creates a confetti controller
    /// - Parameters:
    ///   - config: Configuration for the confetti particles
    ///   - angles: Angles for the left and right cannons
    ///   - emissionDuration: How long to emit particles
    ///   - intensity: Multiplier for particle birth rate
    public init(
        config: ConfettiConfig = .default,
        angles: CannonAngles = .default,
        emissionDuration: TimeInterval = 0.15,
        intensity: Float = 1.0
    ) {
        self.config = config
        self.angles = angles
        self.emissionDuration = emissionDuration
        self.intensity = intensity
    }

    /// Fires confetti on specified screens
    /// - Parameter screens: Screens to display confetti on. Defaults to all screens.
    public func fire(on screens: [NSScreen]? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !hasFired else { return }
        hasFired = true

        let targetScreens = screens ?? NSScreen.screens
        guard !targetScreens.isEmpty else { return }

        // Create windows
        for screen in targetScreens {
            let window = ConfettiWindow(screen: screen)
            window.orderFrontRegardless()
            windows.append(window)
        }

        // Force windows to render before adding emitters
        for window in windows {
            window.contentView?.layer?.display()
        }
        CATransaction.flush()

        // Add emitters immediately after flush
        addEmitters()
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

    private func addEmitters() {
        for window in windows {
            guard let layer = window.contentView?.layer else { continue }
            let bounds = layer.bounds

            switch config.emissionStyle {
            case .cannons:
                // Left cannon (bottom-left corner, firing up)
                let left = ConfettiEmitter.createEmitter(
                    at: CGPoint(x: 0, y: 0),
                    angle: angles.left,
                    in: bounds,
                    config: config,
                    intensity: intensity
                )
                left.beginTime = CACurrentMediaTime()
                layer.addSublayer(left)
                emitters.append(left)

                // Right cannon (bottom-right corner, firing up)
                let right = ConfettiEmitter.createEmitter(
                    at: CGPoint(x: bounds.width, y: 0),
                    angle: angles.right,
                    in: bounds,
                    config: config,
                    intensity: intensity
                )
                right.beginTime = CACurrentMediaTime()
                layer.addSublayer(right)
                emitters.append(right)

            case .curtain:
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
        }

        // Stop emission after burst
        stopWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.stopEmission()
        }
        stopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + emissionDuration, execute: workItem)
    }

    private func stopEmission() {
        dispatchPrecondition(condition: .onQueue(.main))
        for emitter in emitters {
            emitter.birthRate = 0
        }
    }

    /// Removes all windows and cleans up
    public func cleanup() {
        dispatchPrecondition(condition: .onQueue(.main))
        stopWorkItem?.cancel()
        stopWorkItem = nil
        for emitter in emitters {
            emitter.removeFromSuperlayer()
        }
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        emitters.removeAll()
        hasFired = false
    }
}
