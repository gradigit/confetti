import AppKit
import SpriteKit

/// A transparent, click-through window that hosts the blizzard scene
final class BlizzardWindow: NSWindow {

    let skView: SKView
    let blizzardScene: BlizzardScene

    init(screen: NSScreen) {
        let skView = SKView(frame: CGRect(origin: .zero, size: screen.frame.size))
        self.skView = skView
        self.blizzardScene = BlizzardScene(size: screen.frame.size)

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
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        skView.allowsTransparency = true
        skView.preferredFramesPerSecond = 60

        blizzardScene.scaleMode = .resizeFill
        blizzardScene.backgroundColor = .clear
        skView.presentScene(blizzardScene)

        contentView = skView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
