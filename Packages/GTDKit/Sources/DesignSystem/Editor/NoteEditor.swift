#if canImport(SwiftUI)
import SwiftUI
#if os(macOS)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
typealias PlatformFontDescriptor = NSFontDescriptor
#else
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
typealias PlatformFontDescriptor = UIFontDescriptor
#endif

/// The text style of a `NoteEditor` — the two `Typo` styles note bodies use.
public enum NoteEditorFont: Sendable {
    /// `Typo.body`.
    case body
    /// `Typo.cardText`.
    case cardText
}

/// The text colour of a `NoteEditor`.
public enum NoteEditorTone: Sendable {
    /// `Color.ink`.
    case ink
    /// `Color.textSecondary`.
    case secondary
}

// MARK: - Styling (shared)

extension NSAttributedString.Key {
    /// Markup off the caret line: no glyph, no width (`NoteLayoutManager`).
    static let noteHidden = NSAttributedString.Key("gtd.note.hidden")
    /// A list bullet, drawn as a dot over its invisible glyph.
    static let noteBullet = NSAttributedString.Key("gtd.note.bullet")
    /// A checkbox (`[ ]`/`[x]`), drawn as a box over its invisible glyphs; the value is ticked.
    static let noteCheckbox = NSAttributedString.Key("gtd.note.checkbox")
}

/// Turns `MarkdownRendering` runs into text-storage attributes. Shared by both platforms.
@MainActor
struct NoteStyler {
    var font: NoteEditorFont
    var tone: NoteEditorTone

    var baseFont: PlatformFont {
        #if os(macOS)
        NSFont.preferredFont(forTextStyle: font == .body ? .body : .title3)
        #else
        UIFont.preferredFont(forTextStyle: font == .body ? .body : .title3)
        #endif
    }

    var baseColor: PlatformColor { PlatformColor(tone == .ink ? Color.ink : Color.textSecondary) }
    var mutedColor: PlatformColor { PlatformColor(tone == .ink ? Color.textSecondary : Color.textTertiary) }
    var placeholderColor: PlatformColor { PlatformColor(Color.textTertiary) }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: baseColor]
    }

    /// Restyles the whole storage. `selection` is `nil` while the editor has no focus.
    func apply(to storage: NSTextStorage, selection: NSRange?) {
        let runs = MarkdownRendering.runs(
            storage.string,
            selection: selection.map { $0.location..<($0.location + $0.length) })
        let base = baseFont
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: NSRange(location: 0, length: storage.length))
        for run in runs {
            let range = NSRange(location: run.range.lowerBound, length: run.range.count)
            storage.addAttributes(attributes(for: run.attributes, base: base), range: range)
        }
        storage.endEditing()
    }

    private func attributes(for a: MarkdownAttributes, base: PlatformFont) -> [NSAttributedString.Key: Any] {
        var result: [NSAttributedString.Key: Any] = [:]
        let scale: CGFloat = switch a.heading {
        case 1: 1.5
        case 2: 1.3
        case 3: 1.15
        case 4...6: 1.05
        default: 1
        }
        if a.bold || a.italic || a.code || a.codeBlock || a.heading > 0 {
            result[.font] = font(base, size: base.pointSize * scale,
                                 bold: a.bold || a.heading > 0, italic: a.italic,
                                 mono: a.code || a.codeBlock)
        }
        if a.muted { result[.foregroundColor] = mutedColor }
        if a.link { result[.foregroundColor] = PlatformColor(Color.gtdAccent) }
        if a.strike { result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if a.highlight { result[.backgroundColor] = PlatformColor(Color.accentWash) }
        if a.code { result[.backgroundColor] = PlatformColor(Color.fillQuiet) }
        if a.hidden {
            result[.noteHidden] = true
            result[.foregroundColor] = PlatformColor.clear
        }
        if a.bullet {
            result[.noteBullet] = true
            result[.foregroundColor] = PlatformColor.clear
        }
        if let checked = a.checkbox {
            result[.noteCheckbox] = checked
            result[.foregroundColor] = PlatformColor.clear
        }
        return result
    }

    private func font(_ base: PlatformFont, size: CGFloat, bold: Bool, italic: Bool, mono: Bool) -> PlatformFont {
        #if os(macOS)
        if mono { return .monospacedSystemFont(ofSize: size * 0.92, weight: bold ? .semibold : .regular) }
        var traits = base.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: size) ?? base
        #else
        if mono { return .monospacedSystemFont(ofSize: size * 0.92, weight: bold ? .semibold : .regular) }
        var traits = base.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else { return base.withSize(size) }
        return UIFont(descriptor: descriptor, size: size)
        #endif
    }
}

