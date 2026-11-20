import AppKit
import Metal
import ParalluxKit
import QuartzCore
import SwiftUI

/// The flow diagram's moving picture, drawn by the GPU (perf-flow-animation):
/// bands, idle links' dashed lines, nodes and the dots. Everything that
/// changes from frame to frame is here; SwiftUI keeps only the labels, which
/// change once a second.
///
/// Why not a SwiftUI Canvas: redrawing it meant a layout pass, a new display
/// list and a full-layer commit on the main thread for every frame. Measured
/// on screen (2026-11-19, 804×330 pt, about 900 dots): all in one Canvas
/// 10–12.6% of a core; dots on the GPU but bands and labels in a Canvas 3.5%
/// steady and 6–7% whenever the rates changed, the difference being those
/// redraws while the bands eased; everything here 4.2–4.6% steady and
/// 4.4–5.0% while the rates change (docs/tasks/perf-flow-animation.md).
///
/// The display link runs only while something moves: dots (traffic) or an
/// ease. Otherwise a frame is drawn when the input changes, and nothing at
/// all in a window that cannot be seen.
struct FlowLayer: NSViewRepresentable {
    struct Input {
        var target: FlowMotion.Target
        var metrics: FlowDiagram.Metrics
        /// One per link, in the links' order.
        var linkColors: [Color]
        /// Links that are switched off: their node is drawn faded.
        var dimmedLinks: [Bool]
        /// One per exit.
        var exitColors: [Color]
        /// The rates changed less than FlowEase.duration ago.
        var easing: Bool
        var isVisible: Bool
        var reduceMotion: Bool
        /// Points.
        var dotSide: CGFloat
        var isDark: Bool
    }

    let motion: FlowMotion
    let input: Input

    func makeCoordinator() -> Renderer { Renderer(motion: motion) }

    func makeNSView(context: Context) -> FlowLayerView {
        let view = FlowLayerView()
        let renderer = context.coordinator
        view.onFrame = { [weak renderer] view in renderer?.draw(in: view, animated: true) }
        view.onStale = { [weak renderer] view in renderer?.redrawIfIdle(view) }
        return view
    }

    func updateNSView(_ view: FlowLayerView, context: Context) {
        context.coordinator.update(input, view: view)
    }

    static func dismantleNSView(_ view: FlowLayerView, coordinator: Renderer) {
        view.setRunning(false)
    }

    /// Turns the input into vertices once per frame.
    @MainActor
    final class Renderer {
        private let motion: FlowMotion
        private var input: Input?
        private var palette = Palette()
        /// Why 3: a buffer handed to the GPU may still be read while the next
        /// frame is being written; three in rotation is Metal's usual answer
        /// (a drawable queue is at most three deep).
        private var dotBuffers: [MTLBuffer] = []
        private var meshBuffers: [MTLBuffer] = []
        private var frame = 0
        private var meshFrame = 0
        /// The mesh currently in `meshBuffers[meshFrame]`: rebuilt only when the layout moves.
        private var meshKey: MeshKey?
        private var meshCounts = (under: 0, over: 0)
        private var multisample: MTLTexture?
        private var waitingForPipeline = false

        init(motion: FlowMotion) { self.motion = motion }

        func update(_ input: Input, view: FlowLayerView) {
            self.input = input
            // Resolved here, when the inputs change, not on every frame.
            view.effectiveAppearance.performAsCurrentDrawingAppearance {
                palette = Palette(links: input.linkColors.map(Self.rgba), exits: input.exitColors.map(Self.rgba),
                                  centre: Self.rgba(NSColor.labelColor), idle: Self.rgba(NSColor.tertiaryLabelColor),
                                  bandOpacity: Float(FlowPalette.bandOpacity(input.isDark ? .dark : .light)))
            }
            meshKey = nil
            let moving = input.isVisible && !input.reduceMotion && (input.target.hasTraffic || input.easing)
            view.setRunning(moving)
            if !moving { redrawIfIdle(view) }
        }

        /// One frame of the picture as it stands: the input changed, or the view was resized, while nothing moves.
        func redrawIfIdle(_ view: FlowLayerView) {
            guard let input, input.isVisible, !view.isRunning else { return }
            guard isReady else {
                // The shaders are still compiling (first diagram of the process): draw when they are done.
                guard !waitingForPipeline else { return }
                waitingForPipeline = true
                FlowPipeline.shared?.whenReady { [weak self, weak view] in
                    self?.waitingForPipeline = false
                    if let view { self?.redrawIfIdle(view) }
                }
                return
            }
            draw(in: view, animated: false)
        }

