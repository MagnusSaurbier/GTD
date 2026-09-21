#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem

/// The full inbox-processing session (I1–I7): one card at a time, LIFO, forced order, exit only
/// by quitting. Swipes on iPhone, keys on Mac — the map itself lives in `CardTargets.swift`.
///
/// `FeatureReview` embeds this view for "inbox to zero" (§10.1).
public struct InboxProcessingView: View {
    private let onFinished: () -> Void
    private let showsChrome: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.keyBindings) private var keyBindings
    @State private var session: InboxSession?

    /// `showsChrome: false` is for a host that brings its own counter and exit (the weekly
    /// review's sweep): the toolbar then keeps only Undo.
    public init(showsChrome: Bool = true, onFinished: @escaping () -> Void) {
        self.showsChrome = showsChrome
        self.onFinished = onFinished
    }

    public var body: some View {
        ZStack {
            Color.surfaceGrouped.ignoresSafeArea()
            if let session {
                InboxSessionView(session: session, showsChrome: showsChrome, onFinished: onFinished)
            }
        }
        .task {
            if session == nil { session = InboxSession(model: model, bindings: keyBindings) }
        }
        // A rebind in Settings › Keyboard reaches a running session at once (R-10).
        .onChange(of: keyBindings) { _, bindings in
            session?.keyBindings = bindings
        }
        // A capture made on another device (or by the Shortcut) joins the queue (I7).
        .onChange(of: model.snapshot.inbox.count) { _, _ in
            session?.refresh()
        }
    }
}

/// Home-screen entry point: shows the queue count and starts a session (I1).
public struct InboxStartButton: View {
    private let action: () -> Void
    @Environment(AppModel.self) private var model

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(
                "\(Copy.processInbox) (\(Rules.inboxQueue(model.snapshot).count))",
                systemImage: Symbols.inbox)
        }
        .disabled(Rules.inboxQueue(model.snapshot).isEmpty)
    }
}

// MARK: - The session

struct InboxSessionView: View {
    @Bindable var session: InboxSession
    var showsChrome = true
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: CardField?

