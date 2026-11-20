import AppKit
import Metal
import QuartzCore

// MARK: - Shared Metal State

/// Device, queue and pipeline, created once per process.
final class MetalContext {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let compileMs: Double

    init() {
        let t0 = CACurrentMediaTime()
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            fatalError("Metal unavailable")
        }
        let library = try! device.makeLibrary(source: shaderSource, options: nil)
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "confetti_vertex")
        desc.fragmentFunction = library.makeFunction(name: "confetti_fragment")
        let color = desc.colorAttachments[0]!
        color.pixelFormat = .bgra8Unorm
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        self.pipeline = try! device.makeRenderPipelineState(descriptor: desc)
        self.device = device
        self.queue = queue
        self.compileMs = (CACurrentMediaTime() - t0) * 1000
    }
}

// MARK: - View

final class MetalLayerView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func makeBackingLayer() -> CALayer { CAMetalLayer() }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
}

// MARK: - Overlay

/// One screen's confetti: window + CAMetalLayer + sim + display link.
/// Runs only while particles are alive, then stops its display link and calls `onFinished`.
final class MetalOverlay: NSObject {

    let window: OverlayWindow
    let sim: ConfettiSim
    var onFinished: (() -> Void)?
    var cannons: (left: Bool, right: Bool) = (true, true)

    private let ctx: MetalContext
    private let view: MetalLayerView
    private let buffers: [MTLBuffer]
    private let inflight = DispatchSemaphore(value: 3)
    private var frameIndex = 0
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var finished = false
    private let viewport: SIMD2<Float>
    private let stats: Stats

    init(screen: NSScreen, ctx: MetalContext, params: ConfettiSim.Params, stats: Stats, pixelScale: Double? = nil) {
        self.ctx = ctx
        self.stats = stats
        window = OverlayWindow(screen: screen)
        let size = screen.frame.size
        view = MetalLayerView(frame: CGRect(origin: .zero, size: size))
        viewport = SIMD2(Float(size.width), Float(size.height))

        let capacity = params.perCannon * 2
        sim = ConfettiSim(params: params, capacity: capacity, width: viewport.x, height: viewport.y)
        buffers = (0..<3).map { _ in
            ctx.device.makeBuffer(length: capacity * MemoryLayout<Instance>.stride, options: .storageModeShared)!
        }
        super.init()

        let layer = view.metalLayer
        layer.device = ctx.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = false
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.maximumDrawableCount = 3
        let px = pixelScale.map { CGFloat($0) } ?? screen.backingScaleFactor
        layer.contentsScale = px
        layer.drawableSize = CGSize(width: size.width * px, height: size.height * px)
        window.contentView = view
    }

    func fire() {
        window.orderFrontRegardless()
        if cannons.left { sim.fireCannon(origin: SIMD2(0, 0), towardRight: true) }
        if cannons.right { sim.fireCannon(origin: SIMD2(viewport.x, 0), towardRight: false) }
        stats.spawned += sim.count

        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let t0 = CACurrentMediaTime()
        let dt: Float
        if lastTimestamp == 0 {
            dt = 1.0 / 60.0
        } else {
            let interval = link.timestamp - lastTimestamp
            stats.recordInterval(interval, expected: link.targetTimestamp - link.timestamp)
            dt = Float(min(interval, 1.0 / 30.0))
        }
        lastTimestamp = link.timestamp

        inflight.wait()
        let buffer = buffers[frameIndex]
        frameIndex = (frameIndex + 1) % buffers.count
        let n = sim.step(dt: dt, into: buffer.contents().bindMemory(to: Instance.self, capacity: sim.capacity))
        let tSim = CACurrentMediaTime()

        // When nothing is alive we still draw one empty (cleared) frame, then stop.
        let done = sim.aliveCount == 0

        guard let drawable = view.metalLayer.nextDrawable() else {
            inflight.signal()
            return
        }
        let tDrawable = CACurrentMediaTime()

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store

        let cmd = ctx.queue.makeCommandBuffer()!
        let enc = cmd.makeRenderCommandEncoder(descriptor: pass)!
        if n > 0 {
            var vp = viewport
            enc.setRenderPipelineState(ctx.pipeline)
            enc.setVertexBuffer(buffer, offset: 0, index: 0)
            enc.setVertexBytes(&vp, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: n)
        }
        enc.endEncoding()

        let stats = self.stats
        if stats.frames == 0 { stats.firstCommit = Date(); stats.mark("3_first_frame") }
        // presentedTime is 0 for drawables the compositor dropped, so watch the first few
        // frames and keep the earliest one that actually reached the screen.
        if stats.frames < 10 {
            drawable.addPresentedHandler { d in
                guard d.presentedTime > 0 else { return }
                let ago = CACurrentMediaTime() - d.presentedTime
                DispatchQueue.main.async {
                    let t = Date().addingTimeInterval(-ago)
                    if stats.firstPresent == nil || t < stats.firstPresent! { stats.firstPresent = t }
                }
            }
        }
        cmd.present(drawable)
        let sem = inflight
        cmd.addCompletedHandler { cb in
            let gpu = cb.gpuEndTime - cb.gpuStartTime
            DispatchQueue.main.async { stats.gpuFrame.append(gpu) }
            sem.signal()
        }
        cmd.commit()

        let t1 = CACurrentMediaTime()
        stats.frames += 1
        stats.cpuFrame.append(t1 - t0 - (tDrawable - tSim))   // exclude time blocked on nextDrawable
        stats.drawableWait.append(tDrawable - tSim)

        if done { finish() }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        link?.invalidate()
        link = nil
        onFinished?()
    }

    func close() {
        link?.invalidate()
        window.orderOut(nil)
    }
}

// MARK: - Window

/// Same configuration as ConfettiKit's internal ConfettiWindow.
final class OverlayWindow: NSWindow {
    convenience init(screen: NSScreen) {
        self.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let v = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        v.wantsLayer = true
        v.layer?.backgroundColor = .clear
        contentView = v
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
