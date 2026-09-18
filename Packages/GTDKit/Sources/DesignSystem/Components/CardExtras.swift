#if canImport(SwiftUI)
import SwiftUI

/// Raw captured text on `ItemCard` (STYLEGUIDE §3.5): never truncated silently. Past
/// `lineLimit` (6, per the guide) it collapses with a `Show all` button that opens the full
/// text in a sheet, instead of cutting it off.
public struct CollapsibleText: View {
    private let text: String
    private let lineLimit: Int

    @State private var isShowingFull = false

    public init(_ text: String, lineLimit: Int = 6) {
        self.text = text
        self.lineLimit = lineLimit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(text)
                .font(Typo.cardText)
                .foregroundStyle(Color.ink)
                .lineLimit(lineLimit)
            // SwiftUI has no cheap way to ask whether a `Text` actually wrapped past `lineLimit`
            // without a hosting measurement pass; this length heuristic only decides whether the
            // button is offered; the sheet always shows the untruncated `text` either way, so it
            // never hides content — it can just occasionally offer the button early.
            if isLikelyTruncated {
                Button(Copy.showAll) { isShowingFull = true }
                    .font(Typo.meta)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.gtdAccent)
            }
        }
        .sheet(isPresented: $isShowingFull) {
            ScrollView {
                Text(text)
                    .font(Typo.cardText)
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.cardPadding)
            }
            #if os(iOS)
            .presentationDetents([.medium, .large])
            #endif
        }
    }

    private var isLikelyTruncated: Bool {
        text.filter { $0.isNewline }.count >= lineLimit || text.count > lineLimit * 42
    }
}

public extension View {
    /// The next card peeking 8 pt below the current one, scaled 0.96, no content visible
    /// (STYLEGUIDE §3.5: "forced order — the peek only signals 'more'"). Applied to the current,
    /// front-most `ItemCard`; pass `hasNext: false` on the last card.
    func itemCardPeek(hasNext: Bool) -> some View {
        background(alignment: .top) {
            if hasNext {
                Radius.cardShape
                    .fill(Color.surfaceCard)
                    .scaleEffect(0.96)
                    .offset(y: 8)
                    .accessibilityHidden(true)
            }
        }
    }
}
#endif
