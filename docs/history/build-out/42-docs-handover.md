# T42 — Docs handover: from build-out to maintenance

**Wave 3 · last task · after T41**

## Model recommendation

**Difficulty:** Easy–medium (short, high leverage) · **Recommended model:** Opus

Little code, but it requires reading the whole repo and deciding what is *actually true* now
versus what the plan said. Every future agent session starts from the files this task rewrites,
so accuracy matters more than cost here.

## Goal

Leave the repo in a state where a fresh agent with no knowledge of the build-out can work in it
safely: instructions describe the code as built, nothing refers to a phase that is over.

## Owns

`CLAUDE.md`, `README.md`, `docs/ARCHITECTURE.md`, `docs/` (new files), `agent_task/` (archival),
module READMEs (corrections only), `scripts/check-docs.sh`.

## Deliverables

1. **`CLAUDE.md` → maintenance version.** Remove the `<!-- PHASE: build-out -->` marker, the phase
   paragraph and every *(build-out only)* section/line. Keep: where things are, verified commands,
   durable rules, "Keeping this file current" (drop the build-out row from the trigger table).
   Add what the build-out taught us that applies to every task (from the `## Result` sections:
   recurring gotchas, test conventions, how to run the app on simulator with `-useFixtures`,
   how to add a new feature module / a new `GTDCommand` end to end — as a 5–8 line checklist that
   points to `docs/`). Re-verify every command by running it.
2. **`docs/ARCHITECTURE.md` → as built.** Reconcile §2–§4 with the code: apply every
   "Contract changes" entry from all task docs; replace the long "frozen contracts" listing with
   a short description per module + pointer to the source files (the code is now the source of
   truth — duplicated signatures go stale). Rename the section accordingly. Keep §3 vault
   layout/formats, §6 decisions (add dates), §7 sync-safety rules, all verified against the code.
3. **`docs/CONTRIBUTING-AGENTS.md`** (or a section in ARCHITECTURE): how to make a typical change —
   add a field to the action schema (model → codec + round-trip test → reducer → fixtures → UI →
   migration note), add a command, add a feature target (Package.swift is no longer frozen: say so).
4. **Known issues & follow-ups:** collect open issues from all `## Result` sections and T41's
   traceability gaps into `docs/KNOWN_ISSUES.md`; link from README.
5. **Archive the task board:** `git mv agent_task docs/history/build-out` and add a one-paragraph
   `docs/history/build-out/README` note on top: "historical; do not follow these briefs;
   ownership rules and frozen-file rules no longer apply". Fix links.
6. **`README.md`:** current status, feature overview, setup, build/run, first-real-use checklist link, doc map.
7. **Module READMEs:** spot-check each against its public API; fix or delete untrue statements.
8. **`scripts/check-docs.sh`:** extend coverage to `docs/ARCHITECTURE.md` and module READMEs
   (backticked repo paths must exist; referenced scripts must be executable).
9. **Staleness test:** start a fresh agent (no context) with the prompt "Add a `energy` chip to
   actions — plan only, no code" and check that, from the docs alone, it finds the right modules,
   rules and commands. Record what it got wrong and fix the docs, not the agent.

## Acceptance

- `grep -ri "build-out\|agent_task\|frozen\|T[0-9][0-9]" CLAUDE.md README.md docs/ARCHITECTURE.md` returns nothing outside `docs/history/`.
- Every command in CLAUDE.md and README.md was run successfully during this task.
- `scripts/check.sh` passes, including the extended `check-docs.sh`.
- The staleness test result is written into `## Result`.

## Result

**Status: done.** `scripts/check.sh` exits 0 (851 Swift tests + 40 migration tests). The repo is
in its maintenance shape: no document describes a phase that is over, and the archive is clearly
marked as history.

### What changed

1. **`CLAUDE.md` → maintenance version.** Phase marker, phase paragraph and every *(build-out
   only)* section gone; 90 lines (74 of content) against its own "< ~80" rule, down from 95 over
   budget. It opens with the one fact every session needs — *nothing here has been compiled
   against an Apple SDK* — and gained a six-step "Making a change" checklist plus two durable
   rules the build-out earned: errors are never swallowed (`perform`/`report`, no `try?`), and
   the migration script is the user's to run. Every command in it was run during this task.
