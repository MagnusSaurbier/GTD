# T50 — The three missing Mac `⌘` shortcuts

**Follow-up from T41 (traceability gap: E3, STYLEGUIDE §4.5)**

**Scope note (2026-09-21).** This brief is about the **fixed `⌘` shortcuts** of STYLEGUIDE §4.5 and
nothing else. The single-key commands of inbox processing (§3.6) and the review deck (§3.10) are a
separate, *finished* thing: they are rebindable per device through `GTDAppCore.KeyBindings` and
Settings › Keyboard (N7/R-10), and `Esc`, `Tab`, `⌘Z` and `⌘↩` are deliberately not rebindable.
Do not touch that table here.

## Model recommendation

**Difficulty:** Medium · **Recommended model:** Sonnet at high effort

The work is small and well-specified, but it crosses four feature targets and the app shell, and
it is about focus — the one part of SwiftUI where guessing does not work. Every file involved now
compiles on this Mac, so the old "do not start before Gate 2" warning is spent; the live one is
simpler: **try each shortcut in the running app before calling it done.** A focus system you
cannot try is a focus system you cannot write.

## The gap

STYLEGUIDE §4.5 promises a complete Mac keyboard map, and "all shortcuts also appear in the menu
bar (stock `Commands`)". These are in place: `⌘N` capture, `⌘1…⌘7` sidebar, `⌘F` search (but see
T51), `⌘Z` undo, `⌘I` process inbox, `⌘,` settings.

These are **not**:

| Shortcut | Action |
| --- | --- |
| `⌘⏎` | mark the focused action done |
| `⌘⇧W` | set the focused action to waiting (opens `WaitingInfoSheet`, W1) |
| `Space` | toggle the focused chip or checkbox |

**`⌘⇧N` / `⌘⇧S`** (move to Next / **Someday** — one "not now" tier since A3) shipped with the
inbox rework (`FeatureOverview/OverviewCommands.swift`): they read `OverviewNavigation.openAction` — the note
the detail column shows, already promoted by the Mac list's own `selection:` (M2) — rather than a
new focus concept, exactly as deliverable 1 below suggested. They go through `AppModel.perform`,
so a cap or `missingFields` refusal reaches the shell's alert. The remaining three still act on
**the focused row**, and no feature view exposes a focus target the shell can reach for them —
which is why T40 left them out and T41 declined to add them blind (T40 decision #2, in
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
2. **The remaining three commands in the menu bar** (`⌘⏎`, `⌘⇧W`, `Space`), in the stock
   `Commands` groups, disabled (greyed, not hidden) when nothing is focused — same shape as the
   `⌘⇧N`/`⌘⇧S` pair already there. `⌘⇧W` opens the existing `WaitingInfoSheet`; it never sets
   `waiting` without a confirmed **follow-up date** — which is the only thing W1 requires since
   D39. **Who is optional**, and an empty who must write no `waitingFor:` line.
3. **`Space` on a focused chip / checkbox.** If Full Keyboard Access already gives this for free
   on a `Button`, verify it and write that down instead of adding code.
4. A refused command surfaces through `AppModel.perform` exactly as the row actions do — never a
   silent no-op (T41 bug #6). The refusals to expect are `nextCapReached` and, since R-3,
   `missingFields`; a *deferred* Next item is no longer a refusal at all (R-2 reversed D15).
5. `docs/MANUAL_TEST.md` §8.1 ("Keyboard only"): extend it to cover the new shortcuts.

## Acceptance

- Every shortcut in STYLEGUIDE §4.5 works on the Mac **and** appears in the menu bar.
- `scripts/check.sh --app` green; the shortcuts tried by hand in the running app.
- Nothing in `docs/TRACEABILITY.md` still calls E3's keyboard row partial — update that row.

## Result

_(fill in when done)_
