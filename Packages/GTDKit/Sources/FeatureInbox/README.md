# FeatureInbox

Inbox processing: one card at a time, LIFO, forced order (I1–I7).

**Owned by T20.** T00 created a compiling shell: the public root views with the exact signatures
from the task brief, plus the Linux-compilable model listed below. The visuals and behaviour are
T20's work; `docs/STYLEGUIDE.md` is binding and its §9 checklist is part of the gate.

## Public API

`InboxProcessingView(onFinished:)`, `InboxStartButton(action:)`.
Linux-compilable: `InboxSession` (queue, counter, filing, undo) and `CardTargets.swift`
(`CardTarget`, `SwipeDirection`, `DragResolver` — the single definition of the swipe/key map,
ARCHITECTURE §6).

## Platform guards (ARCHITECTURE §5)

Views live in files wrapped entirely in `#if canImport(SwiftUI)`. The logic worth testing lives
in the Linux-compilable file(s) named above, so `swift test` covers it without Xcode. Every
SwiftUI file in this target was written without a compiler and is **unverified** — say so in your
Result until it has been built on a Mac.

## Testing

`cd Packages/GTDKit && swift test --filter FeatureInboxTests`
