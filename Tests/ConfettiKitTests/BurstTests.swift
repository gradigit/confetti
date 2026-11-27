import XCTest
@testable import ConfettiKit

final class BurstTests: XCTestCase {

    private func params(_ config: ConfettiConfig = .default, intensity: Float = 1) -> BurstParameters {
        BurstParameters(config: config, angles: .default, intensity: intensity, burstWindow: 0.15)
    }

    private func cannon(_ p: BurstParameters, height: CGFloat = 956) -> CAEmitterLayer {
        let images = ParticleImageCache(maxSizeScale: CGFloat(p.sizeScale * (1 + p.sizeJitter)), screenScale: 2)
        return EmitterBurst.makeCannon(at: .zero, aimDegrees: p.leftAimDegrees,
                                       in: CGRect(x: 0, y: 0, width: 1470, height: height),
                                       params: p, images: images, screenScale: 2)
    }

    // MARK: - Parameter mapping

    func testDefaultParametersMatchTunedBurst() {
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
    }

    // MARK: - Emitter

    func testPrivateBehaviorsAvailable() {
        // If this starts failing on a new macOS, confetti still works: the controller falls back
        // to the 1.2.0 emitter. It just loses the drag, sway and fade.
        XCTAssertTrue(EmitterBurst.isAvailable, "CAEmitterBehavior missing: confetti will use the 1.2.0 emitter")
    }

    func testFlipFramesAvailable() {
        // Without them pieces fall back to 3D plane particles (no flip strip, no darker back).
        XCTAssertTrue(EmitterBurst.flipAvailable, "emitter sprite-sheet frames missing: no paper flip")
    }

    func testCannonCellsCoverEveryColourShapeAndFlipSpeed() throws {
        try XCTSkipUnless(EmitterBurst.isAvailable && EmitterBurst.flipAvailable)
        let p = params()
        let e = cannon(p)
        XCTAssertEqual(e.emitterCells?.count, p.colors.count * p.shapes.count * p.flipSpeeds.count)
        // Total birth rate over the burst window releases perCannon particles
        let total = (e.emitterCells ?? []).reduce(Float(0)) { $0 + $1.birthRate } * p.burstWindow
        XCTAssertEqual(total, Float(p.perCannon), accuracy: 0.5)
    }

    func testCannonPhysics() throws {
        try XCTSkipUnless(EmitterBurst.isAvailable)
        let p = params()
        let cell = try XCTUnwrap(cannon(p, height: 956).emitterCells?.first)
        XCTAssertEqual(cell.velocity, CGFloat(p.speedMin + p.speedMax) / 2, accuracy: 0.5)
        XCTAssertEqual(cell.yAcceleration, -900, accuracy: 0.01)
        XCTAssertEqual(cell.emissionRange, 25 * 1.7 * .pi / 180, accuracy: 1e-4)
        XCTAssertEqual(cell.lifetime + cell.lifetimeRange, p.lifeMax, accuracy: 1e-4)
        XCTAssertEqual(cell.contentsScale, 2)
        // Launch speed scales with screen height so the burst fills any screen the same way
        let tall = try XCTUnwrap(cannon(p, height: 1912).emitterCells?.first)
        XCTAssertEqual(tall.velocity, cell.velocity * 2, accuracy: 0.5)
    }

    // `type` is a plain method; the behavior class's KVC only exposes its input keys
    private func type(_ b: NSObject) -> String? { b.perform(NSSelectorFromString("type"))?.takeUnretainedValue() as? String }

    func testCannonCarriesDragAndFade() throws {
        try XCTSkipUnless(EmitterBurst.isAvailable && EmitterBurst.flipAvailable)
        let behaviors = try XCTUnwrap(cannon(params()).value(forKey: "emitterBehaviors") as? [NSObject])
        XCTAssertEqual(Set(behaviors.compactMap(type)), ["drag", "valueOverLife"])
        let drag = try XCTUnwrap(behaviors.first { type($0) == "drag" })
        XCTAssertEqual((drag.value(forKey: "drag") as? NSNumber)?.doubleValue ?? 0, 2.7, accuracy: 1e-4)
    }

