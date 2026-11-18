import AppKit
import SwiftUI

/// Sizes the hosting window to the screen's visible frame once, on first
/// appearance (zoomed, not a full-screen space), and reports the window.
struct WindowZoomer: NSViewRepresentable {
    var onWindow: @MainActor (NSWindow) -> Void = { _ in }

    func makeNSView(context: Context) -> NSView {
        let view = ZoomingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ZoomingView: NSView {
        var onWindow: @MainActor (NSWindow) -> Void = { _ in }
        private var didZoom = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            onWindow(window)
            guard !didZoom else { return }
            didZoom = true
            DispatchQueue.main.async {
                guard let screen = window.screen ?? NSScreen.main else { return }
                window.setFrame(screen.visibleFrame, display: true)
            }
        }
    }
}