2. **`docs/ARCHITECTURE.md` → as built.** §4 no longer repeats Swift signatures (the code moved
   past them and the section was a duplicate that would go stale). It is now one block per target
   — what it owns, where to start reading, the invariants no signature shows — with every
   contract change T00-x…T41-x folded in as present-tense truth rather than a change log, and
   the section renamed "Module contracts". §2's layout and dependency graph were rebuilt by
   reading `Package.swift` (the old one listed `Spikes/VaultAccess/`, which does not exist, and
   omitted `GTDIntents` from the graph and `benchmark.sh` from the layout). §6 carries all 29
   decisions with dates, including T41's (error surfacing, the archive-link repair, the refused
   damaged routine log). §7 gained the honest statement that only *undo* has a staleness guard.
3. **`docs/CONTRIBUTING-AGENTS.md`** (new): the route for adding a field to the action schema,
   adding a `GTDCommand`, adding or changing a view, and adding a target — and that
   `Package.swift` is not frozen any more.
4. **`docs/KNOWN_ISSUES.md`** (new): the blind-code fact, the six partial requirements with their
   briefs, the deliberate limitations nobody should file as bugs, the smaller gotchas collected
   from every `## Result`, and the migration caveats. Linked from `README.md` and `CLAUDE.md`.
5. **Archive.** `agent_task/00–41` + the board README + `ORCHESTRATOR-NOTES.md` →
   `docs/history/build-out/`, with a banner on the README saying the briefs are history and that
   ownership, waves and frozen files no longer apply. The orchestrator notes' "REMOVE THIS FILE"
   comment became an archival note pointing at `docs/KNOWN_ISSUES.md`, which is where its "Still
   open" list went. **The six unstarted briefs are not archived**: `50`–`55` are now
   `docs/follow-ups/`, with a README that says when each can be started and how to pick one up
   without the build-out's rules. Every `agent_task/` link in the repo — docs, module READMEs,
   `Package.swift`, three test files — was repointed, and `check-docs.sh` now fails on a new one.
6. **`README.md`:** status first and honest (feature-complete on paper, unverified on a device,
   next step is `TEST-INSTRUCTIONS.md`), then what the app does, setup, build/test, run,
   first-real-use pointer, and the layout.
7. **Module READMEs** spot-checked: every backticked type name in each was checked against that
   target's sources (the misses were all file names, test suites or cross-module types). Fixed:
   `GTDModel`'s claim that `InMemoryBackend` still had a private `isUndoable` copy and that "T16
   must uniquify" trash collisions (both done since), ownership headers naming a task that no
   longer exists, and nine "T40/T13/T10 should…" instructions to finished tasks — rewritten as
   statements of what the code does. `Package.swift`'s header no longer claims the file is frozen.
8. **`scripts/check-docs.sh`:** now checks `docs/ARCHITECTURE.md`, the two new guides,
   `App/README.md`, `docs/follow-ups/README.md` and all 18 module READMEs (25 files), resolving a
   path against the repo root, the mentioning file's folder, `Packages/GTDKit`, `Sources/`,
   `Tests/` or a module folder, and accepting a bare file name that exists somewhere. It flags a
   `scripts/*.sh` that is missing **or not executable**, and it fails if any live file points at
   `agent_task/`. The three prose test scripts are exempt from the path check (their backticks
   hold suite and type names) but not from the stale-link rule.
9. **`scripts/check.sh`** runs `Tools/migrate/tests` when it finds a `pytest` on `PATH`, at
   `~/.local/bin/pytest`, or importable by `python3`, and skips with the command to run by hand
   otherwise. Here it finds the uv-installed one and runs all 40 — the matrix's "not in the gate"
   note is now "in the gate, when pytest is installed".

### Triplication removed

`TEST-INSTRUCTIONS.md`, `docs/MANUAL_TEST.md` and `App/README.md` each carried their own version
of "launch it on fixtures and check these screens" and "pick a vault, relaunch, see if it
remembers". Now: Gate 2 is *build and launch*, and sends you to `MANUAL_TEST` §1 for the walk;
Gate 3 is the bookmark assumption alone (the spike that was skipped), and sends you to §2 for the
rest; `App/README.md` keeps only what is the shell's own (App Intents metadata, signing) and
links the rest. `TEST-INSTRUCTIONS.md` stays — its banner now says exactly when to delete it
(after all three gates, the log committed, and anything unresolved moved into
`docs/KNOWN_ISSUES.md`), and `KNOWN_ISSUES` says the same from the other side. Its migration
snippet was also wrong (`migrate.py` requires `--vault`); fixed.

