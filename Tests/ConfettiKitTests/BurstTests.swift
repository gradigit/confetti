import XCTest
@testable import ConfettiKit

final class BurstTests: XCTestCase {

    private func params(_ config: ConfettiConfig = .default, intensity: Float = 1) -> BurstParameters {
        BurstParameters(config: config, angles: .default, intensity: intensity, burstWindow: 0.15)
    }

    private func bake(_ p: BurstParameters, seed: UInt64 = 42,
                      width: CGFloat = 1470, height: CGFloat = 956) -> [ParticleTrack] {
        var rng = SeededGenerator(seed: seed)
        let sim = BurstSimulation(params: p, width: width, height: height)
        sim.fireCannon(from: .zero, aimDegrees: p.leftAimDegrees, using: &rng)
        sim.fireCannon(from: CGPoint(x: width, y: 0), aimDegrees: p.rightAimDegrees, using: &rng)
        return sim.bake()
    }

    // MARK: - Parameter mapping

    func testDefaultParametersMatchTunedPrototype() {
        let p = params()
        XCTAssertEqual(p.perCannon, 144)                 // 40/s × 24 cells × 0.15 s
        XCTAssertEqual(p.gravity, 900, accuracy: 0.01)
        XCTAssertEqual(p.speedMin, 1827, accuracy: 1)
        XCTAssertEqual(p.speedMax, 3393, accuracy: 1)
        XCTAssertEqual(p.spreadDegrees, 25, accuracy: 0.01)
        XCTAssertEqual(p.sizeScale, 1.6, accuracy: 0.001)
        XCTAssertEqual(p.sizeJitter, 0.25, accuracy: 0.001)
        XCTAssertEqual(p.maxSpin, 5, accuracy: 0.001)
        XCTAssertEqual(p.lifeMax, 4.5, accuracy: 0.001)
        XCTAssertEqual(p.lifeMin, 3.5, accuracy: 0.001)
        XCTAssertEqual(p.colors.count, 8)
    }

    func testParticleCountMatchesEstimate() {
        for config in [ConfettiConfig.default, .subtle, .intense, .fireworks] {
            let estimate = ConfettiEmitter.estimatedParticleCount(config: config, emissionDuration: 0.15)
            XCTAssertEqual(Double(params(config).perCannon * 2), Double(estimate), accuracy: 2)
        }
    }

    func testIntensityScalesParticleCount() {
        XCTAssertEqual(params(intensity: 0.5).perCannon, 72)
        XCTAssertEqual(params(intensity: 0).perCannon, 0)
        XCTAssertTrue(bake(params(intensity: 0)).isEmpty)
    }

    // MARK: - Simulation

    func testBakeIsDeterministicForSeed() {
        let a = bake(params(), seed: 7), b = bake(params(), seed: 7), c = bake(params(), seed: 8)
        XCTAssertEqual(a.count, b.count)
        XCTAssertEqual(a.map(\.points), b.map(\.points))
        XCTAssertNotEqual(a.map(\.points), c.map(\.points))
    }

    func testNearlyAllParticlesBecomeTracks() {
        // A particle is dropped only if it lives < 2 sim frames; that shouldn't happen at launch speeds.
        XCTAssertEqual(bake(params()).count, 288)
    }

    func testTrackTimingIsWellFormed() {
        let p = params()
        for t in bake(params()) {
            XCTAssertGreaterThanOrEqual(t.points.count, 2)
            XCTAssertEqual(t.points.count, t.keyTimes.count)
            XCTAssertEqual(t.keyTimes.first, 0)
            XCTAssertEqual(t.keyTimes.last, 1)
            XCTAssertEqual(t.keyTimes, t.keyTimes.sorted())
            XCTAssertGreaterThan(t.duration, 0)
            XCTAssertLessThanOrEqual(t.birth, Double(p.burstWindow) + 1.0 / 60)
            XCTAssertLessThanOrEqual(t.birth + t.duration, Double(p.burstWindow + p.lifeMax) + 1.0 / 30)
        }
    }

