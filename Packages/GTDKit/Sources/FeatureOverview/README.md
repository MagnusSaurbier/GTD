# FeatureOverview

The Mac shell's content router: sidebar, list, detail (E3).

**Owned by T25.** T00 created a compiling shell: the public root views with the exact signatures
from the task brief, plus the Linux-compilable model listed below. The visuals and behaviour are
T25's work; `docs/STYLEGUIDE.md` is binding and its §9 checklist is part of the gate.

## Public API

`OverviewView()`, `ActionListView(status:onOpen:)`, `ActionDetailView(action:)`, `SidebarItem`.
Linux-compilable: `SidebarItem` (titles, symbols, ⌘1…7, live counts).

## Platform guards (ARCHITECTURE §5)

Views live in files wrapped entirely in `#if canImport(SwiftUI)`. The logic worth testing lives
in the Linux-compilable file(s) named above, so `swift test` covers it without Xcode. Every
SwiftUI file in this target was written without a compiler and is **unverified** — say so in your
Result until it has been built on a Mac.

## Testing

`cd Packages/GTDKit && swift test --filter FeatureOverviewTests`
