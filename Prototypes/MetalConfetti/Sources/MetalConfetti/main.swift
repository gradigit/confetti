import AppKit
import ConfettiKit

// MARK: - Options

struct Options {
    var engine = "metal"        // metal | ca | layers | split
    var metalScale: Double?     // drawable pixels per point (default: screen backing scale)
    var bench = false
    var screenIndex: Int?
    var params = ConfettiSim.Params()

    static func parse() -> Options {
        var o = Options()
        var args = CommandLine.arguments.dropFirst().makeIterator()
        func num(_ flag: String) -> Float {
            guard let s = args.next(), let v = Float(s) else { fail("\(flag) needs a number") }
            return v
        }
        while let a = args.next() {
            switch a {
            case "--engine":
                guard let e = args.next(), ["metal", "ca", "layers", "baked", "split"].contains(e) else { fail("--engine metal|ca|layers|baked|split") }
                o.engine = e
            case "--bench": o.bench = true
            case "--metal-scale": o.metalScale = Double(num(a))
            case "--screen": o.screenIndex = Int(num(a))
            case "--count": o.params.perCannon = Int(num(a))
            case "--size": o.params.sizeScale = num(a)
            case "--gravity": o.params.gravity = num(a)
            case "--drag-min": o.params.dragMin = num(a)
            case "--drag-max": o.params.dragMax = num(a)
            case "--speed-min": o.params.speedMin = num(a)
            case "--speed-max": o.params.speedMax = num(a)
            case "--spread": o.params.spreadDeg = num(a)
            case "--burst-window": o.params.burstWindow = num(a)
            case "-h", "--help":
                print("""
                metal-confetti A/B prototype
                  --engine metal|ca|layers|baked|split   metal = Metal engine, ca = current ConfettiKit, layers = same sim drawn as CALayers, baked = same sim pre-computed into CA animations (no per-frame work), split = CA left cannon + layers right cannon
                  --bench                   print one JSON line of measurements at exit
                  --screen N                one screen only (default: all)
                  --count N                 particles per cannon (default 144, matches CA default)
                  --size X  --gravity X  --drag-min X  --drag-max X  --speed-min X  --speed-max X  --spread DEG  --burst-window S
                """)
                exit(0)
            default: fail("unknown option \(a)")
            }
        }
        return o
    }
}

func fail(_ msg: String) -> Never {
    fputs("Error: \(msg)\n", stderr)
    exit(1)
}