/// TextKit 1 layout: hides `noteHidden` glyphs and draws bullets and boxes.
final class NoteLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes: UnsafePointer<Int>,
        font: PlatformFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let storage = textStorage, glyphRange.length > 0 else { return 0 }
        var modified = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
        var changed = false
        for index in 0..<glyphRange.length {
            let character = characterIndexes[index]
            guard character < storage.length,
                  storage.attribute(.noteHidden, at: character, effectiveRange: nil) != nil
            else { continue }
            modified[index] = .null
            changed = true
        }
        guard changed else { return 0 }
        modified.withUnsafeBufferPointer { buffer in
            layoutManager.setGlyphs(glyphs, properties: buffer.baseAddress!, characterIndexes: characterIndexes,
                                    font: font, forGlyphRange: glyphRange)
        }
        return glyphRange.length
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        storage.enumerateAttribute(.noteBullet, in: characters) { value, range, _ in
            guard value != nil else { return }
            for offset in range.location..<NSMaxRange(range) {
                let rect = rectFor(NSRange(location: offset, length: 1), in: container, origin: origin)
                let font = storage.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont
                let diameter = (font?.pointSize ?? 13) * 0.32
                let dot = CGRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2,
                                 width: diameter, height: diameter)
                NoteDrawing.fillCircle(dot, color: PlatformColor(Color.textSecondary))
            }
        }
        storage.enumerateAttribute(.noteCheckbox, in: characters) { value, range, _ in
            guard let checked = value as? Bool else { return }
            let rect = rectFor(range, in: container, origin: origin)
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont
            let side = min(rect.width, (font?.pointSize ?? 13) * 1.05)
            let box = CGRect(x: rect.minX, y: rect.midY - side / 2, width: side, height: side)
            NoteDrawing.symbol(checked ? Symbols.checkboxOn : Symbols.checkboxOff, in: box,
                               pointSize: font?.pointSize ?? 13,
                               color: PlatformColor(checked ? Color.gtdAccent : Color.textSecondary))
        }
    }

    /// The drawn rect of a character range on one line, in the text view's coordinates.
    ///
    /// Built from glyph locations, not `boundingRect(forGlyphRange:in:)`: when a line starts
    /// with hidden (null) glyphs — a task's `- ` — and the layout was updated incrementally
    /// (Return at the end of that task), TextKit 1 answers both `boundingRect` and
    /// `enumerateEnclosingRects` with a zero-width rect at the end of the line above, so the
    /// box vanished and could not be clicked (2026-09-24). `location(forGlyphAt:)` stays right.
    func rectFor(_ range: NSRange, in container: NSTextContainer, origin: CGPoint) -> CGRect {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return .zero }
        var fragmentGlyphs = NSRange()
        let fragment = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: &fragmentGlyphs)
        let start = location(forGlyphAt: glyphs.location).x
        let after = NSMaxRange(glyphs)
        let end = after < NSMaxRange(fragmentGlyphs)
            ? location(forGlyphAt: after).x
            : lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil).maxX - fragment.minX
        return CGRect(x: fragment.minX + start + origin.x, y: fragment.minY + origin.y,
                      width: max(0, end - start), height: fragment.height)
    }
}

