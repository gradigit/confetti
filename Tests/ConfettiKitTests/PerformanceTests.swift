import XCTest
@testable import ConfettiKit

final class PerformanceTests: XCTestCase {

    func testEmitterCreationPerformance() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        measure {
            for _ in 0..<100 {
                _ = ConfettiEmitter.createEmitter(
                    at: .zero,
                    angle: .pi / 2,
                    in: bounds
                )
            }
        }
    }

    func testEmitterCreationWithMinimalConfigPerformance() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let config = ConfettiConfig(
            colors: [.red],
            shapes: [.rectangle]
        )

        measure {
            for _ in 0..<100 {
                _ = ConfettiEmitter.createEmitter(
                    at: .zero,
                    angle: .pi / 2,
                    in: bounds,
                    config: config
                )
            }
        }
    }

    func testCellCountCalculationPerformance() {
        let config = ConfettiConfig.default

        measure {
            for _ in 0..<10000 {
                _ = ConfettiEmitter.cellCount(for: config)
            }
        }
    }

    func testEstimatedParticleCountPerformance() {
        let config = ConfettiConfig.default

        measure {
            for _ in 0..<10000 {
                _ = ConfettiEmitter.estimatedParticleCount(
                    config: config,
                    emissionDuration: 0.15,
                    emitterCount: 2
                )
            }
        }
    }

    func testConfigCreationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = ConfettiConfig(
                    birthRate: 30,
                    lifetime: 4.5,
                    velocity: 1250,
                    velocityRange: 400,
                    emissionRange: .pi * 0.4,
                    gravity: -750,
                    spin: 8.0,
                    spinRange: 16.0,
                    scale: 0.8,
                    scaleRange: 0.05,
                    scaleSpeed: -0.1,
                    alphaSpeed: -0.15,
                    colors: [.systemRed, .systemGreen, .systemBlue, .systemYellow,
                             .systemOrange, .systemPurple, .systemPink, .cyan],
                    shapes: [.rectangle, .triangle, .circle]
                )
            }
        }
    }

    func testControllerCreationPerformance() {
        measure {
            for _ in 0..<100 {
                _ = ConfettiController(
                    config: .default,
                    angles: .default,
                    emissionDuration: 0.15,
                    intensity: 1.0
                )
            }
        }
    }
}
