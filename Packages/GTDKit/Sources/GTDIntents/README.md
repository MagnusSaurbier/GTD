# GTDIntents

App Intents for capture and routines, plus the Shortcuts recipes (C1, C2, R3).

**Owned by T30.** T00 created a compiling shell: the public root views with the exact signatures
from the task brief, plus the Linux-compilable model listed below. The visuals and behaviour are
T30's work; `docs/STYLEGUIDE.md` is binding and its §9 checklist is part of the gate.

## Public API

`CaptureToInboxIntent`, `StartRoutineIntent`, `ProcessInboxIntent` (all inside `#if canImport(AppIntents)`).
Linux-compilable: `CaptureRequest` (normalisation + the write, testable with a fake writer),
`CaptureStamp` (the `yyyy-MM-dd HHmmss` file-name format), `CaptureError`.

## Platform guards (ARCHITECTURE §5)

Views live in files wrapped entirely in `#if canImport(SwiftUI)`. The logic worth testing lives
in the Linux-compilable file(s) named above, so `swift test` covers it without Xcode. Every
SwiftUI file in this target was written without a compiler and is **unverified** — say so in your
Result until it has been built on a Mac.

## Testing

`cd Packages/GTDKit && swift test --filter GTDIntentsTests`
