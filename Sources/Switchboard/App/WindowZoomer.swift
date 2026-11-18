import AppKit
import SwiftUI

/// Sizes the hosting window to the screen's visible frame once, on first
/// appearance (zoomed, not a full-screen space).
struct WindowZoomer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ZoomingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ZoomingView: NSView {
        private var didZoom = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !didZoom, let window else { return }
            didZoom = true
            DispatchQueue.main.async {
                guard let screen = window.screen ?? NSScreen.main else { return }
                window.setFrame(screen.visibleFrame, display: true)
            }
        }
    }
}
