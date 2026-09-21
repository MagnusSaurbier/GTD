#if canImport(SwiftUI) && os(macOS)
import AppKit
import SwiftUI

extension View {
    /// Routes **every** `Esc` pressed in this view's window through `action`, and swallows it.
    ///
    /// `.onKeyPress(.escape)` on a focusable container is not enough on a Mac sheet: while a
    /// `TextField` is first responder the field editor turns `Esc` into `cancelOperation:`, which
    /// travels up the responder chain and makes the sheet dismiss itself — the whole `Esc` ladder
    /// (STYLEGUIDE §3.6) is skipped. The same happens once the container lost key focus, e.g.
    /// after a click on a button. A local event monitor sees the key before the responder chain
    /// does, so one press is exactly one rung, whatever has focus.
    ///
    /// Left alone on purpose: `Esc` in **another window** (a nested sheet is its own window and
    /// keeps closing itself), and `Esc` that cancels an input-method composition.
    func onEscapeKey(perform action: @escaping () -> Void) -> some View {
        background(EscapeKeyMonitor(action: action))
    }
}

private struct EscapeKeyMonitor: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.action = action
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.action = action
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) {
        view.removeMonitor()
    }

    final class MonitorView: NSView {
        var action: (() -> Void)?
        private var monitor: Any?

        private static let escapeKeyCode: UInt16 = 53

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.shouldHandle(event) else { return event }
                self.action?()
                return nil
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func shouldHandle(_ event: NSEvent) -> Bool {
            guard event.keyCode == Self.escapeKeyCode,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  let window, event.window === window, window.attachedSheet == nil
            else { return false }
            if let editor = window.firstResponder as? NSTextView, editor.hasMarkedText() {
                return false
            }
            return true
        }
    }
}
#endif
