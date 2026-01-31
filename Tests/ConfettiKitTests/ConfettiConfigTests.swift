import XCTest
@testable import ConfettiKit

final class ConfettiConfigTests: XCTestCase {

    func testDefaultConfig() {
        let config = ConfettiConfig.default

        XCTAssertEqual(config.birthRate, 40)
        XCTAssertEqual(config.lifetime, 4.5)
        XCTAssertEqual(config.velocity, 1500)
        XCTAssertEqual(config.velocityRange, 450)
        XCTAssertEqual(config.emissionRange, .pi * 0.4)
        XCTAssertEqual(config.gravity, -750)
        XCTAssertEqual(config.spin, 12.0)
        XCTAssertEqual(config.spinRange, 20.0)
        XCTAssertEqual(config.scale, 0.8)
        XCTAssertEqual(config.scaleRange, 0.2)
        XCTAssertEqual(config.scaleSpeed, -0.1)
        XCTAssertEqual(config.alphaSpeed, -0.15)
        XCTAssertEqual(config.colors.count, 8)
        XCTAssertEqual(config.shapes.count, 3)
    }

    func testDefaultMatchesInit() {
        let explicit = ConfettiConfig.default
        let implicit = ConfettiConfig()

        XCTAssertEqual(explicit.birthRate, implicit.birthRate)
        XCTAssertEqual(explicit.lifetime, implicit.lifetime)
        XCTAssertEqual(explicit.velocity, implicit.velocity)
        XCTAssertEqual(explicit.velocityRange, implicit.velocityRange)
        XCTAssertEqual(explicit.emissionRange, implicit.emissionRange)
        XCTAssertEqual(explicit.gravity, implicit.gravity)
        XCTAssertEqual(explicit.spin, implicit.spin)
        XCTAssertEqual(explicit.spinRange, implicit.spinRange)
        XCTAssertEqual(explicit.scale, implicit.scale)
        XCTAssertEqual(explicit.scaleRange, implicit.scaleRange)
        XCTAssertEqual(explicit.scaleSpeed, implicit.scaleSpeed)
        XCTAssertEqual(explicit.alphaSpeed, implicit.alphaSpeed)
        XCTAssertEqual(explicit.colors.count, implicit.colors.count)
        XCTAssertEqual(explicit.shapes.count, implicit.shapes.count)
    }

    func testCustomConfig() {
        let config = ConfettiConfig(
            birthRate: 50,
            lifetime: 3.0,
            velocity: 1000,
            colors: [.red, .blue],
            shapes: [.rectangle]
        )

        XCTAssertEqual(config.birthRate, 50)
        XCTAssertEqual(config.lifetime, 3.0)
        XCTAssertEqual(config.velocity, 1000)
        XCTAssertEqual(config.colors.count, 2)
        XCTAssertEqual(config.shapes.count, 1)
    }

    func testConfigWithAllShapes() {
        let config = ConfettiConfig.default
        XCTAssertTrue(config.shapes.contains(.rectangle))
        XCTAssertTrue(config.shapes.contains(.triangle))
        XCTAssertTrue(config.shapes.contains(.circle))
    }

    func testCustomScaleSpeed() {
        let config = ConfettiConfig(scaleSpeed: -0.3)
        XCTAssertEqual(config.scaleSpeed, -0.3)
    }

    func testAllShapeCases() {
        let allShapes = ConfettiShape.allCases
        XCTAssertEqual(allShapes.count, 3)
        XCTAssertTrue(allShapes.contains(.rectangle))
        XCTAssertTrue(allShapes.contains(.triangle))
        XCTAssertTrue(allShapes.contains(.circle))
    }
}