@MainActor
private enum NoteDrawing {
    static func fillCircle(_ rect: CGRect, color: PlatformColor) {
        color.setFill()
        #if os(macOS)
        NSBezierPath(ovalIn: rect).fill()
        #else
        UIBezierPath(ovalIn: rect).fill()
        #endif
    }

    static func symbol(_ name: String, in rect: CGRect, pointSize: CGFloat, color: PlatformColor) {
        #if os(macOS)
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        #else
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let image = UIImage(systemName: name, withConfiguration: configuration)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        image.draw(in: rect)
        #endif
    }
}

/// The shared parts of both platforms' text views: storage, layout, the list commands.
@MainActor
enum NoteText {
    /// A TextKit 1 stack. The storage is returned too: a layout manager holds its storage only
    /// weakly, so the text view must keep it (`NoteTextView.storage`) or it is freed at once.
    static func makeStack() -> (storage: NSTextStorage, container: NSTextContainer) {
        let storage = NSTextStorage()
        let layout = NoteLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        return (storage, container)
    }

    /// The checkbox under `point` (text-container coordinates), if a drawn box is there.
    static func checkbox(at point: CGPoint, layout: NSLayoutManager, container: NSTextContainer,
                         text: String) -> Range<Int>? {
        var fraction: CGFloat = 0
        let index = layout.characterIndex(for: point, in: container,
                                          fractionOfDistanceBetweenInsertionPoints: &fraction)
        guard let range = MarkdownRendering.checkbox(at: index, in: text),
              let manager = layout as? NoteLayoutManager else { return nil }
        let rect = manager.rectFor(NSRange(location: range.lowerBound, length: range.count),
                                   in: container, origin: .zero)
        return rect.insetBy(dx: -2, dy: -2).contains(point) ? range : nil
    }

    /// Where the caret belongs after the text was replaced from outside the view (the inbox card
    /// turning `- ` into `- [ ] `, a snapshot arriving mid-edit). The change is taken to be one
    /// replaced stretch between the texts' common prefix and suffix, in UTF-16 units:
    /// a caret before it stays, a caret at or after it moves with the change — so an insertion
    /// exactly at the caret lands the caret after the inserted text, as typing would — and a
    /// caret inside the replaced stretch goes to its end. Never inside hidden markup, then.
    static func caret(_ caret: Int, from old: String, to new: String) -> Int {
        let before = Array(old.utf16), after = Array(new.utf16)
        var prefix = 0
        while prefix < before.count, prefix < after.count, before[prefix] == after[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < before.count - prefix, suffix < after.count - prefix,
              before[before.count - 1 - suffix] == after[after.count - 1 - suffix] { suffix += 1 }
        let clamped = max(0, min(caret, before.count))
        if clamped >= before.count - suffix { return clamped + (after.count - before.count) }
        if clamped <= prefix { return clamped }
        return after.count - suffix
    }

    /// The width a body is measured at when the proposal is no real width (a `0` or `nil`/infinite probe).
    static let unproposedWidth: CGFloat = 320

    /// The size a `NoteEditor` answers a probe with. A pure function of the proposal, never of
    /// the view's current frame: answering the `0` probe with the frame's width made that width
    /// the field's *minimum*, so a legacy scroller appearing (17 pt narrower) and disappearing
    /// flipped the layout between two answers forever, and AppKit killed the app for too many
    /// Update Constraints passes (2026-09-27 crash, `NoteLayoutTests`).
    /// `measure` gives the text's height at a wrap width.
    static func fittingSize(proposedWidth proposed: CGFloat?,
                            measure: (CGFloat) -> CGFloat) -> CGSize {
        if let proposed, proposed.isFinite, proposed > 0 {
            return CGSize(width: proposed, height: measure(proposed))
        }
        let height = measure(unproposedWidth)
        // The `0` probe asks for the minimum width: a text field can wrap to any width.
        if let proposed, proposed.isFinite { return CGSize(width: 0, height: height) }
        return CGSize(width: unproposedWidth, height: height)
    }

    static func height(layout: NSLayoutManager, container: NSTextContainer, font: PlatformFont,
                       minLines: Int) -> CGFloat {
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container).height
        #if os(macOS)
        let line = layout.defaultLineHeight(for: font)
        #else
        let line = font.lineHeight
        #endif
        return ceil(max(used, line * CGFloat(max(minLines, 1))))
    }
}

