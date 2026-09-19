# T50 — The five missing Mac shortcuts

**Follow-up from T41 (traceability gap: E3, STYLEGUIDE §4.5) · after Gate 2**

## Model recommendation

**Difficulty:** Medium · **Recommended model:** Sonnet at high effort

The work is small and well-specified, but it crosses four feature targets and the app shell, and
it is about focus — the one part of SwiftUI where guessing does not work. **Do not start this
before `scripts/check.sh --app` has been green once** and the app has run: every file involved is
one no agent has ever compiled, and a focus system you cannot try is a focus system you cannot
write.

## The gap

STYLEGUIDE §4.5 promises a complete Mac keyboard map, and "all shortcuts also appear in the menu
bar (stock `Commands`)". These are in place: `⌘N` capture, `⌘1…⌘7` sidebar, `⌘F` search (but see
T51), `⌘Z` undo, `⌘I` process inbox, `⌘,` settings.

These are **not**:

| Shortcut | Action |
| --- | --- |
| `⌘⏎` | mark the focused action done |
| `⌘⇧N` / `⌘⇧B` / `⌘⇧M` | move the focused action to Next / Backlog / Maybe |
| `⌘⇧W` | set the focused action to waiting (opens `WaitingInfoSheet`, W1) |
| `Space` | toggle the focused chip or checkbox |

They all act on **the focused row**, and no feature view exposes a focus target the shell can
reach — which is why T40 left them out and T41 declined to add them blind (T40 decision #2, in
`docs/history/build-out/ORCHESTRATOR-NOTES.md`).

## Owns

`FeatureOverview/OverviewCommands.swift`, `FeatureOverview/OverviewNavigation.swift`,
`FeatureNext/`, `FeatureWaiting/`, `FeatureProjects/` (focus targets only), `App/MacShell.swift`,
`DesignSystem` (if the focus value has to live there), `docs/STYLEGUIDE.md` is **read-only**.

## Deliverables

1. **One shared notion of "the focused action".** The shell already shares one
   `OverviewNavigation` between the window and its `Commands` (T40). Give it the selected/focused
   `NoteID` — lists already track a selection for the detail column, so prefer promoting that over
   inventing a second concept. If a list cannot supply one, say so in the Result rather than
   faking it.
2. **The four commands in the menu bar**, in the stock `Commands` groups, disabled (greyed, not
   hidden) when nothing is focused. `⌘⇧W` opens the existing `WaitingInfoSheet`; it never sets
   `waiting` without who + follow-up (W1).
3. **`Space` on a focused chip / checkbox.** If Full Keyboard Access already gives this for free
   on a `Button`, verify it and write that down instead of adding code.
4. A refused command (cap, defer × Next, waiting info) surfaces through `AppModel.perform`
   exactly as the row actions do — never a silent no-op (T41 bug #6).
5. `docs/MANUAL_TEST.md` §1: extend the keyboard row to cover the new shortcuts.

## Acceptance

- Every shortcut in STYLEGUIDE §4.5 works on the Mac **and** appears in the menu bar.
- `scripts/check.sh --app` green; the shortcuts tried by hand in the running app.
- Nothing in `docs/TRACEABILITY.md` still calls E3's keyboard row partial — update that row.

## Result

_(fill in when done)_
