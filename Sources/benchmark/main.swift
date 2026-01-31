import AppKit
import ConfettiKit

// MARK: - Benchmark Infrastructure

/// Prevents the compiler from optimising away unused results.
/// The global var ensures the compiler can't prove the store is dead.
private var _sink: Any = 0

@inline(never)
func blackHole<T>(_ value: T) {
    _sink = value
}

/// Monotonic nanosecond timestamp (not affected by NTP / clock drift)
@inline(__always)
func now() -> UInt64 {
    clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
}

struct Stats {
    let name: String
    let totalIterations: Int
    let medianNs: Double
    let meanNs: Double
    let minNs: Double
    let maxNs: Double
    let stddevNs: Double
    let p95Ns: Double
}

/// Measures per-call time by timing `batchSize` calls together (to exceed
/// clock resolution), repeated `runs` times for statistics.
func benchmark(
    _ name: String,
    batchSize: Int = 10000,
    runs: Int = 20,
    warmup: Int = 3,
    _ block: () -> Void
) -> Stats {
    // Warmup
    for _ in 0..<warmup {
        for _ in 0..<batchSize { block() }
    }

    // Measured runs — each run times batchSize calls, then divides
    var samples = [Double]()
    samples.reserveCapacity(runs)

    for _ in 0..<runs {
        let t0 = now()
        for _ in 0..<batchSize { block() }
        let t1 = now()
        samples.append(Double(t1 &- t0) / Double(batchSize))
    }

    samples.sort()
    let n = Double(runs)
    let mean = samples.reduce(0, +) / n
    let variance = samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
    let mid = runs / 2
    let median = runs % 2 == 0 ? (samples[mid - 1] + samples[mid]) / 2 : samples[mid]
    let p95 = samples[min(Int(n * 0.95), runs - 1)]

    return Stats(
        name: name, totalIterations: batchSize * runs,
        medianNs: median, meanNs: mean,
        minNs: samples.first ?? 0, maxNs: samples.last ?? 0,
        stddevNs: variance.squareRoot(), p95Ns: p95
    )
}

// MARK: - Formatting Helpers

/// Formats nanoseconds into the most readable unit (fixed 11-char width)
func fmt(_ ns: Double) -> String {
    if ns >= 1_000_000 {
        return String(format: "%8.2f ms", ns / 1_000_000)
    } else if ns >= 1000 {
        return String(format: "%8.2f \u{00B5}s", ns / 1000)
    } else {
        return String(format: "%8.1f ns", ns)
    }
}

/// Left-align text in a field of `width` characters
func lpad(_ text: String, _ width: Int) -> String {
    if text.count >= width { return String(text.prefix(width)) }
    return text + String(repeating: " ", count: width - text.count)
}

/// Right-align text in a field of `width` characters
func rpad(_ text: String, _ width: Int) -> String {
    if text.count >= width { return String(text.prefix(width)) }
    return String(repeating: " ", count: width - text.count) + text
}

let innerWidth = 96

func fullBorder(_ left: String, _ fill: String, _ right: String) -> String {
    left + String(repeating: fill, count: innerWidth) + right
}

func tableBorder(_ left: String, _ fill: String, _ sep: String, _ right: String) -> String {
    let cols = [36, 7, 12, 12, 12, 12]
    return left + cols.map { String(repeating: fill, count: $0) }.joined(separator: sep) + right
}

func centered(_ text: String) -> String {
    let p = max(0, innerWidth - text.count)
    return String(repeating: " ", count: p / 2) + text + String(repeating: " ", count: p - p / 2)
}

func printRow(_ s: Stats) {
    print("║ \(lpad(s.name, 35))│\(rpad(String(s.totalIterations), 7))│\(fmt(s.medianNs))│\(fmt(s.p95Ns))│\(fmt(s.minNs))│\(fmt(s.stddevNs))║")
}

// MARK: - Run Benchmarks

