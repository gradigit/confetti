import AppKit

/// Transparent click-through overlay window hosting the CA-based snow view
final class SnowWindow: NSWindow {

    let snowView: SnowLayerView

    init(screen: NSScreen) {
        snowView = SnowLayerView(frame: CGRect(origin: .zero, size: screen.frame.size))

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

        contentView = snowView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