#if os(macOS)

// MARK: - macOS

/// A note-body field with Obsidian-style live preview (STYLEGUIDE §4.4): markdown is styled as
/// you type, markup shows only on the lines the selection touches, bullets and boxes are drawn,
/// and a click on a box ticks it. Carries the list keys of §4.5 and continues lists on Return.
///
/// Use it where a body used a vertical `TextField`; `.focused(_:equals:)`, `.accessibilityLabel`
/// and `.fixedSize` apply as they did. Font and colour are parameters (`Typo`/`Color` cannot be
/// read back from the environment into AppKit).
public struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    var prompt: String
    var font: NoteEditorFont
    var tone: NoteEditorTone
    var minLines: Int
    var onAdvance: (() -> Void)?

    public init(text: Binding<String>, prompt: String = "", font: NoteEditorFont = .body,
                tone: NoteEditorTone = .ink, minLines: Int = 1) {
        self._text = text
        self.prompt = prompt
        self.font = font
        self.tone = tone
        self.minLines = minLines
    }

    /// What `⌘↩` does once the field has no input line left (STYLEGUIDE §4.4): the owner moves
    /// its SwiftUI focus on — `focus = .what`, or `nil` to give the keys back to the card. Without
    /// it the field asks AppKit for the next key view, which SwiftUI's hosting does not reliably
    /// answer (the inbox card's `Why?` never reached `What?` that way, 2026-09-25).
    public func onAdvance(_ action: @escaping () -> Void) -> NoteEditor {
        var copy = self
        copy.onAdvance = action
        return copy
    }

    public func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    public func makeNSView(context: Context) -> NoteTextView {
        let stack = NoteText.makeStack()
        let view = NoteTextView(frame: .zero, textContainer: stack.container)
        view.storage = stack.storage
        view.delegate = context.coordinator
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.smartInsertDeleteEnabled = false
        view.string = text
        configure(view)
        return view
    }

    public func updateNSView(_ view: NoteTextView, context: Context) {
        context.coordinator.text = $text
        configure(view)
        if view.string != text, !view.hasMarkedText() {
            let caret = NoteText.caret(view.selectedRange().location, from: view.string, to: text)
            view.string = text
            view.setSelectedRange(NSRange(location: caret, length: 0))
        }
        view.restyle()
    }

    /// SwiftUI probes with 0, the real width and infinity. The text wraps at the width the view
    /// is finally given (`NoteTextView.setFrameSize`), so a probe must not leave the container
    /// at its width — that is what wrapped a wide detail column at sixty points (2026-09-24).
    public func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NoteTextView,
                             context: Context) -> CGSize? {
        guard let layout = view.layoutManager, let container = view.textContainer else { return nil }
        let previous = container.containerSize
        let size = NoteText.fittingSize(proposedWidth: proposal.width) { width in
            container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
            return NoteText.height(layout: layout, container: container,
                                   font: view.styler.baseFont, minLines: minLines)
        }
        container.containerSize = view.bounds.width > 0
            ? CGSize(width: view.bounds.width, height: .greatestFiniteMagnitude) : previous
        return size
    }

    private func configure(_ view: NoteTextView) {
        view.styler = NoteStyler(font: font, tone: tone)
        view.placeholder = prompt
        view.minLines = minLines
        view.onAdvance = onAdvance
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        public func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NoteTextView else { return }
            if text.wrappedValue != view.string { text.wrappedValue = view.string }
            view.restyle()
            view.invalidateIntrinsicContentSize()
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            (notification.object as? NoteTextView)?.restyle()
        }
    }
}