        /// One frame onto the screen.
        func draw(in view: FlowLayerView, animated: Bool) {
            view.resize()
            guard view.bounds.width >= 1, view.bounds.height >= 1, isReady,
                  // Asked last: a drawable taken and not presented wastes one of the layer's three.
                  let drawable = view.metalLayer.nextDrawable(),
                  let commands = render(to: drawable.texture, size: view.bounds.size, scale: view.metalLayer.contentsScale, at: Date(), animated: animated) else { return }
            commands.present(drawable)
            commands.commit()
        }

        private var isReady: Bool { input != nil && FlowPipeline.shared?.fill != nil }

        /// Encodes the diagram at `date` into `texture` (`size` in points) and
        /// returns the command buffer for the caller to present or wait on and
        /// commit; nil while there is nothing to draw with. Separate from
        /// `draw(in:animated:)` so the picture can be produced, and checked,
        /// without a screen. `animated` false draws the settled picture
        /// without dots (reduced motion, or nothing moving).
        func render(to texture: MTLTexture, size: CGSize, scale: CGFloat, at date: Date, animated: Bool) -> MTLCommandBuffer? {
            guard let input, let pipeline = FlowPipeline.shared, let fill = pipeline.fill,
                  let dotState = input.isDark ? pipeline.additiveDots : pipeline.fill else { return nil }
            if dotBuffers.isEmpty {
                dotBuffers = (0..<3).compactMap { _ in pipeline.device.makeBuffer(length: MemoryLayout<Vertex>.stride * FlowParticles.limit, options: .storageModeShared) }
                meshBuffers = (0..<3).compactMap { _ in pipeline.device.makeBuffer(length: MemoryLayout<Vertex>.stride * Self.meshCapacity, options: .storageModeShared) }
            }
            guard dotBuffers.count == 3, meshBuffers.count == 3, let target = multisampleTarget(for: texture, device: pipeline.device) else { return nil }

            let m = input.metrics
            let layout: SankeyLayout
            var particles: [FlowParticles.Particle] = []
            if animated {
                let current = motion.particles(at: date, target: input.target, metrics: m, easing: input.easing)
                layout = current.layout
                particles = current.particles
            } else {
                layout = motion.layout(at: date, target: input.target, metrics: m, easing: false)
            }

            // Bands and nodes: only when the layout moved (an ease), not on every frame.
            let key = MeshKey(layout: layout, frame: m.meshFrame)
            if key != meshKey {
                meshFrame = (meshFrame + 1) % meshBuffers.count
                meshCounts = fillMesh(meshBuffers[meshFrame], FlowMesh.make(layout, frame: m.meshFrame))
                meshKey = key
            }
            let mesh = meshBuffers[meshFrame]

            frame = (frame + 1) % dotBuffers.count
            let dots = dotBuffers[frame]
            let dotCount = fillDots(dots, particles, layout: layout, metrics: m)

            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].resolveTexture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .multisampleResolve
            // Transparent: the picture sits on the window's content layer, under the SwiftUI labels.
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            guard let commands = pipeline.queue.makeCommandBuffer(),
                  let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return nil }
            var viewport = SIMD4<Float>(Float(size.width), Float(size.height), Float(input.dotSide) * Float(scale), 0)
            encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
            // Design's order: bands and dashes, the dots riding them, nodes on top.
            encoder.setRenderPipelineState(fill)
            encoder.setVertexBuffer(mesh, offset: 0, index: 0)
            if meshCounts.under > 0 { encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: meshCounts.under) }
            if dotCount > 0 {
                encoder.setRenderPipelineState(dotState)
                encoder.setVertexBuffer(dots, offset: 0, index: 0)
                encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: dotCount)
                encoder.setRenderPipelineState(fill)
                encoder.setVertexBuffer(mesh, offset: 0, index: 0)
            }
            if meshCounts.over > 0 { encoder.drawPrimitives(type: .triangle, vertexStart: meshCounts.under, vertexCount: meshCounts.over) }
            encoder.endEncoding()
            return commands
        }

        /// Why: FlowMesh's own bound for bands and dashes, plus room for the
        /// nodes (36 vertices each; a hundred nodes is far past any Mac's links and exits).
        private static let meshCapacity = FlowMesh.maxVertices + 3600

        /// Writes the pieces under the dots first, then the nodes; returns how many vertices of each.
        private func fillMesh(_ buffer: MTLBuffer, _ pieces: [FlowMesh.Piece]) -> (under: Int, over: Int) {
            guard let input else { return (0, 0) }
            let vertices = buffer.contents().bindMemory(to: Vertex.self, capacity: Self.meshCapacity)
            var count = 0
            func write(_ piece: FlowMesh.Piece) {
                let color: SIMD4<Float>
                switch piece.paint {
                case let .band(link): color = palette.link(link) * SIMD4(1, 1, 1, palette.bandOpacity)
                case let .link(index): color = palette.link(index) * SIMD4(1, 1, 1, index < input.dimmedLinks.count && input.dimmedLinks[index] ? 0.3 : 1)
                case let .exit(index): color = index < palette.exits.count ? palette.exits[index] : palette.idle
                case .centre, .rule: color = palette.centre
                case .idle: color = palette.idle
                }
                for point in piece.triangles where count < Self.meshCapacity {
                    vertices[count] = Vertex(position: SIMD4(point.x, point.y, 0, 0), color: color)
                    count += 1
                }
            }
            let isNode = { (paint: FlowMesh.Paint) in
                switch paint {
                case .band, .idle: false
                case .link, .exit, .centre, .rule: true
                }
            }
            for piece in pieces where !isNode(piece.paint) { write(piece) }
            let under = count
            for piece in pieces where isNode(piece.paint) { write(piece) }
            return (under, count - under)
        }

        private func fillDots(_ buffer: MTLBuffer, _ particles: [FlowParticles.Particle], layout: SankeyLayout, metrics m: FlowDiagram.Metrics) -> Int {
            guard !particles.isEmpty else { return 0 }
            // Bands by (from, to), so finding a particle's band is one lookup. A
            // dictionary: in a three-column layout `to` is a band id, not an exit.
            var bands: [Int: SankeyLayout.Band] = [:]
            let stride = (layout.bands.map(\.to).max() ?? 0) + 1
            for band in layout.bands { bands[band.from * stride + band.to] = band }
            let dots = buffer.contents().bindMemory(to: Vertex.self, capacity: FlowParticles.limit)
            var count = 0
            for particle in particles.prefix(FlowParticles.limit) {
                guard particle.from < palette.links.count, particle.to < stride, let band = bands[particle.from * stride + particle.to] else { continue }
                let first = particle.progress < 1
                let t = first ? particle.progress : particle.progress - 1
                let x0 = first ? m.leftX + m.bar : m.centreX + m.bar, x1 = first ? m.centreX : m.rightX
                let x = x0 + (x1 - x0) * CGFloat(FlowParticles.run(t))
                let y = m.inset + CGFloat(FlowParticles.y(of: particle, in: band))
                // Fades in and out over the first and last eighth of a leg.
                let alpha = Float(min(1, particle.progress * 8, (2 - particle.progress) * 8) * 0.9)
                dots[count] = Vertex(position: SIMD4(Float(x), Float(y), 0, 0), color: palette.links[particle.from] * SIMD4(1, 1, 1, alpha))
                count += 1
            }
            return count
        }

        /// Four samples per pixel, so the bands' curved edges are as smooth
        /// as the Canvas drew them. Never read back, so it takes no memory
        /// where the GPU allows that (Apple silicon).
        private func multisampleTarget(for texture: MTLTexture, device: MTLDevice) -> MTLTexture? {
            if let multisample, multisample.width == texture.width, multisample.height == texture.height { return multisample }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat, width: texture.width, height: texture.height, mipmapped: false)
            descriptor.textureType = .type2DMultisample
            descriptor.sampleCount = FlowPipeline.sampleCount
            descriptor.usage = .renderTarget
            descriptor.storageMode = device.hasUnifiedMemory ? .memoryless : .private
            multisample = device.makeTexture(descriptor: descriptor)
            return multisample
        }

        private static func rgba(_ color: Color) -> SIMD4<Float> { rgba(NSColor(color)) }

        private static func rgba(_ color: NSColor) -> SIMD4<Float> {
            let c = color.usingColorSpace(.sRGB) ?? .gray
            return SIMD4(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent), Float(c.alphaComponent))
        }

        private struct MeshKey: Equatable {
            var layout: SankeyLayout
            var frame: FlowMesh.Frame
        }

        /// Straight (not premultiplied) sRGB colours, resolved for the view's appearance.
        private struct Palette {
            var links: [SIMD4<Float>] = []
            var exits: [SIMD4<Float>] = []
            var centre = SIMD4<Float>(0, 0, 0, 1)
            var idle = SIMD4<Float>(0, 0, 0, 0.25)
            var bandOpacity: Float = 0.4
            func link(_ index: Int) -> SIMD4<Float> { index < links.count ? links[index] : idle }
        }
    }

    /// One vertex as the shader reads it (two float4, so both sides agree on the layout).
    private struct Vertex {
        /// x and y in points, origin top left.
        var position: SIMD4<Float>
        /// Straight RGB and alpha.
        var color: SIMD4<Float>
    }
}

