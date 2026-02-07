import AppKit
import SpriteKit

/// A transparent, click-through window that hosts the snow accumulation scene
final class SnowWindow: NSWindow {

    let skView: SKView
    let snowScene: SnowScene

    init(screen: NSScreen) {
        let skView = SKView(frame: CGRect(origin: .zero, size: screen.frame.size))
        self.skView = skView
        self.snowScene = SnowScene(size: screen.frame.size)

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        skView.allowsTransparency = true
        skView.preferredFramesPerSecond = 60
        skView.showsFPS = true
        skView.showsNodeCount = true
        skView.showsDrawCount = true

        snowScene.scaleMode = .resizeFill
        snowScene.backgroundColor = .clear
        skView.presentScene(snowScene)

        contentView = skView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
