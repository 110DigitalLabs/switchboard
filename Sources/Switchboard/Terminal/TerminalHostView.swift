import AppKit
import SwiftTerm
import SwiftUI

/// Shows the selected session's long-lived terminal view by swapping it into
/// a container, without ever owning or recreating it.
struct TerminalHostView: NSViewRepresentable {
    let terminal: SessionTerminal

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let view = terminal.view
        guard view.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
    }
}