/// A Metal layer redrawn by the view's own display link while it runs.
///
/// Not MTKView: its CVDisplayLink thread wakes at the display's refresh rate
/// whatever frame rate is asked for (sampled on a 160 Hz display: 1.9% of a
/// core spent only on waking). NSView's display link runs at the rate
/// requested and stops while the view cannot be seen.
final class FlowLayerView: NSView {
    /// A frame is due (the display link fired).
    var onFrame: (FlowLayerView) -> Void = { _ in }
    /// The picture went stale while no display link runs (resized, moved to another display, appearance changed).
    var onStale: (FlowLayerView) -> Void = { _ in }
    let metalLayer = CAMetalLayer()
    private var link: CADisplayLink?
    private var wantsRunning = false
    var isRunning: Bool { link != nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        metalLayer.device = FlowPipeline.shared?.device
        metalLayer.pixelFormat = FlowPipeline.pixelFormat
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = true
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used from a nib") }

    override func makeBackingLayer() -> CALayer { metalLayer }

    func setRunning(_ running: Bool) {
        wantsRunning = running
        refreshLink()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A display link belongs to the window's display: start over.
        stop()
        refreshLink()
        if !isRunning { onStale(self) }
    }

    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        if !isRunning { onStale(self) }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if !isRunning { onStale(self) }
    }