    @State private var translation: CGSize = .zero
    @State private var dragTarget: InboxExit?
    @State private var cardSize: CGSize = .zero
    @State private var shake: CGFloat = 0
    @State private var toast: String?
    @State private var toastTick = 0

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.surfaceGrouped)
            .toolbar { toolbarContent }
            .sheet(item: $session.sheet) { sheet in
                sheetContent(sheet)
                #if os(iOS)
                    .presentationDetents(sheet == .cap ? [.large] : [.medium, .large])
                #endif
            }
            #if os(macOS)
            // iPhone shows the toast in the bottom inset, above the action bar (`bottomInset`).
            .overlay(alignment: .bottom) { toastOverlay.padding(.bottom, Spacing.xxl) }
            #endif
            .overlay { hintOverlay }
            .onChange(of: session.processed) { old, new in
                guard new > old, let label = session.undoToastLabel else { return }
                toast = label
                toastTick += 1
            }
            .task(id: toastTick) {
                guard toast != nil else { return }
                try? await Task.sleep(
                    nanoseconds: UInt64(MotionTiming.toastDuration * 1_000_000_000))
                toast = nil
            }
            .onChange(of: session.shakeTrigger) { old, new in
                // R-3 — the first missing text field takes focus; every missing field is marked
                // on the card itself (STYLEGUIDE §3.6). The session decides which one.
                guard new > old else { return }
                switch session.focusRequest {
                case .why: focus = .why
                case .what: focus = .what
                default: break
                }
                session.consumeFocusRequest()
                guard !reduceMotion else { return }
                withAnimation(Motion.standard) { shake += 1 }
            }
            .onChange(of: focus) { _, field in
                session.isFieldFocused = field != nil
            }
            // "focus goes to `Why?` on the action card, stays unfocused on the keep card"
            // (STYLEGUIDE §3.6) — only when *opening* from step 1, not on every step change (a
            // collapse-and-reopen keeps whatever the user was doing).
            .onChange(of: session.step) { old, new in
                if old == .step1, new == .actionCard { focus = .why }
            }
            .sensoryFeedback(.error, trigger: session.shakeTrigger)
            .sensoryFeedback(.impact(weight: .medium), trigger: dragTarget)
    }

    @ViewBuilder private var content: some View {
        if session.isFinished {
            InboxZeroView(session: session, onFinished: onFinished)
        } else {
            #if os(iOS)
            phoneContent
            #else
            macContent
            #endif
        }
    }

    #if os(iOS)
    /// The card sits in a `ScrollView`, so the software keyboard can shrink the viewport without
    /// squeezing the card: the fields keep their height, the focused one is scrolled into view,
    /// and dragging the content down takes the keyboard with it. With no field focused and a
    /// card that fits, scrolling is off, so the downward swipe (Trash) stays the card's.
    /// A card taller than the screen scrolls instead; `⋯` in the action bar still files it.
    private var phoneContent: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    card
                        .padding(.horizontal, Spacing.screenMargin)
                        .padding(.vertical, Spacing.l)
                        // Centred while it fits, top-aligned and scrolling once it does not.
                        .frame(maxWidth: .infinity, minHeight: viewport.size.height)
                        .contentShape(Rectangle())
                        // A tap next to a field puts the keyboard away.
                        .onTapGesture { focus = nil }
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
                .scrollClipDisabled()
                .scrollDisabled(
                    focus == nil && cardSize.height + 2 * Spacing.l <= viewport.size.height)
                .onChange(of: focus) { _, field in
                    reveal(field, with: proxy)
                }
                // The keyboard arrives after the focus change; reveal again once it took its
                // space. Only when the viewport **shrinks**: while it grows the user is dragging
                // the keyboard away, and a programmatic scroll would fight that drag.
                .onChange(of: viewport.size.height) { old, new in
                    guard new < old else { return }
                    reveal(focus, with: proxy)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { bottomInset }
    }

    private func reveal(_ field: CardField?, with proxy: ScrollViewProxy) {
        guard let field else { return }
        withAnimation(reduceMotion ? Motion.reduced : Motion.standard) {
            proxy.scrollTo(field, anchor: .center)
        }
    }

    /// Toast above the action bar, in the same inset, so the two can never overlap. While a
    /// field has the keyboard the inset rides on top of it and the bar gives way to the
    /// keyboard's `Done`.
    private var bottomInset: some View {
        VStack(spacing: Spacing.s) {
            toastOverlay
            if focus == nil {
                actionBar
            } else {
                keyboardBar
            }
        }
        .animation(reduceMotion ? Motion.reduced : Motion.standard, value: toast)
    }

    /// `Why?` and `What?` are multi-line, so Return is a newline: this is the way out of the
    /// keyboard. With the focus gone the swipes and the action bar work again. A view in the
    /// bottom inset rather than `ToolbarItemGroup(placement: .keyboard)`, which did not render
    /// in the full-screen cover `PhoneShell` presents the session in (iOS 26.5 simulator).
    private var keyboardBar: some View {
        HStack {
            Spacer(minLength: 0)
            Button(Copy.done) { focus = nil }
                .buttonStyle(.glass)
                .accessibilityIdentifier("inbox.keyboardDone")
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.bottom, Spacing.s)
    }
    #endif

    #if os(macOS)
    private var macContent: some View {
        VStack(spacing: Spacing.l) {
            Spacer(minLength: 0)
            // A macOS sheet has no title bar, so the `.principal` toolbar item below never
            // renders there (seen on the first real run); the counter sits above the card.
            Text(session.counter)
                .font(Typo.counter)
                .foregroundStyle(Color.textSecondary)
            card
            // Mac also gets a row of stock buttons under the card (STYLEGUIDE §3.6) — the
            // keyboard is the primary path, but every action stays reachable with the mouse.
            actionBar
            // The legend always renders the current bindings, per step (STYLEGUIDE §3.6, R-10).
            Text(session.legendString)
                .font(Typo.counter)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .accessibilityLabel(InboxCopy.keyLegendLabel)
                .accessibilityValue(session.legendString)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { press(.arrowLeft) }
        .onKeyPress(.rightArrow) { press(.arrowRight) }
        .onKeyPress(.escape) { escape() }
        .onKeyPress(characters: Self.keyCharacters, phases: .down) {
            handle($0)
        }
    }
    #endif

    // MARK: Card stack

    private var card: some View {
        InboxCardView(
            session: session,
            focus: $focus,
            dragTarget: dragTarget,
            translation: translation,
            shake: shake)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { cardSize = proxy.size }
                        .onChange(of: proxy.size) { _, newValue in cardSize = newValue }
                }
            }
            // The next card peeks 8 pt below, scaled down, with no content: forced order,
            // the peek only signals "more" (STYLEGUIDE §3.5).
            .background(alignment: .center) {
                if session.queue.count > 1 {
                    Radius.cardShape
                        .fill(Color.surfaceCard)
                        .cardElevation()
                        .scaleEffect(0.96)
                        .offset(y: Spacing.s)
                }
            }
            #if os(iOS)
            .gesture(
                dragGesture,
                including: focus == nil ? GestureMask.all : GestureMask.subviews)
            #endif
    }

    #if os(iOS)
    /// The drag map is the session's `dragContext`: no drag at all on step 1, only `↓` on the
    /// Knowledge / List card, nothing at all while a field has the keyboard (STYLEGUIDE §3.6).
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: DragThresholds.axisLock)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let context = session.dragContext
                translation = DragResolver.lockedTranslation(dx: dx, dy: dy, in: context)
                switch DragResolver.outcome(
                    dx: dx, dy: dy, cardSize: cardSize, in: context
                ) {
                case let .file(exit): dragTarget = exit
                case .collapse: dragTarget = .collapse
                case nil: dragTarget = nil
                }
            }
            .onEnded { value in
                let outcome = DragResolver.outcome(
                    dx: value.translation.width,
                    dy: value.translation.height,
                    cardSize: cardSize,
                    in: session.dragContext)
                dragTarget = nil
                switch outcome {
                case let .file(exit):
                    fly(to: exit)
                case .collapse:
                    withAnimation(reduceMotion ? Motion.reduced : Motion.standard) {
                        translation = .zero
                        session.collapse()
                    }
                case nil:
                    withAnimation(reduceMotion ? Motion.reduced : Motion.cardReturn) {
                        translation = .zero
                    }
                }
            }
    }
    #endif

    /// The card flies out in the exit's direction, then the next one springs up. A refusal
    /// (missing fields, the cap) springs it back — the session has already marked the card.
    private func fly(to exit: InboxExit) {
        let processedBefore = session.processed
        withAnimation(reduceMotion ? Motion.reduced : Motion.cardExit) {
            translation = exitTranslation(for: exit)
        }
        Task {
            await session.take(exit)
            if session.processed == processedBefore {
                withAnimation(reduceMotion ? Motion.reduced : Motion.cardReturn) {
                    translation = .zero
                }
            } else {
                translation = .zero
            }
        }
    }

    private func exitTranslation(for exit: InboxExit) -> CGSize {
        let width = max(cardSize.width, 320) * 1.5
        switch exit {
        case .next: return CGSize(width: width, height: 0)
        case .someday: return CGSize(width: -width, height: 0)
        default: return .zero
        }
    }

    /// The bottom bar of the current step (STYLEGUIDE §3.6, decision #12) — `DesignSystem`'s
    /// three real bars, wired straight to `session.take(_:)`; the view invents no labels, icons
    /// or ordering of its own. The bar cross-fades between steps (STYLEGUIDE §3.6 "the bar swaps
    /// with a cross-fade").
    @ViewBuilder private var actionBar: some View {
        Group {
            switch session.step {
            case .step1: stepOneBar
            case .actionCard: openedActionBar
            case .keepCard: keepNavbar
            }
        }
        .id(session.step)
        .transition(.opacity)
        .animation(reduceMotion ? Motion.reduced : Motion.standard, value: session.step)
    }

    /// Three equal, neutral buttons — none accent-filled, because the app does not know the
    /// right answer (§1.2). `Defer to review` sits as a quiet text button: centred between card
    /// and bar on iPhone, beside the three buttons on Mac (STYLEGUIDE §3.6).
    private var stepOneBar: some View {
        #if os(macOS)
        HStack(spacing: Spacing.m) {
            StepOneBar(
                onAction: { Task { await session.take(.openAction) } },
                onKnowledgeOrList: { Task { await session.take(.openKeep) } },
                onTrash: { Task { await session.take(.trash) } })
            deferToReviewButton
        }
        #else
        VStack(spacing: Spacing.s) {
            deferToReviewButton
            StepOneBar(
                onAction: { Task { await session.take(.openAction) } },
                onKnowledgeOrList: { Task { await session.take(.openKeep) } },
                onTrash: { Task { await session.take(.trash) } })
        }
        .padding(.bottom, Spacing.s)
        #endif
    }

    private var deferToReviewButton: some View {
        Button(Copy.deferToReview) { Task { await session.take(.deferToReview) } }
            .buttonStyle(.plain)
            .font(Typo.meta)
            .foregroundStyle(Color.textSecondary)
    }

    /// `Waiting` and `Done` as labelled buttons, `⋯` ("File to") repeating the two swipe exits
    /// so a card taller than the screen can still be filed; a `Done` bar while a field has the
    /// keyboard (STYLEGUIDE §3.6).
    private var openedActionBar: some View {
        ActionCardBar(
            isFieldFocused: focus != nil,
            onWaiting: { Task { await session.take(.waiting) } },
            onDone: { Task { await session.take(.done) } },
            onFileToNext: { fly(to: .next) },
            onFileToSomeday: { fly(to: .someday) },
            onDismissKeyboard: { focus = nil })
            .padding(.bottom, Spacing.s)
    }

    /// The fixed-slot navbar: `Knowledge`, the favourite lists in Settings order, then `More…`.
    /// A list button files the card at once (I4b).
    private var keepNavbar: some View {
        KnowledgeListNavbar(
            favourites: session.favouriteListNames,
            platform: session.platform,
            onKnowledge: { Task { await session.take(.knowledge) } },
            onList: { name in Task { await session.take(.list(name)) } },
            onMore: { Task { await session.take(.more) } })
            .padding(.bottom, Spacing.s)
    }

    // MARK: Keyboard (STYLEGUIDE §3.6, Mac)

    #if os(macOS)
    /// Letters, digits and the shifted digits `!@#$` (STYLEGUIDE §3.6).
    private static let keyCharacters: CharacterSet = CharacterSet.alphanumerics
        .union(.punctuationCharacters)
        .union(.symbols)

    private func press(_ stroke: KeyStroke) -> KeyPress.Result {
        guard focus == nil else { return .ignored }
        guard let key = KeyMap.resolve(stroke: stroke, step: session.step, bindings: session.keyBindings)
        else { return .ignored }
        perform(key)
        return .handled
    }

    /// Filing animates the card out in the key's direction (STYLEGUIDE §3.6, Mac): `Next`/
    /// `Someday` fly the same way a swipe would, whichever key they are bound to; everything
    /// else — Waiting, Done, Trash, Knowledge, a list slot — has no direction and just runs.
    private func perform(_ key: InboxKey) {
        if case let .command(command) = key, command == .cardNext {
            fly(to: .next)
        } else if case let .command(command) = key, command == .cardSomeday {
            fly(to: .someday)
        } else {
            Task { await session.handle(key) }
        }
    }

    /// `Esc` is a ladder (STYLEGUIDE §3.6): focused field → blur; opened card → collapse;
    /// step 1 → quit. The session owns the middle rung; the view owns the two ends.
    private func escape() -> KeyPress.Result {
        session.isFieldFocused = focus != nil
        switch session.escape() {
        case .blurField: focus = nil
        case .collapsed: break
        case .quit: onFinished()
        }
        return .handled
    }

    private func handle(_ keyPress: KeyPress) -> KeyPress.Result {
        guard focus == nil, let character = keyPress.characters.first else { return .ignored }
        // Everything rebindable resolves through `KeyBindings` for the **current step** (R-10).
        guard let key = KeyMap.resolve(
            character,
            shift: keyPress.modifiers.contains(.shift),
            command: keyPress.modifiers.contains(.command),
            step: session.step,
            bindings: session.keyBindings)
        else { return .ignored }
        perform(key)
        return .handled
    }
    #endif

    // MARK: Chrome

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if showsChrome {
            ToolbarItem(placement: .principal) {
                Text(session.counter)
                    .font(Typo.counter)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        ToolbarItem(placement: .cancellationAction) {
            Button {
                Task { await session.undo() }
            } label: {
                Label(Copy.undo, systemImage: Symbols.undo)
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!session.canUndo)
        }
        if showsChrome {
            ToolbarItem(placement: .confirmationAction) {
                // `Close`, not `Done`: on this screen `Done` files a card (STYLEGUIDE §3.6).
                Button(Copy.close, action: onFinished)
            }
        }
    }

    @ViewBuilder private func sheetContent(_ sheet: InboxSession.Sheet) -> some View {
        switch sheet {
        case .knowledge:
            KnowledgeSheet(session: session)
        case .project:
            ProjectSheet(session: session)
        case .waiting:
            WaitingInfoSheet(today: session.today) { info in
                Task { await session.confirmWaiting(info) }
            }
        case .deferToReview:
            DeferToReviewSheet(session: session)
        case .cap:
            CapSheet(session: session)
        case .more:
            MoreListsSheet(session: session)
        }
    }

    @ViewBuilder private var toastOverlay: some View {
        if let toast {
            UndoToast(label: toast) {
                self.toast = nil
                Task { await session.undo() }
            }
            .transition(.opacity)
        }
    }

    /// One-time hint showing the four directions (STYLEGUIDE §3.6).
    @ViewBuilder private var hintOverlay: some View {
        #if os(iOS)
        if session.isSwipeHintVisible, !session.isFinished {
            VStack(spacing: Spacing.m) {
                Text(InboxCopy.hintTitle).font(Typo.sectionHeader)
                Text(InboxCopy.hintBody)
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                Button(InboxCopy.hintDismiss) { session.dismissSwipeHint() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(Spacing.cardPadding)
            .background(Color.surfaceCard, in: Radius.tileShape)
            .cardElevation()
            .padding(Spacing.screenMargin)
        }
        #endif
    }
}

// MARK: - Inbox zero (STYLEGUIDE §5, reward moment)

struct InboxZeroView: View {
    let session: InboxSession
    let onFinished: () -> Void

    /// STYLEGUIDE §5.1's moment comes from `DesignSystem.RewardMoment` rather than being drawn
    /// again here (T41): that is where the bouncing tray, the `signalDone` check badge and the
    /// single `.success` haptic on appear are defined, and §5 allows exactly two such moments,
    /// so there must be exactly one implementation. Only the per-target breakdown — which is
    /// inbox vocabulary, not a design-system concept — stays local.
    var body: some View {
        VStack(spacing: Spacing.l) {
            RewardMoment.inboxZero(
                processed: session.processed, minutes: session.elapsedMinutes)

            let breakdown = InboxCopy.targetBreakdown(session.summaryCounts)
            if !breakdown.isEmpty {
                Text(breakdown)
                    .font(Typo.counter)
                    .foregroundStyle(Color.textSecondary)
            }

            Button(Copy.done, action: onFinished)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
