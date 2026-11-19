import AppKit
import Metal
import QuartzCore
import ParalluxKit
import SwiftUI

/// The flow diagram's dots, drawn by the GPU (perf-flow-animation).
///
/// They are the only part of the diagram that changes on every frame. Drawn
/// in a SwiftUI Canvas, every frame rasterised and committed the whole layer:
/// 10–12.6% of a core at 60 fps on screen (measured 2026-11-19, 804×330 pt,
/// about 900 dots). As point sprites the same picture is one small buffer and
/// one draw call: about 3.2%. Bands, nodes and labels stay in SwiftUI; they
/// change once a second.
///
/// The view exists only while there is something to animate (FlowDiagram
/// removes it without traffic, in a hidden window and under reduced motion),
/// so its display link stops with it.
struct FlowParticleLayer: NSViewRepresentable {
    struct Input {
        var target: FlowMotion.Target
        var metrics: FlowDiagram.Metrics
        /// One colour per link, in the links' order.
        var colors: [Color]
        var easing: Bool
        /// Points.
        var dotSide: CGFloat
        /// Dark appearance: dots add light instead of covering (the design's `lighter`).
        var additive: Bool
    }

    let motion: FlowMotion
    let input: Input

    func makeCoordinator() -> Renderer { Renderer(motion: motion) }

    func makeNSView(context: Context) -> FlowParticleView {
        let view = FlowParticleView()
        let renderer = context.coordinator
        view.onFrame = { [weak renderer] view in renderer?.draw(in: view) }
        return view
    }

    func updateNSView(_ view: FlowParticleView, context: Context) {
        context.coordinator.update(input, appearance: view.effectiveAppearance)
    }

    static func dismantleNSView(_ view: FlowParticleView, coordinator: Renderer) {
        view.stop()
    }

    /// Steps the particle model once per frame and hands the dots to the GPU.
    @MainActor
    final class Renderer {
        private let motion: FlowMotion
        private var input: Input?
        private var colors: [SIMD3<Float>] = []
        /// Why 3: a buffer handed to the GPU may still be read while the next
        /// frame is being written; three in rotation is Metal's usual answer
        /// (a drawable queue is at most three deep).
        private var buffers: [MTLBuffer] = []
        private var frame = 0

        init(motion: FlowMotion) { self.motion = motion }

        func update(_ input: Input, appearance: NSAppearance) {
            self.input = input
            // Resolved here, when the inputs change, not on every frame.
            appearance.performAsCurrentDrawingAppearance {
                colors = input.colors.map { color in
                    let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .gray
                    return SIMD3(Float(rgb.redComponent), Float(rgb.greenComponent), Float(rgb.blueComponent))
                }
            }
        }

        /// One frame onto the screen.
        func draw(in view: FlowParticleView) {
            // Asked first: taking a drawable and then not presenting it wastes one of the layer's three.
            guard isReady, let drawable = view.metalLayer.nextDrawable(),
                  let commands = render(to: drawable.texture, size: view.bounds.size, scale: view.metalLayer.contentsScale, at: Date()) else { return }
            commands.present(drawable)
            commands.commit()
        }

        private var isReady: Bool {
            guard let input, let pipeline = FlowParticlePipeline.shared else { return false }
            return (input.additive ? pipeline.additive : pipeline.over) != nil
        }

        /// Steps the particles to `date` and encodes them into `texture`
        /// (`size` in points). Returns the command buffer for the caller to
        /// present or wait on and commit; nil while there is nothing to draw
        /// with. Separate from `draw(in:)` so the picture can be produced, and
        /// checked, without a screen.
        func render(to texture: MTLTexture, size: CGSize, scale: CGFloat, at date: Date) -> MTLCommandBuffer? {
            guard let input, let pipeline = FlowParticlePipeline.shared,
                  let state = input.additive ? pipeline.additive : pipeline.over else { return nil }
            if buffers.isEmpty {
                buffers = (0..<3).compactMap { _ in
                    pipeline.device.makeBuffer(length: MemoryLayout<Dot>.stride * FlowParticles.limit, options: .storageModeShared)
                }
            }
            guard buffers.count == 3 else { return nil }
            frame = (frame + 1) % buffers.count
            let buffer = buffers[frame]

            let m = input.metrics
            let current = motion.particles(at: date, target: input.target, metrics: m, easing: input.easing)
            let exitCount = max(current.layout.right.count, 1)
            // Bands by (link, exit), so finding a particle's band is one lookup.
            var bands = [SankeyLayout.Band?](repeating: nil, count: max(current.layout.left.count, 1) * exitCount)
            for band in current.layout.bands { bands[band.from * exitCount + band.to] = band }
            let dots = buffer.contents().bindMemory(to: Dot.self, capacity: FlowParticles.limit)
            var count = 0
            for particle in current.particles.prefix(FlowParticles.limit) {
                let slot = particle.from * exitCount + particle.to
                guard particle.from < colors.count, particle.to < exitCount, slot < bands.count, let band = bands[slot] else { continue }
                let first = particle.progress < 1
                let t = first ? particle.progress : particle.progress - 1
                let x0 = first ? m.leftX + m.bar : m.centreX + m.bar, x1 = first ? m.centreX : m.rightX
                let x = x0 + (x1 - x0) * CGFloat(FlowParticles.run(t))
                let y = m.inset + CGFloat(FlowParticles.y(of: particle, in: band))
                // Fades in and out over the first and last eighth of a leg.
                let alpha = Float(min(1, particle.progress * 8, (2 - particle.progress) * 8) * 0.9)
                dots[count] = Dot(position: SIMD4(Float(x), Float(y), 0, 0), color: SIMD4(colors[particle.from], alpha))
                count += 1
            }

            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            // Transparent: the dots sit on top of the SwiftUI band layer.
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            guard let commands = pipeline.queue.makeCommandBuffer(),
                  let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return nil }
            if count > 0 {
                var viewport = SIMD4<Float>(Float(size.width), Float(size.height), Float(input.dotSide) * Float(scale), 0)
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
                encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: count)
            }
            encoder.endEncoding()
            return commands
        }
    }

    /// One dot as the shader reads it (two float4, so both sides agree on the layout).
    private struct Dot {
        /// x and y in points, origin top left.
        var position: SIMD4<Float>
        /// Straight RGB and alpha.
        var color: SIMD4<Float>
    }
}

