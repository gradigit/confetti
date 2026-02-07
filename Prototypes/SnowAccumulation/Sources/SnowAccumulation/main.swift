import AppKit

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [SnowWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        guard !NSScreen.screens.isEmpty else {
            fputs("Error: no screens available\n", stderr)
            NSApp.terminate(nil)
            return
        }

        // Create a window for each screen
        for screen in NSScreen.screens {
            let window = SnowWindow(screen: screen)
            window.orderFrontRegardless()
            windows.append(window)
        }

        // Runs indefinitely until killed
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