@discardableResult
func runBenchmarks() -> [Stats] {
    // ── System Info ──────────────────────────────────────────────────────────
    print(fullBorder("╔", "═", "╗"))
    print("║\(centered("CONFETTI BENCHMARK SUITE v2.0"))║")
    print(fullBorder("╚", "═", "╝"))
    print("")
    print("System: macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("Date:   \(ISO8601DateFormatter().string(from: Date()))")
    print("CPU:    \(ProcessInfo.processInfo.processorCount) cores")
    print("Memory: \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB")
    print("Timer:  CLOCK_MONOTONIC_RAW")
    print("")

    // ── Timing Benchmarks ───────────────────────────────────────────────────
    print(fullBorder("╔", "═", "╗"))
    print("║\(centered("TIMING BENCHMARKS"))║")
    print(tableBorder("╠", "═", "╤", "╣"))
    print("║ \(lpad("Benchmark", 35))│\(rpad("Iters", 7))│\(rpad("Median", 12))│\(rpad("p95", 12))│\(rpad("Min", 12))│\(rpad("Stddev", 12))║")
    print(tableBorder("╠", "═", "╪", "╣"))

    var results: [Stats] = []

    // Pre-create colors (avoids NSColor.system* which needs appearance system)
    let colors = [
        NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
        NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1),
        NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1),
    ]

    let safeConfig = ConfettiConfig(
        birthRate: 40, lifetime: 4.5, velocity: 1500,
        velocityRange: 450, emissionRange: .pi * 0.4,
        gravity: -750, spin: 12.0, spinRange: 20.0,
        scale: 0.8, scaleRange: 0.2, scaleSpeed: -0.1,
        alphaSpeed: -0.15,
        colors: colors,
        shapes: [.rectangle, .triangle, .circle]
    )

    let fakeBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    // ── End-to-End: Full fire cycle ─────────────────────────────────────────
    // Measures what actually happens when you call confetti: create controller,
    // fire on screen, tear down.  Uses a real screen and window.
    guard let screen = NSScreen.main else {
        print("║ (skipping fire cycle — no screen available)")
        return results
    }

    let r1 = benchmark("Full fire cycle (1 screen)", batchSize: 5, runs: 10, warmup: 1) {
        let ctrl = ConfettiController(
            config: safeConfig, angles: .default,
            emissionDuration: 0.15, intensity: 1.0
        )
        ctrl.fire(on: [screen])
        ctrl.cleanup()
    }
    printRow(r1)
    results.append(r1)

    // ── Emitter Creation ────────────────────────────────────────────────────
    // Warm the texture cache (created once in real usage)
    blackHole(ConfettiEmitter.createEmitter(
        at: .zero, angle: .pi / 2, in: fakeBounds,
        config: safeConfig, intensity: 1.0
    ))

    // 9 cells (3 colors × 3 shapes) — default config
    let r2 = benchmark("Emitter creation (9 cells)", batchSize: 500, runs: 20) {
        blackHole(ConfettiEmitter.createEmitter(
            at: .zero, angle: .pi / 2, in: fakeBounds,
            config: safeConfig, intensity: 1.0
        ))
    }
    printRow(r2)
    results.append(r2)

    // 4 cells (2 colors × 2 shapes) — smaller config
    let smallConfig = ConfettiConfig(
        birthRate: 15, lifetime: 3.5, velocity: 800,
        velocityRange: 200, emissionRange: .pi * 0.4,
        gravity: -400, spin: 4.0, spinRange: 8.0,
        scale: 0.6, scaleRange: 0.1, scaleSpeed: -0.05,
        alphaSpeed: -0.2,
        colors: [colors[0], colors[1]],
        shapes: [.rectangle, .circle]
    )
    let r3 = benchmark("Emitter creation (4 cells)", batchSize: 500, runs: 20) {
        blackHole(ConfettiEmitter.createEmitter(
            at: .zero, angle: .pi / 2, in: fakeBounds,
            config: smallConfig, intensity: 1.0
        ))
    }
    printRow(r3)
    results.append(r3)

    // ── Object Creation ─────────────────────────────────────────────────────
    let r4 = benchmark("Controller init", batchSize: 10000) {
        blackHole(ConfettiController(
            config: safeConfig, angles: .default,
            emissionDuration: 0.15, intensity: 1.0
        ))
    }
    printRow(r4)
    results.append(r4)

    let r5 = benchmark("Config creation", batchSize: 50000) {
        blackHole(ConfettiConfig(
            birthRate: 30, lifetime: 4.5, velocity: 1250,
            velocityRange: 400, emissionRange: .pi * 0.4,
            gravity: -750, spin: 8.0, spinRange: 16.0,
            scale: 0.8, scaleRange: 0.05, scaleSpeed: -0.1,
            alphaSpeed: -0.15,
            colors: colors,
            shapes: [.rectangle, .circle]
        ))
    }
    printRow(r5)
    results.append(r5)

    // ── Pure Computation ────────────────────────────────────────────────────
    let r6 = benchmark("Particle count estimate", batchSize: 100000) {
        blackHole(ConfettiEmitter.estimatedParticleCount(
            config: safeConfig, emissionDuration: 0.15, emitterCount: 2
        ))
    }
    printRow(r6)
    results.append(r6)

    let r7 = benchmark("Cell count", batchSize: 100000) {
        blackHole(ConfettiEmitter.cellCount(for: safeConfig))
    }
    printRow(r7)
    results.append(r7)

    print(tableBorder("╚", "═", "╧", "╝"))
    print("")

    // ── Preset Comparison ───────────────────────────────────────────────────
    print(fullBorder("╔", "═", "╗"))
    print("║\(centered("PRESET COMPARISON"))║")
    print("║\(centered(""))║")
    print("║ \(lpad("Preset", 15))│ \(rpad("Cells", 6)) │ \(rpad("Emitters", 8)) │ \(rpad("Particles", 9)) │ \(rpad("Lifetime", 8)) │ \(lpad("Style", 15)) ║")
    print("║\(String(repeating: "─", count: innerWidth))║")

    let presetInfo: [(String, Int, Int, Int, Float, String)] = [
        ("default",   8, 3, 40,  4.5, "cannons"),
        ("subtle",    8, 3, 15,  3.5, "cannons"),
        ("intense",   8, 3, 80,  5.0, "cannons"),
        ("snow",      2, 1,  4,  7.0, "curtain"),
        ("fireworks", 8, 3, 100, 3.0, "cannons"),
    ]

    for (name, colorCount, shapeCount, birthRate, lifetime, style) in presetInfo {
        let cells = colorCount * shapeCount
        let emitterCount = style == "curtain" ? 1 : 2
        let particles = Int(Float(birthRate) * Float(cells) * Float(emitterCount) * 0.15)
        print("║ \(lpad(name, 15))│ \(rpad(String(cells), 6)) │ \(rpad(String(emitterCount), 8)) │ \(rpad(String(particles), 9)) │ \(rpad(String(format: "%.1fs", lifetime), 8)) │ \(lpad(style, 15)) ║")
    }

    print("║\(String(repeating: "─", count: innerWidth))║")
    print("║\(centered("Cells = colors x shapes.  Particles = birthRate x cells x emitters x 0.15s."))║")
    print(fullBorder("╚", "═", "╝"))
    print("")

    // ── Texture Memory ──────────────────────────────────────────────────────
    print(fullBorder("╔", "═", "╗"))
    print("║\(centered("TEXTURE MEMORY"))║")
    print(fullBorder("╠", "═", "╣"))

    let textures: [(String, Int, Int)] = [
        ("rectangle", 14, 7),
        ("triangle",  10, 10),
        ("circle",     8, 8),
    ]
    var totalBytes = 0
    for (name, w, h) in textures {
        let bytes = w * h * 4
        totalBytes += bytes
        let line = "  \(lpad(name, 12))  \(rpad(String(w), 2))x\(lpad(String(h), 2)) RGBA = \(rpad(String(bytes), 4)) bytes"
        print("║\(lpad(line, innerWidth))║")
    }
    let totalLine = "  Total cached: \(totalBytes) bytes (created once, reused across all emitters)"
    print("║\(lpad(totalLine, innerWidth))║")
    print(fullBorder("╚", "═", "╝"))
    print("")

    // ── Summary ─────────────────────────────────────────────────────────────
    let totalIters = results.reduce(0) { $0 + $1.totalIterations }
    let totalNs = results.reduce(0.0) { $0 + $1.meanNs * Double($1.totalIterations) }
    print(String(format: "Total: %d iterations in %.1f ms", totalIters, totalNs / 1_000_000))
    print("")

    return results
}

