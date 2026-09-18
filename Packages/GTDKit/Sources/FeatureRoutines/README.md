# FeatureRoutines

Routines: one step per screen, done/skip, resume from today's log (R1–R6).

**Owned by T24.** T00 created a compiling shell: the public root views with the exact signatures
from the task brief, plus the Linux-compilable model listed below. The visuals and behaviour are
T24's work; `docs/STYLEGUIDE.md` is binding and its §9 checklist is part of the gate.

## Public API

`RoutinesHomeView()`, `RoutineRunnerView(routine:onFinished:)`.
Linux-compilable: `RoutineRun` (resume index, progress text, logging, going back).

## Platform guards (ARCHITECTURE §5)

Views live in files wrapped entirely in `#if canImport(SwiftUI)`. The logic worth testing lives
in the Linux-compilable file(s) named above, so `swift test` covers it without Xcode. Every
SwiftUI file in this target was written without a compiler and is **unverified** — say so in your
Result until it has been built on a Mac.

## Testing

`cd Packages/GTDKit && swift test --filter FeatureRoutinesTests`
