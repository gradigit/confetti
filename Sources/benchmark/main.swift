import AppKit
import ConfettiKit

// MARK: - Benchmark Utilities

struct BenchmarkResult {
    let name: String
    let iterations: Int
    let totalTime: TimeInterval
    let averageTime: TimeInterval
    let minTime: TimeInterval
    let maxTime: TimeInterval

    var description: String {
        let avgUs = averageTime * 1_000_000
        let minUs = minTime * 1_000_000
        let maxUs = maxTime * 1_000_000
        let totalMs = totalTime * 1000
        return String(format: "%-40s │ %7d │ %8.2f ms │ %8.2f μs │ %8.2f μs │ %8.2f μs",
                      name, iterations, totalMs, avgUs, minUs, maxUs)
    }
}

func benchmark(_ name: String, iterations: Int = 1000, warmup: Int = 100, _ block: () -> Void) -> BenchmarkResult {
    // Warmup
    for _ in 0..<warmup {
        block()
    }

    var times: [TimeInterval] = []
    times.reserveCapacity(iterations)

    for _ in 0..<iterations {
        let start = CFAbsoluteTimeGetCurrent()
        block()
        let end = CFAbsoluteTimeGetCurrent()
        times.append(end - start)
    }

    let totalTime = times.reduce(0, +)
    let averageTime = totalTime / Double(iterations)
    let minTime = times.min() ?? 0
    let maxTime = times.max() ?? 0

    return BenchmarkResult(
        name: name,
        iterations: iterations,
        totalTime: totalTime,
        averageTime: averageTime,
        minTime: minTime,
        maxTime: maxTime
    )
}

// MARK: - Table Drawing

private let colWidths = [42, 9, 13, 13, 13, 13]

private func tableBorder(left: String, fill: String, sep: String, right: String) -> String {
    left + colWidths.map { String(repeating: fill, count: $0) }.joined(separator: sep) + right
}

private func fullBorder(left: String, fill: String, right: String) -> String {
    let innerWidth = colWidths.reduce(0, +) + colWidths.count - 1
    return left + String(repeating: fill, count: innerWidth) + right
}

private func centered(_ text: String) -> String {
    let innerWidth = colWidths.reduce(0, +) + colWidths.count - 1
    let pad = innerWidth - text.count
    let leftPad = pad / 2
    let rightPad = pad - leftPad
    return String(repeating: " ", count: leftPad) + text + String(repeating: " ", count: rightPad)
}

// MARK: - Benchmarks

