#if canImport(SwiftUI)
import SwiftUI

extension View {
    /// Gives a note-body field the Obsidian list shortcuts (STYLEGUIDE §4.5): ⇧⌘L toggles a
    /// bullet list, ⌥⌘L cycles plain → bullet → checkbox, ⌥L toggles a checkbox. Apply it to the
    /// `TextField` itself. What the keys do is `ListEditing`; this only routes them.
    ///
    /// Mac only. iOS has no hardware-keyboard path yet, so there it changes nothing.
    public func listEditingShortcuts() -> some View {
        #if os(macOS)
        background(ListEditingMonitor())
        #else
        self
        #endif
    }
}

#if os(macOS)
import AppKit

/// A local key monitor, like `onEscapeKey`: the field editor would otherwise type `¬` for ⌥L
/// before any `.onKeyPress` saw it. It edits the field editor directly, so the change goes
/// through the text system (one undo step, the SwiftUI binding updates as for typing).
///
/// Every field with the modifier installs a monitor; each acts only while the window's field
/// editor belongs to the field it sits behind (their frames coincide).
private struct ListEditingMonitor: NSViewRepresentable {
    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ view: MonitorView, context: Context) {}
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.removeMonitor() }

    final class MonitorView: NSView {
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.handle(event) else { return event }
                return nil
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// Whether the event was one of the shortcuts, for this field. Such a key is swallowed
        /// even when it changes nothing, so ⌥L never types `¬` into a body.
        private func handle(_ event: NSEvent) -> Bool {
            guard let command = Self.command(for: event),
                  let window, event.window === window,
                  let editor = window.firstResponder as? NSTextView,
                  !editor.hasMarkedText(), owns(editor)
            else { return false }

            let selected = editor.selectedRange()
            let text = editor.string
            guard let edit = ListEditing.edit(
                command, text: text,
                selection: selected.location..<(selected.location + selected.length))
            else { return true }

            let range = NSRange(location: edit.range.lowerBound, length: edit.range.count)
            guard editor.shouldChangeText(in: range, replacementString: edit.replacement) else { return true }
            editor.textStorage?.replaceCharacters(in: range, with: edit.replacement)
            editor.didChangeText()
            editor.setSelectedRange(NSRange(location: edit.selection.lowerBound, length: edit.selection.count))
            return true
        }

        /// The field editor is edited on behalf of its control (`delegate`); it belongs to this
        /// field when that control's centre lies inside this background view.
        private func owns(_ editor: NSTextView) -> Bool {
            let control = (editor.delegate as? NSView) ?? editor
            guard control.window === window else { return false }
            let controlFrame = control.convert(control.bounds, to: nil)
            let ownFrame = convert(bounds, to: nil).insetBy(dx: -2, dy: -2)
            return ownFrame.contains(CGPoint(x: controlFrame.midX, y: controlFrame.midY))
        }

        private static func command(for event: NSEvent) -> ListEditCommand? {
            guard let key = event.charactersIgnoringModifiers?.lowercased().first else { return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return ListEditShortcut.command(for: ListEditShortcut(
                key: key,
                command: flags.contains(.command),
                option: flags.contains(.option),
                shift: flags.contains(.shift),
                control: flags.contains(.control)))
        }
    }
}
#endif
#endif
