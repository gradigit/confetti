import AppKit
import QuartzCore

/// A transparent, click-through window for displaying confetti
final class ConfettiWindow: NSWindow {

    /// Creates a confetti window covering the specified screen
    /// - Parameters:
    ///   - screen: The screen to cover with confetti
    ///   - windowLevel: Window level for the overlay
    convenience init(screen: NSScreen, windowLevel: WindowLevel = .statusBar) {
        self.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        configureWindow(for: screen, windowLevel: windowLevel)
    }

    private func configureWindow(for screen: NSScreen, windowLevel: WindowLevel = .statusBar) {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = windowLevel.nsWindowLevel
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
