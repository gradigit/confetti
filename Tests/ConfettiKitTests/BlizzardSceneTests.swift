import XCTest
import SpriteKit
@testable import ConfettiKit

final class BlizzardSceneTests: XCTestCase {

    var scene: BlizzardScene!

    override func setUp() {
        super.setUp()
        // Use a reasonable size for the scene
        let size = CGSize(width: 800, height: 600)
        scene = BlizzardScene(size: size)
    }

    override func tearDown() {
        scene = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(scene)
        XCTAssertEqual(scene.size, CGSize(width: 800, height: 600))
        XCTAssertEqual(scene.anchorPoint, .zero)

        // Colors can fail equality checks across color spaces (e.g. NSDeviceRGB vs Generic Gray)
        // Check components instead or allow for color space differences
        let color = scene.backgroundColor
        XCTAssertEqual(color.alphaComponent, 0.0)

        // Verify nodes are added: pileNode, glowNode, repulsionField
        XCTAssertEqual(scene.children.count, 3)
    }

    func testAddSessionLayer() {
        let layer = scene.addSessionLayer(sessionID: "test-session")
        XCTAssertEqual(layer.sessionID, "test-session")
        XCTAssertEqual(layer.sessionIndex, 0)
        XCTAssertEqual(scene.activeSessionCount, 1)

        // Verify layer nodes are added to scene
        // windField (1) + 3 puff emitters + 5 sparkles = 9 nodes per layer
        // Initial 3 nodes + 9 = 12
        XCTAssertEqual(scene.children.count, 12)
    }

    func testRemoveSessionLayer() {
        scene.addSessionLayer(sessionID: "test-session")
        XCTAssertEqual(scene.activeSessionCount, 1)

        scene.removeSessionLayer(sessionID: "test-session")
        // Removal sets isFadingOut = true immediately
        XCTAssertEqual(scene.activeSessionCount, 0)

        // Note: The actual removal of nodes happens async after fade out duration.
        // We can't easily test the async cleanup in a unit test without expectations.
    }

    func testUpdateLoop() {
        scene.addSessionLayer(sessionID: "test-session")

        // Simulate a few frames
        scene.update(0.0)
        scene.update(0.1)
        scene.update(0.2)

        // Ensure no crash
    }

    func testStopSnowing() {
        scene.addSessionLayer(sessionID: "test-session")
        scene.stopSnowing()

        // stopSnowing logic sets flags but doesn't change activeSessionCount immediately
        // (unless layers were already fading).
        // It starts the melt process.

        scene.update(0.3)
        // Should not crash
    }
}
