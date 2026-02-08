import AppKit

// MARK: - Argument Parsing

func parseMode() -> SceneMode {
    let args = CommandLine.arguments
    if let modeIndex = args.firstIndex(of: "--mode"), modeIndex + 1 < args.count {
        let value = args[modeIndex + 1].lowercased()
        switch value {
        case "confetti":
            return .confetti
        case "snow":
            return .snow
        default:
            fputs("Unknown mode '\(value)'. Use 'snow' or 'confetti'.\n", stderr)
            exit(1)
        }
    }
    return .snow
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [SnowWindow] = []
    let mode: SceneMode

    init(mode: SceneMode) {
        self.mode = mode
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        guard !NSScreen.screens.isEmpty else {
            fputs("Error: no screens available\n", stderr)
            NSApp.terminate(nil)
            return
        }

        // Create a window for each screen
        for screen in NSScreen.screens {
            let window = SnowWindow(screen: screen, mode: mode)
            window.orderFrontRegardless()
            windows.append(window)
        }

        // Runs indefinitely until killed
    }
}

// MARK: - Main

let mode = parseMode()
let app = NSApplication.shared
let delegate = AppDelegate(mode: mode)
app.delegate = delegate
app.run()
