import XCTest
@testable import ConfettiKit

final class ConfettiControllerTests: XCTestCase {

    func testDefaultController() {
        let controller = ConfettiController()

        XCTAssertEqual(controller.emissionDuration, 0.15)
        XCTAssertEqual(controller.intensity, 1.0)
    }

    func testControllerWithCustomConfig() {
        let config = ConfettiConfig(birthRate: 50)
        let controller = ConfettiController(
            config: config,
            emissionDuration: 0.2,
            intensity: 0.8
        )

        XCTAssertEqual(controller.config.birthRate, 50)
        XCTAssertEqual(controller.emissionDuration, 0.2)
        XCTAssertEqual(controller.intensity, 0.8)
    }

    func testDefaultAngles() {
        let angles = ConfettiController.CannonAngles.default

        // ~85° and ~95°
        XCTAssertEqual(angles.left, .pi * 0.47, accuracy: 0.01)
        XCTAssertEqual(angles.right, .pi * 0.53, accuracy: 0.01)
    }

    func testCustomAngles() {
        let angles = ConfettiController.CannonAngles(
            left: .pi / 4,
            right: 3 * .pi / 4
        )

        XCTAssertEqual(angles.left, .pi / 4)
        XCTAssertEqual(angles.right, 3 * .pi / 4)
    }

    func testEstimatedParticleCount() {
        let config = ConfettiConfig(
            birthRate: 10,
            colors: [.red, .blue],
            shapes: [.rectangle]
        )

        let controller = ConfettiController(
            config: config,
            emissionDuration: 1.0
        )

        // 10 birthRate × 2 colors × 1 shape × 2 emitters × 1 second = 40
        let estimate = controller.estimatedParticleCount(emitterCount: 2)
        XCTAssertEqual(estimate, 40)
    }

    func testEstimatedParticleCountDefault() {
        let controller = ConfettiController()

        // 40 birthRate × 8 colors × 3 shapes × 2 emitters × 0.15 sec = 288
        let estimate = controller.estimatedParticleCount()
        XCTAssertEqual(estimate, 288)
    }

    // MARK: - Fire / Cleanup Tests

    func testFireWithEmptyScreens() {
        let controller = ConfettiController()
        // Should not crash when given empty array
        controller.fire(on: [])
    }

    func testCleanupOnUnfiredController() {
        let controller = ConfettiController()
        // Should not crash when cleaning up without firing
        controller.cleanup()
    }

    func testDoubleFire() {
        let controller = ConfettiController()
        // First fire with empty screens (no display required)
        controller.fire(on: [])
        // Second fire should be a no-op (hasFired guard)
        controller.fire(on: [])
    }

    func testCleanupThenRefire() {
        let controller = ConfettiController()
        controller.fire(on: [])
        controller.cleanup()
        // After cleanup, should be able to fire again
        controller.fire(on: [])
    }
}