### Staleness test (deliverable 9)

A separate agent session could not be given this work — the branch is local and unpushed, and a
fresh session would clone a checkout without any of it. So the test was run by hand instead, as
strictly as possible: take the prompt *"Add an `energy` chip to actions — plan only, no code"*,
follow only what the documents say, and open only the files they name. Three findings, all fixed
in the docs rather than worked around:

1. **The right answer is "this is out of scope", and the docs said so only by accident.**
   `energy` is REQUIREMENTS §12; `CLAUDE.md` rule 8 says §12 is out of scope, but the contributing
   guide walked straight into the field route. It now opens with "check §12 first" and names the
   energy field as an example.
2. **A wrong pointer:** the guide sent the reader to `Entities/Entities.swift` for `ActionDraft`,
   which lives in `Commands/Commands.swift`. Fixed.
3. **A wrong claim:** "`FuzzRoundTripTests` picks a new key up for free once it is in `Keys`" — it
   does not; it has its own generator and mutation table, so a new field silently misses ~1 800
   generated notes and the damaged-file sweep. Fixed, with the two places to edit named.

Also added from the walkthrough: `docs/TRACEABILITY.md` is the fastest way to find *every* place
a field is rendered (I3 for the inbox card, E3 for the Mac editor), which is now step 6 of the
field route. The walkthrough otherwise landed correctly: `GTDModel` → `NoteCodec.Keys` +
`decodeAction`/`encode` + `NoteTemplates.action` → round-trip tests → `Reducer`/`Rules` →
`GTDFixtures` + regenerate → `DesignSystem` chip → the two feature views.

### Acceptance

- `grep -ri "build-out\|agent_task\|frozen\|T[0-9][0-9]" CLAUDE.md README.md docs/ARCHITECTURE.md`
  returns **one** line: `created: 2026-09-18T21:04:11+02:00`, the timestamp in §3's example action
  note. Nothing else matches.
- Every command in `CLAUDE.md` and `README.md` was run here, except the Xcode ones, which are
  marked as unrun and belong to `TEST-INSTRUCTIONS.md`.
- `scripts/check.sh` passes, including the extended `check-docs.sh` and the migration tests.

### Deviations

- The briefs were archived as `docs/history/build-out/`, as asked, but the acceptance grep forbids
  the string `build-out` in the three top files, so `CLAUDE.md` links `docs/history/` and
  `ARCHITECTURE` §6 describes the vault-access fallback instead of linking the spike brief. Both
  paths are one click from where a reader lands.
- `docs/REQUIREMENTS.md` and `docs/STYLEGUIDE.md` were not touched: they are snapshots of the
  user's vault notes, and `check-docs.sh` deliberately does not path-check them.
- `TEST-INSTRUCTIONS.md` was reconciled but **not deleted** — that is the Mac verifier's call,
  after the log is filled in.

### `scripts/check.sh`

```
=== swift build (Packages/GTDKit)
[11 expected "no rule to process file … xcstrings/assetcatalog" warnings]
Build complete!

=== swift test (Packages/GTDKit)
✔ 851 tests across all 18 test targets passed

=== docs check
checking backticked paths in 25 files
  ok (allow-listed, not a file in this repo): … (vault paths only)
checking that no live document points at the archived task board
checking the build-out phase marker
  ok (marker and agent_task/ agree)
check-docs.sh: ok

=== pytest — Tools/migrate
........................................                                 [100%]
40 passed in 0.57s

=== xcodebuild — package for the iOS Simulator
SKIPPED: xcodebuild not available (Linux). Asset and string catalogs are compiled by Xcode's build system only — verify this step on a Mac.

=== check.sh finished
```

(exit 0.)

### For whoever has a Mac, in their first ten minutes

`scripts/check.sh` (Gate 1) — the package compiles for the first time — then
`TEST-INSTRUCTIONS.md` "Where to look first", in that order. Nothing else in this repo is worth
doing before that.