// MARK: - Frame Counter

/// Counts display refresh callbacks to measure rendering FPS
@available(macOS 14.0, *)
class FrameCounter: NSObject {
    private var timestamps: [Double] = []
    private var displayLink: CADisplayLink?

    func start(screen: NSScreen) {
        timestamps.reserveCapacity(500)
        let link = screen.displayLink(target: self, selector: #selector(onFrame(_:)))
        link.add(to: RunLoop.main, forMode: .common)
        displayLink = link
    }

    @objc private func onFrame(_ link: CADisplayLink) {
        timestamps.append(link.timestamp)
    }

    struct FrameStats {
        let totalFrames: Int
        let duration: Double
        let avgFps: Double
        let minFps: Double
        let p1Fps: Double
        let droppedFrames: Int
    }

    func stop() -> FrameStats {
        displayLink?.invalidate()
        displayLink = nil

        guard timestamps.count >= 2 else {
            return FrameStats(totalFrames: 0, duration: 0, avgFps: 0, minFps: 0, p1Fps: 0, droppedFrames: 0)
        }

        let duration = timestamps.last! - timestamps.first!
        let avgFps = Double(timestamps.count - 1) / duration

        var intervals = [Double]()
        intervals.reserveCapacity(timestamps.count - 1)
        for i in 1..<timestamps.count {
            intervals.append(timestamps[i] - timestamps[i - 1])
        }

        let sortedIntervals = intervals.sorted()
        let medianInterval = sortedIntervals[sortedIntervals.count / 2]

        // Worst 1% frame time → lowest sustained FPS
        let p99Interval = sortedIntervals[min(Int(Double(sortedIntervals.count) * 0.99), sortedIntervals.count - 1)]
        let p1Fps = 1.0 / p99Interval

        let worstInterval = sortedIntervals.last ?? medianInterval
        let minFps = 1.0 / worstInterval

        // Dropped = interval > 1.5x median (missed vsync)
        let dropped = intervals.filter { $0 > medianInterval * 1.5 }.count

        return FrameStats(
            totalFrames: timestamps.count,
            duration: duration,
            avgFps: avgFps,
            minFps: minFps,
            p1Fps: p1Fps,
            droppedFrames: dropped
        )
    }
}

// MARK: - Main

// AppKit types (NSColor, ConfettiController/NSWindow) require NSApplication
// to be initialised.  Without it, even NSColor(srgbRed:...) segfaults.
// We mirror the confetti CLI pattern: run benchmarks inside the app lifecycle.

class BenchmarkDelegate: NSObject, NSApplicationDelegate {
    private var controller: ConfettiController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Phase 1: Run timing benchmarks (synchronous)
        let _ = runBenchmarks()