    func testCellsFlipAtTheirGroupSpeedAndSway() throws {
        try XCTSkipUnless(EmitterBurst.isAvailable && EmitterBurst.flipAvailable)
        let p = params()
        let cells = try XCTUnwrap(cannon(p).emitterCells)
        for (i, c) in cells.prefix(p.flipSpeeds.count).enumerated() {
            XCTAssertEqual(c.value(forKey: "particleType") as? String, "sprite")
            XCTAssertEqual((c.value(forKey: "contentsFrameCount") as? NSNumber)?.intValue, p.flipFrames)
            XCTAssertEqual(c.value(forKey: "contentsFrameMode") as? String, "random")
            XCTAssertEqual((c.value(forKey: "contentsFramesPerSecond") as? NSNumber)?.doubleValue ?? 0,
                           Double(p.flipSpeeds[i]) * Double(p.flipFrames), accuracy: 1e-3)
            XCTAssertEqual(c.contentsRect.width, 1 / CGFloat(p.flipFrames), accuracy: 1e-6)
            let wave = try XCTUnwrap((c.value(forKey: "emitterBehaviors") as? [NSObject])?.first)
            XCTAssertEqual(type(wave), "wave")
            XCTAssertEqual((wave.value(forKey: "frequency") as? NSNumber)?.doubleValue ?? 0,
                           Double(p.swayFrequencies[i]), accuracy: 1e-4)
        }
    }

    func testOnlyConfiguredShapesAndColors() throws {
        try XCTSkipUnless(EmitterBurst.isAvailable)
        let p = params(ConfettiConfig(colors: [.systemRed], shapes: [.circle]))
        XCTAssertEqual(cannon(p).emitterCells?.count, EmitterBurst.flipAvailable ? p.flipSpeeds.count : 1)
    }

    // MARK: - Images

    func testImagesDrawnAtPixelScale() {
        let cache = ParticleImageCache(maxSizeScale: 2, screenScale: 2)
        let img = cache.image(color: SIMD3(255, 0, 0), shape: .rectangle)
        XCTAssertEqual(img.width, 56)    // 14 pt × 2 × 2
        XCTAssertEqual(img.height, 28)
        XCTAssertTrue(img === cache.image(color: SIMD3(255, 0, 0), shape: .rectangle))
    }

    func testFlipStripHasOneFramePerStep() {
        let cache = ParticleImageCache(maxSizeScale: 2, screenScale: 2)
        let strip = cache.flipStrip(color: SIMD3(255, 0, 0), shape: .rectangle, frames: 24, backShade: 0.6)
        XCTAssertEqual(strip.width, 56 * 24)
        XCTAssertEqual(strip.height, 28)
        XCTAssertTrue(strip === cache.flipStrip(color: SIMD3(255, 0, 0), shape: .rectangle, frames: 24, backShade: 0.6))
        XCTAssertFalse(strip === cache.image(color: SIMD3(255, 0, 0), shape: .rectangle))
    }

    // MARK: - End to end

    func testControllerCompletesShortBurstOnScreen() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no display") }
        let config = ConfettiConfig(birthRate: 5, lifetime: 0.4)
        let controller = ConfettiController(config: config, emissionDuration: 0.05)
        let done = expectation(description: "onComplete")
        controller.onComplete = { done.fulfill() }
        controller.fire(on: [screen])
        XCTAssertEqual(controller.duration, 0.05 + 0.4, accuracy: 1e-6)
        wait(for: [done], timeout: controller.duration + 2)
        controller.cleanup()
        XCTAssertEqual(controller.duration, 0)
    }

    func testZeroIntensityCompletesImmediately() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no display") }
        let controller = ConfettiController(intensity: 0)
        let done = expectation(description: "onComplete")
        controller.onComplete = { done.fulfill() }
        controller.fire(on: [screen])
        XCTAssertEqual(controller.duration, EmitterBurst.isAvailable ? 0 : 0.15 + 4.5, accuracy: 1e-6)
        wait(for: [done], timeout: controller.duration + 1)
        controller.cleanup()
    }
}
