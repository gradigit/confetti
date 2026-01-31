import AppKit
import QuartzCore

/// A transparent, click-through window for displaying confetti
final class ConfettiWindow: NSWindow {

    /// Creates a confetti window covering the specified screen
    /// - Parameter screen: The screen to cover with confetti
    convenience init(screen: NSScreen) {
        self.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        configureWindow(for: screen)
    }

    private func configureWindow(for screen: NSScreen) {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let bounds = CGRect(origin: .zero, size: screen.frame.size)
        let contentView = NSView(frame: bounds)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = .clear
        self.contentView = contentView
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