        // Phase 2: Visual integration test — fire real confetti,
        // measure fire() latency and track FPS via CADisplayLink.
        let colors = [
            NSColor(srgbRed: 0.95, green: 0.2, blue: 0.2, alpha: 1),
            NSColor(srgbRed: 0.2, green: 0.5, blue: 0.95, alpha: 1),
            NSColor(srgbRed: 0.95, green: 0.85, blue: 0.1, alpha: 1),
            NSColor(srgbRed: 0.2, green: 0.8, blue: 0.3, alpha: 1),
            NSColor(srgbRed: 0.95, green: 0.5, blue: 0.1, alpha: 1),
            NSColor(srgbRed: 0.6, green: 0.3, blue: 0.9, alpha: 1),
            NSColor(srgbRed: 0.95, green: 0.4, blue: 0.6, alpha: 1),
            NSColor(srgbRed: 0.0, green: 0.8, blue: 0.85, alpha: 1),
        ]
        let config = ConfettiConfig(
            birthRate: 40, lifetime: 4.5, velocity: 1500,
            velocityRange: 450, emissionRange: .pi * 0.4,
            gravity: -750, spin: 12.0, spinRange: 20.0,
            scale: 0.8, scaleRange: 0.2, scaleSpeed: -0.1,
            alphaSpeed: -0.15,
            colors: colors,
            shapes: [.rectangle, .triangle, .circle]
        )

