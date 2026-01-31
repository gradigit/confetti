import XCTest
@testable import ConfettiKit

final class ConfettiEmitterTests: XCTestCase {

    func testCreateEmitter() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let emitter = ConfettiEmitter.createEmitter(
            at: CGPoint(x: 0, y: 0),
            angle: .pi / 2,
            in: bounds
        )

        XCTAssertEqual(emitter.emitterPosition, CGPoint(x: 0, y: 0))
        XCTAssertEqual(emitter.emitterShape, .point)
        XCTAssertEqual(emitter.frame, bounds)
        XCTAssertNotNil(emitter.emitterCells)
    }

    func testEmitterCellCount() {
        let config = ConfettiConfig.default
        let expectedCells = config.colors.count * config.shapes.count

        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let emitter = ConfettiEmitter.createEmitter(
            at: .zero,
            angle: .pi / 2,
            in: bounds,
            config: config
        )

        XCTAssertEqual(emitter.emitterCells?.count, expectedCells)
    }

    func testCellCountCalculation() {
        let config = ConfettiConfig(
            colors: [.red, .blue, .green],
            shapes: [.rectangle, .circle]
        )

        let count = ConfettiEmitter.cellCount(for: config)
        XCTAssertEqual(count, 6) // 3 colors × 2 shapes
    }

    func testEstimatedParticleCount() {
        let config = ConfettiConfig(
            birthRate: 10,
            colors: [.red],
            shapes: [.rectangle]
        )

        // 10 birthRate × 1 cell × 2 emitters × 1.0 second = 20 particles
        let estimate = ConfettiEmitter.estimatedParticleCount(
            config: config,
            emissionDuration: 1.0,
            emitterCount: 2
        )

        XCTAssertEqual(estimate, 20)
    }

    func testEmitterWithCustomIntensity() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let config = ConfettiConfig(birthRate: 100, colors: [.red], shapes: [.rectangle])

        let emitter = ConfettiEmitter.createEmitter(
            at: .zero,
            angle: .pi / 2,
            in: bounds,
            config: config,
            intensity: 0.5
        )

        // With intensity 0.5, birth rate should be halved
        if let cell = emitter.emitterCells?.first {
            XCTAssertEqual(cell.birthRate, 50) // 100 * 0.5
        } else {
            XCTFail("No emitter cells created")
        }
    }

    func testEmitterPosition() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let position = CGPoint(x: 100, y: 200)

        let emitter = ConfettiEmitter.createEmitter(
            at: position,
            angle: .pi / 2,
            in: bounds
        )

        XCTAssertEqual(emitter.emitterPosition, position)
    }

    func testEmitterAngle() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let angle: CGFloat = .pi / 3

        let emitter = ConfettiEmitter.createEmitter(
            at: .zero,
            angle: angle,
            in: bounds,
            config: ConfettiConfig(colors: [.red], shapes: [.rectangle])
        )

        if let cell = emitter.emitterCells?.first {
            XCTAssertEqual(cell.emissionLongitude, angle)
        } else {
            XCTFail("No emitter cells created")
        }
    }

    func testEmitterRenderMode() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let emitter = ConfettiEmitter.createEmitter(
            at: .zero,
            angle: .pi / 2,
            in: bounds
        )

        XCTAssertEqual(emitter.renderMode, .oldestFirst)
    }

    func testEmitterDrawsAsynchronously() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let emitter = ConfettiEmitter.createEmitter(
            at: .zero,
            angle: .pi / 2,
            in: bounds
        )

        XCTAssertTrue(emitter.drawsAsynchronously)
    }

    // MARK: - Edge Cases

    func testEmitterWithZeroIntensity() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let config = ConfettiConfig(birthRate: 100, colors: [.red], shapes: [.rectangle])

        let emitter = ConfettiEmitter.createEmitter(
            at: .zero,
            angle: .pi / 2,
            in: bounds,
            config: config,
            intensity: 0.0
        )

        if let cell = emitter.emitterCells?.first {
            XCTAssertEqual(cell.birthRate, 0)
        } else {
            XCTFail("No emitter cells created")
        }
    }

    func testEmitterWithZeroBounds() {
        let emitter = ConfettiEmitter.createEmitter(
            at: .zero,
            angle: .pi / 2,
            in: .zero,
            config: ConfettiConfig(colors: [.red], shapes: [.rectangle])
        )

        XCTAssertEqual(emitter.frame, .zero)
        XCTAssertNotNil(emitter.emitterCells)
    }

    func testEmitterWithSingleColorAndShape() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let config = ConfettiConfig(colors: [.white], shapes: [.circle])

        let emitter = ConfettiEmitter.createEmitter(
            at: .zero,
            angle: .pi / 2,
            in: bounds,
            config: config
        )

        XCTAssertEqual(emitter.emitterCells?.count, 1)
    }

    func testEstimatedParticleCountWithZeroIntensity() {
        let config = ConfettiConfig(birthRate: 40, colors: [.red], shapes: [.rectangle])
        let estimate = ConfettiEmitter.estimatedParticleCount(
            config: config,
            emissionDuration: 0.15,
            emitterCount: 2,
            intensity: 0.0
        )
        XCTAssertEqual(estimate, 0)
    }
}