public final class NoteTextView: NSTextView {
    var styler = NoteStyler(font: .body, tone: .ink)
    /// Keeps the TextKit stack alive (see `NoteText.makeStack`).
    var storage: NSTextStorage?
    var placeholder = "" { didSet { if placeholder != oldValue { needsDisplay = true } } }
    var minLines = 1
    /// `⌘↩` with no input line left (see `NoteEditor.onAdvance`).
    var onAdvance: (() -> Void)?
    private var isRestyling = false
    private var lastStyle: (text: String, selection: NSRange?)?

    private var isFocused: Bool { window?.firstResponder === self }

    /// Restyles when the text or — while focused — the caret's lines changed.
    func restyle() {
        guard !isRestyling, !hasMarkedText(), let storage = textStorage else { return }
        let selection = isFocused ? selectedRange() : nil
        if let last = lastStyle, last.text == string, last.selection == selection { return }
        isRestyling = true
        styler.apply(to: storage, selection: selection)
        typingAttributes = styler.baseAttributes
        lastStyle = (string, selection)
        isRestyling = false
        invalidateIntrinsicContentSize()
    }

    public override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { lastStyle = nil; restyle() }
        return accepted
    }

    public override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            lastStyle = nil
            DispatchQueue.main.async { [weak self] in self?.restyle() }
        }
        return resigned
    }

    /// The frame SwiftUI settles on is the wrap width — not the last width a probe measured.
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard newSize.width > 0, let container = textContainer,
              container.containerSize.width != newSize.width else { return }
        container.containerSize = CGSize(width: newSize.width, height: .greatestFiniteMagnitude)
        invalidateIntrinsicContentSize()
    }

    public override var intrinsicContentSize: NSSize {
        guard let layout = layoutManager, let container = textContainer else { return super.intrinsicContentSize }
        return NSSize(width: NSView.noIntrinsicMetric,
                      height: NoteText.height(layout: layout, container: container,
                                              font: styler.baseFont, minLines: minLines))
    }

    // MARK: Keys

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isFocused, let command = Self.listCommand(for: event) {
            perform(command)
            return true
        }
        if isFocused, Self.isCommandReturn(event) {
            moveToNextInputLineOrField()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// `⌘↩` — to the next input line of this field (STYLEGUIDE §4.4), or, when the field has
    /// none left, on to the next field: what `Tab` did before it became indentation.
    func moveToNextInputLineOrField() {
        if let target = ListEditing.nextInputLine(text: string, caret: selectedRange().location) {
            setSelectedRange(NSRange(location: target, length: 0))
            scrollRangeToVisible(selectedRange())
        } else if let onAdvance {
            onAdvance()
        } else {
            window?.selectNextKeyView(self)
        }
    }

    static func isCommandReturn(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command, let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first
        else { return false }
        return scalar == "\r" || scalar == "\n" || scalar == "\u{3}"
    }

    public override func keyDown(with event: NSEvent) {
        if !hasMarkedText(), let command = Self.listCommand(for: event) {
            perform(command)
            return
        }
        super.keyDown(with: event)
    }

    public override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        if let edit = ListEditing.newline(text: string, selection: selection.location..<NSMaxRange(selection)) {
            apply(edit)
        } else {
            super.insertNewline(sender)
        }
    }

    /// `Tab` indents the caret's line(s), `⇧Tab` outdents them (2026-09-25). Moving on to the
    /// next field is `⌘↩` once the field has no input line left.
    public override func insertTab(_ sender: Any?) { perform(.indent) }
    public override func insertBacktab(_ sender: Any?) { perform(.outdent) }

    private func perform(_ command: ListEditCommand) {
        let selection = selectedRange()
        guard let edit = ListEditing.edit(command, text: string,
                                          selection: selection.location..<NSMaxRange(selection))
        else { return }
        apply(edit)
    }

    /// Applies an edit through the text system: one undo step, the binding updates as for typing.
    private func apply(_ edit: ListEdit, select: Bool = true) {
        let range = NSRange(location: edit.range.lowerBound, length: edit.range.count)
        let previous = selectedRange()
        guard shouldChangeText(in: range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: edit.replacement)
        didChangeText()
        setSelectedRange(select
            ? NSRange(location: edit.selection.lowerBound, length: edit.selection.count)
            : previous)
    }

    static func listCommand(for event: NSEvent) -> ListEditCommand? {
        guard let key = event.charactersIgnoringModifiers?.lowercased().first else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return ListEditShortcut.command(for: ListEditShortcut(
            key: key,
            command: flags.contains(.command),
            option: flags.contains(.option),
            shift: flags.contains(.shift),
            control: flags.contains(.control)))
    }

    // MARK: Checkboxes

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let origin = textContainerOrigin
        if let layout = layoutManager, let container = textContainer,
           let box = NoteText.checkbox(at: CGPoint(x: point.x - origin.x, y: point.y - origin.y),
                                       layout: layout, container: container, text: string),
           let edit = ListEditing.edit(.toggleCheckbox, text: string, selection: box.lowerBound..<box.lowerBound) {
            apply(edit, select: false)
            return
        }
        super.mouseDown(with: event)
    }

    // MARK: Placeholder

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        (placeholder as NSString).draw(
            at: textContainerOrigin,
            withAttributes: [.font: styler.baseFont, .foregroundColor: styler.placeholderColor])
    }
}

