import Foundation

/// Benchmark measurements for one process run. Main thread only.
final class Stats {
    let processStart: Date = Stats.processStartTime()
    var fireStart: Date?
    var firstCommit: Date?
    var firstPresent: Date?
    var end: Date?
    var shaderCompileMs: Double?
    var spawned = 0
    var frames = 0
    var hitches = 0
    var cpuFrame: [Double] = []
    var drawableWait: [Double] = []
    /// Process CPU (ms, all threads) at named checkpoints
    var cpuMarks: [String: Double] = [:]
    func mark(_ name: String) { cpuMarks[name] = Stats.processCPUms() }

    static func processCPUms() -> Double {
        var ru = rusage()
        getrusage(RUSAGE_SELF, &ru)
        return Double(ru.ru_utime.tv_sec + ru.ru_stime.tv_sec) * 1000
            + Double(ru.ru_utime.tv_usec + ru.ru_stime.tv_usec) / 1000
    }
    var gpuFrame: [Double] = []

    func recordInterval(_ interval: Double, expected: Double) {
        if expected > 0 && interval > expected * 1.5 { hitches += 1 }
    }

    func json(engine: String, screens: Int) -> String {
        func ms(_ a: Date?, _ b: Date?) -> Any {
            guard let a, let b else { return NSNull() }
            return round(b.timeIntervalSince(a) * 10000) / 10
        }
        func us(_ xs: [Double], _ f: ([Double]) -> Double) -> Any {
            xs.isEmpty ? NSNull() : round(f(xs) * 1e6 * 10) / 10
        }
        let avg: ([Double]) -> Double = { $0.reduce(0, +) / Double($0.count) }
        let p99: ([Double]) -> Double = { let s = $0.sorted(); return s[min(s.count - 1, Int(Double(s.count) * 0.99))] }
        let mx: ([Double]) -> Double = { $0.max()! }

        var ru = rusage()
        getrusage(RUSAGE_SELF, &ru)
        let cpu = Double(ru.ru_utime.tv_sec + ru.ru_stime.tv_sec) * 1000
            + Double(ru.ru_utime.tv_usec + ru.ru_stime.tv_usec) / 1000

        let dict: [String: Any] = [
            "engine": engine,
            "screens": screens,
            "particles": spawned,
            "launch_to_fire_ms": ms(processStart, fireStart),
            "launch_to_first_commit_ms": ms(processStart, firstCommit),
            "launch_to_first_present_ms": ms(processStart, firstPresent),
            "shader_compile_ms": shaderCompileMs.map { round($0 * 10) / 10 } ?? NSNull(),
            "overlay_ms": ms(fireStart, end),
            "frames": frames,
            "hitches": hitches,
            "cpu_frame_avg_us": us(cpuFrame, avg),
            "cpu_frame_p99_us": us(cpuFrame, p99),
            "drawable_wait_avg_us": us(drawableWait, avg),
            "gpu_frame_avg_us": us(gpuFrame, avg),
            "gpu_frame_max_us": us(gpuFrame, mx),
            "process_cpu_ms": round(cpu * 10) / 10,
            "max_rss_mb": round(Double(ru.ru_maxrss) / 1_048_576 * 10) / 10,
            "cpu_marks_ms": cpuMarks.mapValues { round($0 * 10) / 10 },
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    private static func processStartTime() -> Date {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return Date() }
        let tv = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6)
    }
}