        let ctrl = ConfettiController(
            config: config, angles: .default,
            emissionDuration: 0.15, intensity: 1.0
        )

        if #available(macOS 14.0, *) {
            runVisualBenchmark(controller: ctrl, config: config)
        } else {
            runVisualBenchmarkLegacy(controller: ctrl, config: config)
        }
    }

    @available(macOS 14.0, *)
    private func runVisualBenchmark(controller ctrl: ConfettiController, config: ConfettiConfig) {
        let totalRuns = 5
        let animDuration = 3.0
        let cooldownDuration = 0.5  // Gap between runs for window server to settle

        print(fullBorder("╔", "═", "╗"))
        print("║\(centered("VISUAL BENCHMARK (\(totalRuns) runs)"))║")
        print(fullBorder("╠", "═", "╣"))

        var allFireNs: [Double] = []
        var allAvgFps: [Double] = []
        var allMinFps: [Double] = []
        var allP1Fps: [Double] = []
        var allDropped: [Int] = []
        var allFrames: [Int] = []

        func runIteration(_ index: Int) {
            guard index < totalRuns else {
                // All runs complete — print aggregated results
                printAggregatedResults(
                    fireNs: allFireNs, avgFps: allAvgFps, minFps: allMinFps,
                    p1Fps: allP1Fps, dropped: allDropped, frames: allFrames
                )
                return
            }

            let run = index + 1
            print("║\(lpad("  Run \(run)/\(totalRuns)...", innerWidth))║")

            // Create a fresh controller for each run
            let iterCtrl = ConfettiController(
                config: config, angles: .default,
                emissionDuration: 0.15, intensity: 1.0
            )

            let frameCounter = FrameCounter()

            // Measure fire() latency
            let t0 = now()
            iterCtrl.fire()
            let t1 = now()
            let fireNs = Double(t1 &- t0)
            allFireNs.append(fireNs)

            self.controller = iterCtrl
            frameCounter.start(screen: NSScreen.main ?? NSScreen.screens[0])

            DispatchQueue.main.asyncAfter(deadline: .now() + animDuration) { [self] in
                let stats = frameCounter.stop()
                controller?.cleanup()
                controller = nil

                allAvgFps.append(stats.avgFps)
                allMinFps.append(stats.minFps)
                allP1Fps.append(stats.p1Fps)
                allDropped.append(stats.droppedFrames)
                allFrames.append(stats.totalFrames)

                print("║\(lpad("    fire(): \(fmt(fireNs))  avg: \(String(format: "%.1f", stats.avgFps)) fps  min: \(String(format: "%.1f", stats.minFps)) fps  dropped: \(stats.droppedFrames)", innerWidth))║")

                // Cooldown before next iteration
                DispatchQueue.main.asyncAfter(deadline: .now() + cooldownDuration) {
                    runIteration(index + 1)
                }
            }
        }

        runIteration(0)
    }

    @available(macOS 14.0, *)
    private func printAggregatedResults(
        fireNs: [Double], avgFps: [Double], minFps: [Double],
        p1Fps: [Double], dropped: [Int], frames: [Int]
    ) {
        print("║\(String(repeating: "─", count: innerWidth))║")

        let sortedFire = fireNs.sorted()
        let sortedAvg = avgFps.sorted()
        let sortedMin = minFps.sorted()
        let sortedP1 = p1Fps.sorted()

        let medianFire = sortedFire[sortedFire.count / 2]
        let medianAvg = sortedAvg[sortedAvg.count / 2]
        let worstMin = sortedMin.first ?? 0
        let medianP1 = sortedP1[sortedP1.count / 2]
        let totalDropped = dropped.reduce(0, +)
        let totalFrames = frames.reduce(0, +)

        // Stddev of avg FPS
        let meanAvg = sortedAvg.reduce(0, +) / Double(sortedAvg.count)
        let varianceAvg = sortedAvg.reduce(0) { $0 + ($1 - meanAvg) * ($1 - meanAvg) } / Double(sortedAvg.count)
        let stddevAvg = varianceAvg.squareRoot()

        print("║\(centered("AGGREGATED (\(fireNs.count) runs)"))║")
        print("║\(String(repeating: "─", count: innerWidth))║")
        print("║\(lpad("  fire() latency (median): \(fmt(medianFire))", innerWidth))║")
        print("║\(lpad("  fire() latency (range):  \(fmt(sortedFire.first ?? 0)) – \(fmt(sortedFire.last ?? 0))", innerWidth))║")
        print("║\(lpad("  Average FPS (median):    \(String(format: "%.1f", medianAvg)) ± \(String(format: "%.1f", stddevAvg))", innerWidth))║")
        print("║\(lpad("  Average FPS (range):     \(String(format: "%.1f", sortedAvg.first ?? 0)) – \(String(format: "%.1f", sortedAvg.last ?? 0))", innerWidth))║")
        print("║\(lpad("  1% low FPS (median):     \(String(format: "%.1f", medianP1))", innerWidth))║")
        print("║\(lpad("  Min FPS (worst across runs): \(String(format: "%.1f", worstMin))", innerWidth))║")
        print("║\(lpad("  Total dropped frames:    \(totalDropped) / \(totalFrames)", innerWidth))║")
        print(fullBorder("╚", "═", "╝"))
        print("")
        print("Benchmarks complete!")
        NSApp.terminate(nil)
    }

    private func runVisualBenchmarkLegacy(controller ctrl: ConfettiController, config: ConfettiConfig) {
        let totalRuns = 5
        let animDuration = 3.0
        let cooldownDuration = 0.5

        print(fullBorder("╔", "═", "╗"))
        print("║\(centered("VISUAL BENCHMARK (\(totalRuns) runs, no FPS — requires macOS 14+)"))║")
        print(fullBorder("╠", "═", "╣"))

        var allFireNs: [Double] = []

        func runIteration(_ index: Int) {
            guard index < totalRuns else {
                let sorted = allFireNs.sorted()
                let median = sorted[sorted.count / 2]
                print("║\(String(repeating: "─", count: innerWidth))║")
                print("║\(lpad("  fire() latency (median): \(fmt(median))", innerWidth))║")
                print("║\(lpad("  fire() latency (range):  \(fmt(sorted.first ?? 0)) – \(fmt(sorted.last ?? 0))", innerWidth))║")
                print(fullBorder("╚", "═", "╝"))
                print("")
                print("Benchmarks complete!")
                NSApp.terminate(nil)
                return
            }

            let run = index + 1
            print("║\(lpad("  Run \(run)/\(totalRuns)...", innerWidth))║")

            let iterCtrl = ConfettiController(
                config: config, angles: .default,
                emissionDuration: 0.15, intensity: 1.0
            )

            let t0 = now()
            iterCtrl.fire()
            let t1 = now()
            let fireNs = Double(t1 &- t0)
            allFireNs.append(fireNs)

            controller = iterCtrl
            print("║\(lpad("    fire(): \(fmt(fireNs))", innerWidth))║")

            DispatchQueue.main.asyncAfter(deadline: .now() + animDuration) { [self] in
                controller?.cleanup()
                controller = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + cooldownDuration) {
                    runIteration(index + 1)
                }
            }
        }

        runIteration(0)
    }
}

let app = NSApplication.shared
let delegate = BenchmarkDelegate()
app.delegate = delegate
app.run()