#else

// MARK: - iOS

/// See the macOS declaration: the same editor over `UITextView`. The list keys work with a
/// hardware keyboard; a tap on a box ticks it.
public struct NoteEditor: UIViewRepresentable {
    @Binding var text: String
    var prompt: String
    var font: NoteEditorFont
    var tone: NoteEditorTone
    var minLines: Int
    var onAdvance: (() -> Void)?

    public init(text: Binding<String>, prompt: String = "", font: NoteEditorFont = .body,
                tone: NoteEditorTone = .ink, minLines: Int = 1) {
        self._text = text
        self.prompt = prompt
        self.font = font
        self.tone = tone
        self.minLines = minLines
    }

    /// What `⌘↩` does once the field has no input line left (STYLEGUIDE §4.4): the owner moves
    /// its SwiftUI focus on — `focus = .what`, or `nil` to give the keys back to the card. Without
    /// it the field asks AppKit for the next key view, which SwiftUI's hosting does not reliably
    /// answer (the inbox card's `Why?` never reached `What?` that way, 2026-09-25).
    public func onAdvance(_ action: @escaping () -> Void) -> NoteEditor {
        var copy = self
        copy.onAdvance = action
        return copy
    }

    public func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    public func makeUIView(context: Context) -> NoteTextView {
        let stack = NoteText.makeStack()
        let view = NoteTextView(frame: .zero, textContainer: stack.container)
        view.storage = stack.storage
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.adjustsFontForContentSizeCategory = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.text = text
        configure(view)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        return view
    }

    public func updateUIView(_ view: NoteTextView, context: Context) {
        context.coordinator.text = $text
        configure(view)
        if view.text != text, view.markedTextRange == nil {
            let caret = NoteText.caret(view.selectedRange.location, from: view.text, to: text)
            view.text = text
            view.selectedRange = NSRange(location: caret, length: 0)
        }
        view.restyle()
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView view: NoteTextView,
                             context: Context) -> CGSize? {
        let previous = view.textContainer.size
        let size = NoteText.fittingSize(proposedWidth: proposal.width) { width in
            view.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
            return NoteText.height(layout: view.layoutManager, container: view.textContainer,
                                   font: view.styler.baseFont, minLines: minLines)
        }
        // `widthTracksTextView` follows the frame once there is one; until then keep the probe.
        view.textContainer.size = view.bounds.width > 0
            ? CGSize(width: view.bounds.width, height: .greatestFiniteMagnitude) : previous
        return size
    }

