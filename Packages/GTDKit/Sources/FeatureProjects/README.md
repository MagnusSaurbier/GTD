# FeatureProjects

Areas and projects: list, detail with inline steps, promotion and the "What's next?" flow (P1–P6).

**Owned by T22.** T00 created a compiling shell: the public root views with the exact signatures
from the task brief, plus the Linux-compilable model listed below. The visuals and behaviour are
T22's work; `docs/STYLEGUIDE.md` is binding and its §9 checklist is part of the gate.

## Public API

`ProjectsListView(onOpenProject:onOpenAction:)`, `ProjectDetailView(project:onOpenAction:)`,
`WhatsNextSheet(project:)`, `ConvertToProjectSheet(action:)`, `ProjectPicker(selection:)`.
Linux-compilable: `ProjectsListModel` (grouping by area, open steps, demotion count).

## Platform guards (ARCHITECTURE §5)

Views live in files wrapped entirely in `#if canImport(SwiftUI)`. The logic worth testing lives
in the Linux-compilable file(s) named above, so `swift test` covers it without Xcode. Every
SwiftUI file in this target was written without a compiler and is **unverified** — say so in your
Result until it has been built on a Mac.

## Testing

`cd Packages/GTDKit && swift test --filter FeatureProjectsTests`