/// The default preset's palette, converted to sRGB bytes once (not during any scene setup).
func paletteBytes() -> [SIMD3<UInt8>] {
    ConfettiConfig.default.colors.map { color in
        let c = color.usingColorSpace(.sRGB) ?? color
        func b(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        return SIMD3(b(c.redComponent), b(c.greenComponent), b(c.blueComponent))
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let options = Options.parse()
    let stats = Stats()
    var controller: ConfettiController?
    var overlays: [MetalOverlay] = []
    var layerOverlays: [LayerOverlay] = []
    var bakedOverlays: [BakedOverlay] = []
    var exitTimer: DispatchSourceTimer?
    var caWindows: [OverlayWindow] = []
    var pending = 0
    var screenCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let screens: [NSScreen]
        if let i = options.screenIndex {
            guard i < NSScreen.screens.count else { fail("screen \(i) out of range") }
            screens = [NSScreen.screens[i]]
        } else {
            screens = NSScreen.screens
        }

        screenCount = screens.count
        stats.fireStart = Date()
        stats.mark("0_launch_done")
        switch options.engine {
        case "ca": runCA(screens)
        case "metal": runMetal(screens, cannons: (true, true))
        case "layers": runLayers(screens, cannons: (true, true))
        case "baked": runBaked(screens)
        default: runSplit(screens)
        }
    }

    // MARK: A — current ConfettiKit path, exactly as the `confetti` CLI runs it

    private func runCA(_ screens: [NSScreen]) {
        let config = ConfettiConfig.default
        let c = ConfettiController(config: config, emissionDuration: 0.15, intensity: 1.0, windowLevel: .statusBar)
        c.fire(on: screens)
        CATransaction.flush()
        stats.firstCommit = Date()
        stats.spawned = ConfettiEmitter.estimatedParticleCount(config: config, emissionDuration: 0.15) * screens.count
        controller = c
        pending += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(config.lifetime)) { [weak self] in
            c.cleanup()
            self?.done()
        }
    }

    // MARK: B — new Metal engine

    private func runMetal(_ screens: [NSScreen], cannons: (left: Bool, right: Bool)) {
        let ctx = MetalContext()
        stats.mark("1_metal_context")
        stats.shaderCompileMs = ctx.compileMs
        var params = options.params
        params.colors = paletteBytes()
        for screen in screens {
            let o = MetalOverlay(screen: screen, ctx: ctx, params: params, stats: stats, pixelScale: options.metalScale)
            o.cannons = cannons
            o.onFinished = { [weak self] in self?.done() }
            overlays.append(o)
            pending += 1
        }
        stats.mark("2_overlays_created")
        for o in overlays { o.fire() }
    }

    // MARK: C — same sim, one CALayer per particle

    private func runLayers(_ screens: [NSScreen], cannons: (left: Bool, right: Bool)) {
        var params = options.params
        params.colors = paletteBytes()
        for screen in screens {
            let o = LayerOverlay(screen: screen, params: params, stats: stats)
            o.cannons = cannons
            o.onFinished = { [weak self] in self?.done() }
            layerOverlays.append(o)
            pending += 1
        }
        stats.mark("2_overlays_created")
        for o in layerOverlays { o.fire() }
    }

    // MARK: D — same sim, baked into Core Animation animations, committed once

    private func runBaked(_ screens: [NSScreen]) {
        var params = options.params
        params.colors = paletteBytes()
        bakedOverlays = screens.map { BakedOverlay(screen: $0, params: params, stats: stats) }
        stats.mark("2_overlays_created")
        bakedOverlays.forEach { $0.fire() }
        stats.firstCommit = Date()
        stats.mark("3_committed")
        pending += 1
        let longest = bakedOverlays.map(\.duration).max() ?? 0
        // asyncAfter on an idle app gets coalesced ~5% late (~220 ms on a 4.6 s delay), keeping
        // the overlay up for nothing. A timer source with explicit 1 ms leeway fires on time.
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + longest, leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.done() }
        t.resume()
        exitTimer = t
    }

    // MARK: Split — CA fires the left cannon, the layers engine fires the right, same screen

    private func runSplit(_ screens: [NSScreen]) {
        let config = ConfettiConfig.default
        for screen in screens {
            let w = OverlayWindow(screen: screen)
            w.orderFrontRegardless()
            caWindows.append(w)
            guard let layer = w.contentView?.layer else { continue }
            layer.display()
            CATransaction.flush()
            let emitter = ConfettiEmitter.createEmitter(
                at: .zero, angle: ConfettiController.CannonAngles.default.left,
                in: layer.bounds, config: config)
            emitter.beginTime = CACurrentMediaTime()
            layer.addSublayer(emitter)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { emitter.birthRate = 0 }
        }
        pending += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(config.lifetime)) { [weak self] in
            self?.caWindows.forEach { $0.orderOut(nil) }
            self?.done()
        }
        runLayers(screens, cannons: (false, true))
    }

    // MARK: Exit

    private func done() {
        pending -= 1
        guard pending == 0 else { return }
        stats.end = Date()
        stats.mark("4_end")
        overlays.forEach { $0.close() }
        layerOverlays.forEach { $0.close() }
        bakedOverlays.forEach { $0.close() }
        // Let late GPU-completion and presented handlers land on main before reporting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            if options.bench {
                let name = options.engine == "metal" && options.metalScale != nil ? "metal@\(options.metalScale!)x" : options.engine
                print(stats.json(engine: name, screens: screenCount))
            }
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