    private func configure(_ view: NoteTextView) {
        view.styler = NoteStyler(font: font, tone: tone)
        view.placeholder = prompt
        view.onAdvance = onAdvance
    }

    @MainActor
    public final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        public func textViewDidChange(_ view: UITextView) {
            if text.wrappedValue != view.text { text.wrappedValue = view.text }
            (view as? NoteTextView)?.restyle()
            view.invalidateIntrinsicContentSize()
        }

        public func textViewDidChangeSelection(_ view: UITextView) { (view as? NoteTextView)?.restyle() }
        public func textViewDidBeginEditing(_ view: UITextView) { (view as? NoteTextView)?.restyle(force: true) }
        public func textViewDidEndEditing(_ view: UITextView) { (view as? NoteTextView)?.restyle(force: true) }

        public func textView(_ view: UITextView, shouldChangeTextIn range: NSRange,
                             replacementText replacement: String) -> Bool {
            guard replacement == "\n", let note = view as? NoteTextView,
                  let edit = ListEditing.newline(text: view.text, selection: range.location..<NSMaxRange(range))
            else { return true }
            note.apply(edit)
            return false
        }

        public func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let view = recognizer.view as? NoteTextView else { return false }
            return view.checkbox(at: recognizer.location(in: view)) != nil
        }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? NoteTextView,
                  let box = view.checkbox(at: recognizer.location(in: view)),
                  let edit = ListEditing.edit(.toggleCheckbox, text: view.text,
                                              selection: box.lowerBound..<box.lowerBound)
            else { return }
            view.apply(edit, select: false)
        }
    }
}

public final class NoteTextView: UITextView {
    var styler = NoteStyler(font: .body, tone: .ink)
    /// Keeps the TextKit stack alive (see `NoteText.makeStack`).
    var storage: NSTextStorage?
    var placeholder = "" { didSet { if placeholder != oldValue { setNeedsDisplay() } } }
    /// `⌘↩` with no input line left (see `NoteEditor.onAdvance`).
    var onAdvance: (() -> Void)?
    private var isRestyling = false
    private var lastStyle: (text: String, selection: NSRange?)?

    func restyle(force: Bool = false) {
        guard !isRestyling, markedTextRange == nil else { return }
        let selection = isFirstResponder ? selectedRange : nil
        if !force, let last = lastStyle, last.text == text, last.selection == selection { return }
        isRestyling = true
        let kept = selectedRange
        styler.apply(to: textStorage, selection: selection)
        typingAttributes = styler.baseAttributes
        selectedRange = kept
        lastStyle = (text, selection)
        isRestyling = false
        setNeedsDisplay()
        invalidateIntrinsicContentSize()
    }