/// A Metal layer redrawn by the view's own display link.
///
/// Not MTKView: its CVDisplayLink thread wakes at the display's refresh rate
/// whatever frame rate is asked for (sampled on a 160 Hz display: 1.9% of a
/// core spent only on waking, perf-flow-animation). NSView's display link
/// runs at the rate requested and stops by itself while the view cannot be
/// seen.
final class FlowParticleView: NSView {
    var onFrame: (FlowParticleView) -> Void = { _ in }
    let metalLayer = CAMetalLayer()
    private var link: CADisplayLink?

    override init(frame: NSRect) {
        super.init(frame: frame)
        metalLayer.device = FlowParticlePipeline.shared?.device
        metalLayer.pixelFormat = FlowParticlePipeline.pixelFormat
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = true
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used from a nib") }

    override func makeBackingLayer() -> CALayer { metalLayer }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        resize()
        let link = displayLink(target: self, selector: #selector(tick))
        let rate = Float(1 / FlowDiagram.frameInterval)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: rate / 2, maximum: rate, preferred: rate)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// The display link retains its target; invalidating it is what lets the view go.
    func stop() {
        link?.invalidate()
        link = nil
    }

    private func resize() {
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        if size.width >= 1, size.height >= 1, metalLayer.drawableSize != size { metalLayer.drawableSize = size }
    }

    @objc private func tick() {
        guard bounds.width >= 1, bounds.height >= 1 else { return }
        // Checked on every frame rather than in layout(): SwiftUI sizes the
        // view without a layout pass, and a stale drawable size shows nothing.
        resize()
        onFrame(self)
    }
}

/// The device, queue and compiled shaders, shared by every diagram (the
/// overview's and the panel's). Compiled once, asynchronously: the first
/// frames simply have no dots, and opening the panel never waits for a
/// shader compile (PLAN §5, panel to first frame).
@MainActor
final class FlowParticlePipeline {
    /// nil where there is no GPU to draw with (some virtual machines): the
    /// diagram is then shown without dots.
    static let shared: FlowParticlePipeline? = {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return FlowParticlePipeline(device: device)
    }()
    nonisolated static let pixelFormat = MTLPixelFormat.bgra8Unorm

    let device: MTLDevice
    let queue: MTLCommandQueue
    /// Dots cover what is under them (light appearance).
    private(set) var over: MTLRenderPipelineState?
    /// Dots add light (dark appearance).
    private(set) var additive: MTLRenderPipelineState?

    private init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        device.makeLibrary(source: Self.shader, options: nil) { library, _ in
            guard let library else { return }
            let states = [false, true].map { additive -> MTLRenderPipelineState? in
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "flow_dot_vertex")
                descriptor.fragmentFunction = library.makeFunction(name: "flow_dot_fragment")
                let attachment = descriptor.colorAttachments[0]
                attachment?.pixelFormat = Self.pixelFormat
                attachment?.isBlendingEnabled = true
                // The fragment shader outputs premultiplied colour.
                attachment?.sourceRGBBlendFactor = .one
                attachment?.sourceAlphaBlendFactor = .one
                attachment?.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
                attachment?.destinationAlphaBlendFactor = additive ? .one : .oneMinusSourceAlpha
                return try? device.makeRenderPipelineState(descriptor: descriptor)
            }
            DispatchQueue.main.async {
                // The pipeline is a process-wide singleton; it is never released.
                FlowParticlePipeline.shared?.over = states[0]
                FlowParticlePipeline.shared?.additive = states[1]
            }
        }
    }

    /// Point sprites: one vertex per dot, positioned in view points.
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Dot { float4 position; float4 color; };
    struct Fragment { float4 position [[position]]; float4 color; float size [[point_size]]; };
    vertex Fragment flow_dot_vertex(uint id [[vertex_id]], const device Dot *dots [[buffer(0)]], constant float4 &view [[buffer(1)]]) {
        Fragment out;
        out.position = float4(dots[id].position.x / view.x * 2 - 1, 1 - dots[id].position.y / view.y * 2, 0, 1);
        out.color = dots[id].color;
        out.size = view.z;
        return out;
    }
    fragment float4 flow_dot_fragment(Fragment in [[stage_in]]) {
        return float4(in.color.rgb * in.color.a, in.color.a);
    }
    """
}