    /// The drawable follows the view. Checked whenever a frame is drawn rather
    /// than in layout(): SwiftUI sizes the view without a layout pass, and a
    /// stale drawable size shows nothing.
    func resize() {
        let scale = window?.backingScaleFactor ?? 2
        // Only when it changed: setting a layer property opens a transaction, and this runs every frame.
        if metalLayer.contentsScale != scale { metalLayer.contentsScale = scale }
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        if size.width >= 1, size.height >= 1, metalLayer.drawableSize != size { metalLayer.drawableSize = size }
    }

    private func refreshLink() {
        guard wantsRunning, window != nil else { return stop() }
        guard link == nil else { return }
        let link = displayLink(target: self, selector: #selector(tick))
        let rate = Float(1 / FlowDiagram.frameInterval)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: rate / 2, maximum: rate, preferred: rate)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// The display link retains its target; invalidating it is what lets the view go.
    private func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick() { onFrame(self) }
}

/// The device, queue and compiled shaders, shared by every diagram (the
/// overview's and the panel's). Compiled once, asynchronously: the first
/// frames are simply empty, and opening the panel never waits for a shader
/// compile (PLAN §5, panel to first frame).
@MainActor
final class FlowPipeline {
    /// nil where there is no GPU to draw with; FlowDiagram then draws a still picture itself.
    static let shared: FlowPipeline? = {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return FlowPipeline(device: device)
    }()
    nonisolated static let pixelFormat = MTLPixelFormat.bgra8Unorm
    /// Why 4: the usual multisample count, supported by every Mac GPU; the
    /// band edges are long shallow curves where 1 sample shows steps.
    nonisolated static let sampleCount = 4

    let device: MTLDevice
    let queue: MTLCommandQueue
    /// Source-over: bands, nodes, and the dots in light appearance.
    private(set) var fill: MTLRenderPipelineState?
    /// Dots that add light (dark appearance, the design's `lighter`).
    private(set) var additiveDots: MTLRenderPipelineState?
    private var waiting: [() -> Void] = []

    /// Runs `body` on the main actor once the shaders are compiled (never, if they fail to).
    func whenReady(_ body: @escaping () -> Void) {
        if fill != nil { body() } else { waiting.append(body) }
    }

    private init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        device.makeLibrary(source: Self.shader, options: nil) { library, _ in
            guard let library else { return }
            let states = [false, true].map { additive -> MTLRenderPipelineState? in
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "flow_vertex")
                descriptor.fragmentFunction = library.makeFunction(name: "flow_fragment")
                descriptor.rasterSampleCount = Self.sampleCount
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
                guard let shared = FlowPipeline.shared else { return }
                shared.fill = states[0]
                shared.additiveDots = states[1]
                guard shared.fill != nil else { return }
                let waiting = shared.waiting
                shared.waiting = []
                waiting.forEach { $0() }
            }
        }
    }

    /// One vertex function for triangles and point sprites (the point size is ignored for triangles),
    /// positions in view points.
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Vertex { float4 position; float4 color; };
    struct Fragment { float4 position [[position]]; float4 color; float size [[point_size]]; };
    vertex Fragment flow_vertex(uint id [[vertex_id]], const device Vertex *vertices [[buffer(0)]], constant float4 &view [[buffer(1)]]) {
        Fragment out;
        out.position = float4(vertices[id].position.x / view.x * 2 - 1, 1 - vertices[id].position.y / view.y * 2, 0, 1);
        out.color = vertices[id].color;
        out.size = view.z;
        return out;
    }
    fragment float4 flow_fragment(Fragment in [[stage_in]]) {
        return float4(in.color.rgb * in.color.a, in.color.a);
    }
    """
}