    func testParticlesStartAtTheirCannon() {
        let width: CGFloat = 1470
        for t in bake(params(), width: width) {
            let x = t.points[0].x
            XCTAssertTrue(x < 200 || x > width - 200, "first sample at x=\(x), far from both cannons")
            XCTAssertLessThan(t.points[0].y, 150)
        }
    }

    func testDragCapsFallSpeedAtTerminalVelocity() {
        let p = params()
        let terminal = CGFloat(p.gravity / p.dragMin)   // slowest drag = fastest possible fall
        for t in bake(p) {
            for k in 1..<t.points.count {
                let dt = (t.keyTimes[k] - t.keyTimes[k - 1]) * t.duration
                guard dt > 0 else { continue }
                let vy = (t.points[k].y - t.points[k - 1].y) / CGFloat(dt)
                if vy < 0 { XCTAssertLessThanOrEqual(-vy, terminal * 1.02) }
            }
        }
    }

    func testOldAgeFadesOut() {
        // Particles that die of old age on screen end transparent; ones that fell off end opaque.
        let tracks = bake(params())
        XCTAssertTrue(tracks.contains { $0.endAlpha < 0.05 } || tracks.allSatisfy { $0.points.last!.y < 0 })
        for t in tracks { XCTAssertTrue((0...1).contains(t.endAlpha)) }
    }

    func testOnlyConfiguredShapesAndColors() {
        let config = ConfettiConfig(colors: [.systemRed], shapes: [.circle])
        let tracks = bake(params(config))
        XCTAssertFalse(tracks.isEmpty)
        XCTAssertTrue(tracks.allSatisfy { $0.shape == .circle })
        XCTAssertEqual(Set(tracks.map { [$0.color.x, $0.color.y, $0.color.z] }).count, 1)
    }

    // MARK: - Images

    func testImagesDrawnAtPixelScale() {
        let cache = ParticleImageCache(maxSizeScale: 2, screenScale: 2)
        let img = cache.image(color: SIMD3(255, 0, 0), shape: .rectangle, back: false)
        XCTAssertEqual(img.width, 56)    // 14 pt × 2 × 2
        XCTAssertEqual(img.height, 28)
        let back = cache.image(color: SIMD3(255, 0, 0), shape: .rectangle, back: true)
        XCTAssertFalse(img === back)
        XCTAssertTrue(img === cache.image(color: SIMD3(255, 0, 0), shape: .rectangle, back: false))
    }

    // MARK: - Layers

    func testLayersCarryAnimationsAndDuration() {
        let tracks = bake(params())
        let root = CALayer()
        let cache = ParticleImageCache(maxSizeScale: 2, screenScale: 2)
        let end = ConfettiBurst.addLayers(for: tracks, to: root, scale: 2, images: cache)
        XCTAssertEqual(root.sublayers?.count, tracks.count)
        let latest = tracks.map { $0.birth + $0.duration }.max()!
        XCTAssertEqual(end, latest + 1.0 / 60, accuracy: 1e-9)
        let outer = root.sublayers![0]
        XCTAssertEqual(outer.opacity, 0)                          // hidden outside its animation
        XCTAssertNotNil(outer.animation(forKey: "confetti"))
        XCTAssertNotNil(outer.sublayers?.first?.animation(forKey: "flutter"))
        XCTAssertEqual(outer.animation(forKey: "confetti")?.isRemovedOnCompletion, false)
    }

    // MARK: - End to end

    func testControllerCompletesShortBurstOnScreen() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no display") }
        let config = ConfettiConfig(birthRate: 5, lifetime: 0.4)
        let controller = ConfettiController(config: config, emissionDuration: 0.05)
        let done = expectation(description: "onComplete")
        controller.onComplete = { done.fulfill() }
        controller.fire(on: [screen])
        XCTAssertGreaterThan(controller.duration, 0)
        XCTAssertLessThanOrEqual(controller.duration, 0.05 + 0.4 + 0.05)
        wait(for: [done], timeout: controller.duration + 2)
        controller.cleanup()
        XCTAssertEqual(controller.duration, 0)
    }
}