    func checkbox(at point: CGPoint) -> Range<Int>? {
        NoteText.checkbox(at: CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top),
                          layout: layoutManager, container: textContainer, text: text)
    }

    func apply(_ edit: ListEdit, select: Bool = true) {
        let previous = selectedRange
        guard let start = position(from: beginningOfDocument, offset: edit.range.lowerBound),
              let end = position(from: beginningOfDocument, offset: edit.range.upperBound),
              let range = textRange(from: start, to: end) else { return }
        replace(range, withText: edit.replacement)
        selectedRange = select
            ? NSRange(location: edit.selection.lowerBound, length: edit.selection.count)
            : previous
    }

    public override var keyCommands: [UIKeyCommand]? {
        // Hardware keyboard: Tab / ⇧Tab indent and outdent, ⌘↩ jumps to the next input line
        // or, with none left, calls `onAdvance` (there is no key-view loop to fall back on).
        let tab = UIKeyCommand(title: "", action: #selector(listCommand(_:)), input: "\t",
                               modifierFlags: [], propertyList: ListEditCommand.indent.rawValue)
        let backtab = UIKeyCommand(title: "", action: #selector(listCommand(_:)), input: "\t",
                                   modifierFlags: .shift, propertyList: ListEditCommand.outdent.rawValue)
        let next = UIKeyCommand(title: "", action: #selector(nextInputLine(_:)), input: "\r",
                                modifierFlags: .command)
        for key in [tab, backtab, next] { key.wantsPriorityOverSystemBehavior = true }
        return [tab, backtab, next] + ListEditShortcut.table.map { shortcut, command in
            var flags: UIKeyModifierFlags = []
            if shortcut.command { flags.insert(.command) }
            if shortcut.option { flags.insert(.alternate) }
            if shortcut.shift { flags.insert(.shift) }
            if shortcut.control { flags.insert(.control) }
            let key = UIKeyCommand(title: "", action: #selector(listCommand(_:)), input: String(shortcut.key),
                                   modifierFlags: flags, propertyList: command.rawValue)
            key.wantsPriorityOverSystemBehavior = true
            return key
        }
    }

    @objc private func nextInputLine(_ sender: UIKeyCommand) {
        guard let target = ListEditing.nextInputLine(text: text, caret: selectedRange.location) else {
            onAdvance?()
            return
        }
        selectedRange = NSRange(location: target, length: 0)
        scrollRangeToVisible(selectedRange)
    }

    @objc private func listCommand(_ sender: UIKeyCommand) {
        guard let raw = sender.propertyList as? String, let command = ListEditCommand(rawValue: raw),
              let edit = ListEditing.edit(command, text: text,
                                          selection: selectedRange.location..<NSMaxRange(selectedRange))
        else { return }
        apply(edit)
    }

    public override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard text.isEmpty, !placeholder.isEmpty else { return }
        (placeholder as NSString).draw(
            at: CGPoint(x: textContainerInset.left, y: textContainerInset.top),
            withAttributes: [.font: styler.baseFont, .foregroundColor: styler.placeholderColor])
    }
}
#endif

// MARK: - Read-only

/// Note content shown read-only (the review deck's `CollapsibleText`), rendered as the editor
/// shows it off the caret line (STYLEGUIDE §4.4). Font and colour come from the environment.
public enum MarkdownText {
    public static func attributed(_ source: String) -> AttributedString {
        let (text, runs) = MarkdownRendering.display(source)
        var result = AttributedString(text)
        let utf16 = Array(text.utf16)
        for run in runs {
            // Runs are UTF-16 offsets; step through scalars so a grapheme cluster that spans a
            // run boundary cannot shift the rest.
            let lower = String(decoding: utf16[0..<run.range.lowerBound], as: UTF16.self).unicodeScalars.count
            let length = String(decoding: utf16[run.range], as: UTF16.self).unicodeScalars.count
            let start = result.unicodeScalars.index(result.startIndex, offsetBy: lower)
            let end = result.unicodeScalars.index(start, offsetBy: length)
            let a = run.attributes
            var intent: InlinePresentationIntent = []
            if a.bold || a.heading > 0 { intent.insert(.stronglyEmphasized) }
            if a.italic { intent.insert(.emphasized) }
            if a.code { intent.insert(.code) }
            if a.strike { intent.insert(.strikethrough) }
            if !intent.isEmpty { result[start..<end].inlinePresentationIntent = intent }
            if a.muted { result[start..<end].foregroundColor = Color.textSecondary }
            if a.link { result[start..<end].foregroundColor = Color.gtdAccent }
            if a.highlight { result[start..<end].backgroundColor = Color.accentWash }
        }
        return result
    }
}
#endif
