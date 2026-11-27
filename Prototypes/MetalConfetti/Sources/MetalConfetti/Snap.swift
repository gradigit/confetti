import AppKit
import ScreenCaptureKit

/// Screenshots of this process's own windows on the main screen (confetti overlay + black
/// backdrop). The filter lists only our windows, so no other app's content can be captured.
enum Snap {
    static func schedule(dir: String, times: [Double], label: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for t in times {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                Task { await capture(to: "\(dir)/\(label)-\(String(format: "%.2f", t)).png") }
            }
        }
    }

    static func capture(to path: String) async {
        for _ in 0..<4 {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                let pid = ProcessInfo.processInfo.processIdentifier
                let mine = content.windows.filter { $0.owningApplication?.processID == pid }
                guard !mine.isEmpty,
                      let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else { return }
                let filter = SCContentFilter(display: display, including: mine)
                let cfg = SCStreamConfiguration()
                cfg.width = display.width; cfg.height = display.height; cfg.showsCursor = false
                let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
                try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
                    .write(to: URL(fileURLWithPath: path))
                return
            } catch {
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
        fputs("snap failed: \(path)\n", stderr)
    }
}
