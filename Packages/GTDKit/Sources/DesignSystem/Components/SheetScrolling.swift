#if canImport(SwiftUI)
import SwiftUI

public extension View {
    /// For a `Form` presented as a sheet. macOS' default form style (`.columns`) lays every row
    /// out at full height, never scrolls, and turns a text field's title into a left-column
    /// label — a long picker runs off the bottom of the sheet. `.grouped` scrolls and is iOS'
    /// default already, so iOS is unchanged.
    func sheetFormStyle() -> some View {
        formStyle(.grouped).scrollingSheetFrame()
    }

    /// For a `List` or grouped `Form` presented as a Mac sheet: scrolling content has no
    /// intrinsic height, so give the sheet a size to open at (`SheetMetrics`). No-op on iOS,
    /// where detents size the sheet.
    func scrollingSheetFrame() -> some View {
        #if os(macOS)
        frame(
            minWidth: SheetMetrics.minWidth, idealWidth: SheetMetrics.idealWidth,
            minHeight: SheetMetrics.minHeight, idealHeight: SheetMetrics.idealHeight)
        #else
        self
        #endif
    }
}

/// Rows inside a content-sized sheet (a plain `VStack`, no `List`): drawn inline while they fit
/// under `maxHeight`, scrolling once they do not — so a project with thirty steps cannot push the
/// sheet's buttons off the screen.
public struct OverflowScroll<Content: View>: View {
    private let maxHeight: CGFloat
    private let spacing: CGFloat
    private let content: Content

    public init(
        maxHeight: CGFloat = SheetMetrics.inlineRowsMaxHeight,
        spacing: CGFloat = Spacing.l,
        @ViewBuilder content: () -> Content
    ) {
        self.maxHeight = maxHeight
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        ViewThatFits(in: .vertical) {
            rows
            ScrollView { rows }
        }
        .frame(maxHeight: maxHeight)
        // Without this the frame grows to whatever the sheet offers, up to `maxHeight`, and a
        // two-row list leaves a gap under it. Its ideal height is the rows' own, capped.
        .fixedSize(horizontal: false, vertical: true)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The opened action card inside a content-sized Mac sheet: drawn inline while it fits under
/// `maxHeight`, scrolling once it does not, so a long note never pushes the sheet's action bar
/// and legend below the window. `focused` is the field that should be revealed: the scroll
/// follows the focus so a field opened by keyboard is never hidden under the fold. The card's
/// shadow stays inside the clip sideways through a padding the caller's layout does not see;
/// top and bottom clip exactly at the card, or the scrolled lines would run over the sheet's
/// counter and action bar (so the next card's peek is hidden while the card scrolls).
public struct MacCardScroll<Content: View, Field: Hashable>: View {
    private let focused: Field?
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Content height of the window the sheet hangs from (`SheetParentHeightReader`); the cap
    /// follows it, so the sheet's buttons stay inside the window at any window size.
    @State private var windowHeight: CGFloat?

    public init(focused: Field?, @ViewBuilder content: () -> Content) {
        self.focused = focused
        self.content = content()
    }

    private var maxHeight: CGFloat { SheetMetrics.cardCap(forWindowHeight: windowHeight) }

    public var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollViewReader { proxy in
                ScrollView {
                    content.padding(.horizontal, Self.bleed)
                }
                .scrollBounceBehavior(.basedOnSize)
                .padding(.horizontal, -Self.bleed)
                .onChange(of: focused) { _, field in
                    guard let field else { return }
                    withAnimation(reduceMotion ? Motion.reduced : Motion.standard) {
                        proxy.scrollTo(field, anchor: .center)
                    }
                }
            }
        }
        .frame(maxHeight: maxHeight)
        // Its ideal height is the card's own, capped — see `OverflowScroll`.
        .fixedSize(horizontal: false, vertical: true)
        #if os(macOS)
        .background { SheetParentHeightReader(height: $windowHeight) }
        #endif
    }

    /// Room for the card's shadow (`Elevation`) inside the scroll clip, sideways.
    private static var bleed: CGFloat { Elevation.cardShadowRadius + Elevation.cardShadowY }
}

#if os(macOS)
import AppKit

/// Reports the content height of the window a sheet is attached to (or of the view's own
/// window when it is not in a sheet), and again whenever that window is resized. SwiftUI has
/// no view of the parent window from inside a `.sheet`, and a Mac sheet is happy to grow past
/// its window's bottom edge.
private struct SheetParentHeightReader: NSViewRepresentable {
    @Binding var height: CGFloat?

    func makeNSView(context: Context) -> Probe { Probe { height = $0 } }
    func updateNSView(_ view: Probe, context: Context) {}

    final class Probe: NSView {
        private let onChange: (CGFloat?) -> Void
        private var observer: NSObjectProtocol?

        init(onChange: @escaping (CGFloat?) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable) required init?(coder: NSCoder) { nil }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil { detach() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // `sheetParent` is set once `beginSheet` has run, which is after this view joined
            // the sheet's window: look again on the next turn of the run loop.
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func detach() {
            observer.map(NotificationCenter.default.removeObserver)
            observer = nil
        }

        private func attach() {
            detach()
            guard let parent = window?.sheetParent ?? window else { return onChange(nil) }
            report(parent)
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: parent, queue: .main
            ) { [weak self] _ in self?.report(parent) }
        }

        private func report(_ window: NSWindow) {
            onChange(window.contentLayoutRect.height)
        }
    }
}
#endif
#endif
