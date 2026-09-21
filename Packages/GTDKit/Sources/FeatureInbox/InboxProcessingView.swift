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
            if session == nil { session = InboxSession(model: model) }
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
    @State private var dragTarget: CardTarget?
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
            .onChange(of: session.validation?.nonce) { _, _ in
                // R-3 — the first missing field takes focus; every one of them is marked on the
                // card itself (STYLEGUIDE §3.6).
                let missing = session.missingFields
                guard !missing.isEmpty else { return }
                focus = missing.contains(.why) ? .why : (missing.contains(.what) ? .what : nil)
                guard !reduceMotion else { return }
                withAnimation(Motion.standard) { shake += 1 }
            }
            .sensoryFeedback(.error, trigger: session.validation?.nonce)
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
            Text(CardTarget.keyLegend)
                .font(Typo.counter)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .accessibilityLabel(InboxCopy.keyLegendLabel)
                .accessibilityValue(CardTarget.keyLegend)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { press(.someday) }
        .onKeyPress(.rightArrow) { press(.next) }
        .onKeyPress(.downArrow) { press(.trash) }
        .onKeyPress(.escape) { quit() }
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
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: DragThresholds.axisLock)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                translation = DragResolver.lockedTranslation(dx: dx, dy: dy)
                dragTarget = DragResolver.target(dx: dx, dy: dy, cardSize: cardSize)
            }
            .onEnded { value in
                let target = DragResolver.target(
                    dx: value.translation.width,
                    dy: value.translation.height,
                    cardSize: cardSize)
                dragTarget = nil
                guard let target else {
                    withAnimation(reduceMotion ? Motion.reduced : Motion.cardReturn) {
                        translation = .zero
                    }
                    return
                }
                fly(to: target)
            }
    }

    /// The card flies out in the target's direction, then the next one springs up.
    private func fly(to target: CardTarget) {
        guard session.validate(for: target) else {
            withAnimation(reduceMotion ? Motion.reduced : Motion.cardReturn) { translation = .zero }
            return
        }
        withAnimation(reduceMotion ? Motion.reduced : Motion.cardExit) {
            translation = exitTranslation(for: target)
        }
        Task {
            await session.choose(target)
            translation = .zero
        }
    }

    private func exitTranslation(for target: CardTarget) -> CGSize {
        guard let direction = target.swipe else { return .zero }
        let width = max(cardSize.width, 320) * 1.5
        let height = max(cardSize.height, 480) * 1.5
        switch direction {
        case .right: return CGSize(width: width, height: 0)
        case .left: return CGSize(width: -width, height: 0)
        case .down: return CGSize(width: 0, height: height)
        }
    }

    /// Floating glass capsule above the home indicator: the four targets that have no swipe as
    /// labelled buttons, and `⋯` with the swipe targets for whoever cannot or will not
    /// swipe (one-handed use, Switch Control, a card taller than the screen).
    private var actionBar: some View {
        GlassActionBar {
            ForEach(CardTarget.buttonTargets) { target in
                Button {
                    Task { await session.choose(target) }
                } label: {
                    barLabel(target.shortTitle, symbol: target.symbol)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.ink)
                .accessibilityLabel(target.title)
            }
            Menu {
                ForEach(CardTarget.menuTargets) { target in
                    Button(role: target == .trash ? .destructive : nil) {
                        fly(to: target)
                    } label: {
                        Label(target.title, systemImage: target.symbol)
                    }
                }
            } label: {
                barLabel(InboxCopy.fileMenuLabel, symbol: InboxSymbols.more)
            }
            .foregroundStyle(Color.ink)
            .accessibilityLabel(InboxCopy.fileMenuLabel)
        }
        .padding(.bottom, Spacing.s)
    }

    /// Symbols differ in height; a fixed icon box keeps every caption on one baseline.
    private func barLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .frame(height: Spacing.xl)
            Text(title)
                .font(Typo.counter)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: Spacing.minHitTarget)
        .contentShape(Rectangle())
    }
    #endif

    // MARK: Keyboard (STYLEGUIDE §3.6, Mac)

    #if os(macOS)
    /// Letters, digits and the shifted digits `!@#$` (STYLEGUIDE §3.6).
    private static let keyCharacters: CharacterSet = CharacterSet.alphanumerics
        .union(.punctuationCharacters)
        .union(.symbols)

    private func press(_ target: CardTarget) -> KeyPress.Result {
        guard focus == nil else { return .ignored }
        Task { await session.choose(target) }
        return .handled
    }

    private func quit() -> KeyPress.Result {
        guard focus == nil else {
            focus = nil        // Esc first blurs the field, so the next Esc quits
            return .handled
        }
        onFinished()
        return .handled
    }

    private func handle(_ keyPress: KeyPress) -> KeyPress.Result {
        guard focus == nil, let character = keyPress.characters.first else { return .ignored }
        guard let resolved = KeyMap.resolve(
            character,
            shift: keyPress.modifiers.contains(.shift),
            command: keyPress.modifiers.contains(.command))
        else { return .ignored }
        switch resolved {
        case let .target(target):
            Task { await session.choose(target) }
        case let .context(index):
            guard index < session.contexts.count else { return .ignored }
            toggleContext(session.contexts[index])
        case let .time(bucket):
            session.draft.timeBucket = session.draft.timeBucket == bucket ? nil : bucket
        case .undo:
            Task { await session.undo() }
        case .quit:
            onFinished()
        }
        return .handled
    }

    private func toggleContext(_ context: String) {
        if let index = session.draft.contexts.firstIndex(of: context) {
            session.draft.contexts.remove(at: index)
        } else {
            session.draft.contexts.append(context)
        }
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
        case .fullText:
            FullTextSheet(session: session)
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
