import MetalKit
import SwiftUI

public struct NekoCraftMetalView: UIViewRepresentable {
    public final class Coordinator {
        var bridge: NekoCraftRuntimeBridge?
    }

    public init() {
    }

    public func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        context.coordinator.bridge = NekoCraftRuntimeBridge(view: view)
        return view
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func updateUIView(_ view: MTKView, context: Context) {
    }
}

public final class NekoCraftRuntimeBridge: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue

    public init?(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }

        self.commandQueue = commandQueue
        super.init()

        view.device = device
        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.08, green: 0.10, blue: 0.12, alpha: 1)
        view.isPaused = false
        view.enableSetNeedsDisplay = false
    }

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            return
        }

        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }
}