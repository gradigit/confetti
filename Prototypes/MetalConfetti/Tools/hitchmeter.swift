// hitchmeter: launch a binary and measure how smoothly its on-screen content updates.
// Captures the main display with every app that was running beforehand excluded, so only the
// launched process's windows (plus static wallpaper) can produce frames. ScreenCaptureKit only
// delivers a "complete" frame when content changed, so gaps between frame display times are
// dropped frames while the animation is moving.
// Usage: hitchmeter <label> <binary> [args...]
import AppKit
import ScreenCaptureKit
import CoreMedia

final class Meter: NSObject, SCStreamOutput, SCStreamDelegate {
    var times: [UInt64] = []   // mach absolute display times of complete frames
    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let atts = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = atts.first,
              let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let t = info[.displayTime] as? UInt64 else { return }
        DispatchQueue.main.async { self.times.append(t) }
    }
}

let args = CommandLine.arguments
guard args.count >= 3 else { fputs("usage: hitchmeter <label> <binary> [args...]\n", stderr); exit(2) }
let label = args[1]
let meter = Meter()
var stream: SCStream?

Task { @MainActor in
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else { exit(3) }
    let filter = SCContentFilter(display: display, excludingApplications: content.applications, exceptingWindows: [])
    let cfg = SCStreamConfiguration()
    cfg.width = display.width / 2
    cfg.height = display.height / 2
    cfg.minimumFrameInterval = CMTime(value: 1, timescale: 120)
    cfg.queueDepth = 8
    cfg.showsCursor = false
    let s = SCStream(filter: filter, configuration: cfg, delegate: meter)
    try s.addStreamOutput(meter, type: .screen, sampleHandlerQueue: DispatchQueue(label: "frames"))
    try await s.startCapture()
    stream = s
    try await Task.sleep(nanoseconds: 300_000_000)   // let capture settle

    let p = Process()
    p.executableURL = URL(fileURLWithPath: args[2])
    p.arguments = Array(args.dropFirst(3))
    try p.run()
    p.waitUntilExit()
    try await Task.sleep(nanoseconds: 200_000_000)
    try await s.stopCapture()

    var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
    let ms = meter.times.map { Double($0) * Double(tb.numer) / Double(tb.denom) / 1e6 }
    guard ms.count > 2 else { print("{\"label\":\"\(label)\",\"frames\":\(ms.count)}"); exit(0) }
    let gaps = zip(ms.dropFirst(), ms).map { $0 - $1 }
    let span = ms.last! - ms.first!
    let hz = CGDisplayCopyDisplayMode(CGMainDisplayID())?.refreshRate ?? 60
    let frameMs = 1000.0 / (hz > 0 ? hz : 60)
    // Missing frames = for each gap, how many vsyncs passed without an update.
    let missed = gaps.reduce(0) { $0 + max(0, Int(($1 / frameMs).rounded()) - 1) }
    let sorted = gaps.sorted()
    func f(_ x: Double) -> String { String(format: "%.1f", x) }
    // Split: first 1 s of animation vs the rest
    let t0 = ms.first!
    var missedEarly = 0, missedLate = 0
    for (i, g) in gaps.enumerated() {
        let m = max(0, Int((g / frameMs).rounded()) - 1)
        if ms[i] - t0 < 1000 { missedEarly += m } else { missedLate += m }
    }
    print("{\"label\":\"\(label)\",\"frames\":\(ms.count),\"span_ms\":\(f(span)),\"fps\":\(f(Double(ms.count - 1) / span * 1000)),"
        + "\"missed\":\(missed),\"missed_first_1s\":\(missedEarly),\"missed_after\":\(missedLate),"
        + "\"gap_p50_ms\":\(f(sorted[sorted.count / 2])),\"gap_p99_ms\":\(f(sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.99))])),\"gap_max_ms\":\(f(sorted.last!))}")
    exit(0)
}
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