func runBenchmarks() {
    print("")
    print(fullBorder(left: "╔", fill: "═", right: "╗"))
    print("║" + centered("CONFETTI PERFORMANCE BENCHMARKS") + "║")
    print(tableBorder(left: "╠", fill: "═", sep: "╤", right: "╣"))
    print("║ Benchmark                                │  Iters  │    Total    │     Avg     │     Min     │     Max     ║")
    print(tableBorder(left: "╠", fill: "═", sep: "╪", right: "╣"))

    var results: [BenchmarkResult] = []

    // Benchmark 1: Config default access
    let configResult = benchmark("ConfettiConfig.default", iterations: 100000) {
        _ = ConfettiConfig.default
    }
    results.append(configResult)
    print("║ \(configResult.description) ║")

    // Benchmark 2: Custom config creation
    let customConfigResult = benchmark("ConfettiConfig custom init", iterations: 50000) {
        _ = ConfettiConfig(
            birthRate: 30,
            lifetime: 4.5,
            velocity: 1250,
            velocityRange: 400,
            emissionRange: .pi * 0.4,
            gravity: -750,
            spin: 8.0,
            spinRange: 16.0,
            scale: 0.8,
            scaleRange: 0.05,
            scaleSpeed: -0.1,
            alphaSpeed: -0.15,
            colors: [.systemRed, .systemGreen, .systemBlue, .systemYellow,
                     .systemOrange, .systemPurple, .systemPink, .cyan],
            shapes: [.rectangle, .triangle, .circle]
        )
    }
    results.append(customConfigResult)
    print("║ \(customConfigResult.description) ║")

    // Benchmark 3: Cell count calculation
    let cellCountResult = benchmark("ConfettiEmitter.cellCount", iterations: 500000) {
        _ = ConfettiEmitter.cellCount(for: .default)
    }
    results.append(cellCountResult)
    print("║ \(cellCountResult.description) ║")

    // Benchmark 4: Particle count estimation
    let estimateResult = benchmark("estimatedParticleCount", iterations: 500000) {
        _ = ConfettiEmitter.estimatedParticleCount(
            config: .default,
            emissionDuration: 0.15,
            emitterCount: 2
        )
    }
    results.append(estimateResult)
    print("║ \(estimateResult.description) ║")

    // Benchmark 5: Controller creation
    let controllerResult = benchmark("ConfettiController init", iterations: 10000) {
        _ = ConfettiController(
            config: .default,
            angles: .default,
            emissionDuration: 0.15,
            intensity: 1.0
        )
    }
    results.append(controllerResult)
    print("║ \(controllerResult.description) ║")

    // Benchmark 6: Angles default access
    let anglesResult = benchmark("CannonAngles.default", iterations: 100000) {
        _ = ConfettiController.CannonAngles.default
    }
    results.append(anglesResult)
    print("║ \(anglesResult.description) ║")

    // Benchmark 7: Custom angles creation
    let customAnglesResult = benchmark("CannonAngles custom init", iterations: 100000) {
        _ = ConfettiController.CannonAngles(left: .pi * 0.47, right: .pi * 0.53)
    }
    results.append(customAnglesResult)
    print("║ \(customAnglesResult.description) ║")

    // Benchmark 8: Shape iteration
    let shapesResult = benchmark("ConfettiShape.allCases iteration", iterations: 100000) {
        for shape in ConfettiShape.allCases {
            _ = shape
        }
    }
    results.append(shapesResult)
    print("║ \(shapesResult.description) ║")

    print(tableBorder(left: "╚", fill: "═", sep: "╧", right: "╝"))

    // Summary
    print("")
    print("══════════════════════════════════════════════════════════════════════════════════════════════════")
    print("SUMMARY")
    print("══════════════════════════════════════════════════════════════════════════════════════════════════")

    let totalBenchmarkTime = results.reduce(0) { $0 + $1.totalTime }
    print(String(format: "Total benchmark time:        %.2f ms", totalBenchmarkTime * 1000))
    print(String(format: "Total iterations:            %d", results.reduce(0) { $0 + $1.iterations }))
    print("")

    // Particle statistics
    print("══════════════════════════════════════════════════════════════════════════════════════════════════")
    print("PARTICLE STATISTICS (default config)")
    print("══════════════════════════════════════════════════════════════════════════════════════════════════")
    let config = ConfettiConfig.default
    let cellCount = ConfettiEmitter.cellCount(for: config)
    let particleCount = ConfettiEmitter.estimatedParticleCount(
        config: config,
        emissionDuration: 0.15,
        emitterCount: 2
    )

    print("• Colors:                    \(config.colors.count)")
    print("• Shapes:                    \(config.shapes.count)")
    print("• Cell types per emitter:    \(cellCount)")
    print("• Total cell types:          \(cellCount * 2) (2 emitters)")
    print("• Birth rate per cell:       \(config.birthRate)/sec")
    print("• Emission duration:         0.15 sec")
    print("• Estimated particles:       ~\(particleCount)")
    print("• Particle lifetime:         \(config.lifetime) sec")
    print("• Velocity:                  \(config.velocity) (±\(config.velocityRange))")
    print("• Gravity:                   \(config.gravity)")
    print("• Scale:                     \(config.scale) (±\(config.scaleRange))")
    print("")

    // Memory estimate
    print("══════════════════════════════════════════════════════════════════════════════════════════════════")
    print("MEMORY ESTIMATE")
    print("══════════════════════════════════════════════════════════════════════════════════════════════════")
    let rectBytes = 14 * 7 * 4   // 14x7 RGBA
    let triBytes = 10 * 10 * 4   // 10x10 RGBA
    let circBytes = 8 * 8 * 4    // 8x8 RGBA
    let textureMemory = rectBytes + triBytes + circBytes
    print("• Rectangle texture:         \(rectBytes) bytes (14×7 RGBA)")
    print("• Triangle texture:          \(triBytes) bytes (10×10 RGBA)")
    print("• Circle texture:            \(circBytes) bytes (8×8 RGBA)")
    print("• Total cached textures:     \(textureMemory) bytes")
    print("• Per-particle overhead:     ~64 bytes (estimated)")
    print("• Peak memory (~200 particles): ~\(200 * 64 / 1024) KB")
    print("")

    // Performance notes
    print("══════════════════════════════════════════════════════════════════════════════════════════════════")
    print("PERFORMANCE NOTES")
    print("══════════════════════════════════════════════════════════════════════════════════════════════════")
    print("• Textures are cached at first use (one-time cost)")
    print("• CAEmitterLayer uses hardware acceleration (GPU)")
    print("• renderMode = .oldestFirst for optimal batching")
    print("• drawsAsynchronously = true for background rendering")
    print("• Typical animation: 60fps, <10% CPU, <5MB RAM")
    print("")
    print("NOTE: CAEmitterLayer benchmarks require a display context.")
    print("      Run 'confetti' directly to test full rendering performance.")
    print("")
}

// MARK: - Main

print(fullBorder(left: "╔", fill: "═", right: "╗"))
print("║" + centered("CONFETTI BENCHMARK SUITE v1.0") + "║")
print(fullBorder(left: "╚", fill: "═", right: "╝"))
print("")
print("System: macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
print("Date:   \(Date())")
print("CPU:    \(ProcessInfo.processInfo.processorCount) cores")
print("Memory: \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB")

runBenchmarks()

print("Benchmarks complete!")
