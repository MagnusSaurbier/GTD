# Instructions for agents working in this repo

A personal GTD app for macOS and iOS whose data store is the markdown notes in the user's
Obsidian vault. The pre-2026-09-21 code was **written blind, on Linux**; it first compiled and
launched on fixtures on 2026-09-19 (Xcode 27). Since then this Mac has Xcode 27, so new UI code
is compiled and some of it has been driven on screen — but **vault access on a device is still
untested**. `TEST-INSTRUCTIONS.md` has the three gates and their log; keep that file until Gate 3
is in it. The 2026-09-21 inbox rework is `docs/inbox-rework/IMPLEMENTATION-GUIDE.md` (§1 is the
delta, §3 the rulings R-1…R-10 every module now follows).

## Where things are

- `docs/REQUIREMENTS.md` — what the app does · `docs/STYLEGUIDE.md` — binding UI rules. Both are snapshots of notes in the user's vault, which stay the living copies.
- `docs/ARCHITECTURE.md` — modules, dependency direction, vault layout, module contracts, decisions.
- `docs/CONTRIBUTING-AGENTS.md` — the route through the code for a typical change.
- `docs/TRACEABILITY.md` — every requirement → its module, tests, status. Fix the row your change moves.
- `docs/KNOWN_ISSUES.md` — what is missing, deliberate or merely assumed. Read it before filing a bug.
- `docs/MANUAL_TEST.md` — the checks only a real Mac/iPhone can do (§1–§3 = the reworked flow); §9 is the first-real-use checklist.
- `docs/TICKETS.md` — **the ticket rule**: every change is a GitHub issue, opened first, labelled `in progress`, body kept current, closed by the PR.
- `docs/follow-ups/` — specs for the open `follow-up` issues · `docs/history/` — how the app was built; not instructions.
- `.github/workflows/README.md` — CI policy: docs commits run nothing, deploys only on tag/dispatch.
- `Packages/GTDKit/Sources/<Target>/README.md` — per-module notes. Read the one for the module you touch.
- `App/README.md` — the app shell: composition root, routing, lifecycle.

## Commands

From the repo root. Verified on Linux with Swift 6.4, and on macOS with Xcode 27:

```bash
scripts/check.sh                             # the gate: build + test + docs check + migration tests
scripts/check.sh --app                       # additionally xcodegen + build the app
cd Packages/GTDKit && swift build
cd Packages/GTDKit && swift test              # 1 350 tests across 19 test targets
cd Packages/GTDKit && swift test --filter GTDModelTests               # one test target
cd Packages/GTDKit && swift test --filter "RulesTests/sidebarCounts"  # one test
cd Tools/migrate && pytest -q                # the migration script's 90 tests
scripts/benchmark.sh                         # performance numbers (1 000 notes; takes an argument)
cd Packages/GTDKit && GTD_EXPORT_SAMPLE_VAULT="$PWD/Sources/GTDFixtures/Resources/SampleVault" swift test --filter exportSampleVault
```

The last one regenerates the committed sample vault after an edit to `GTDFixtures/SampleSnapshot.swift`.
Every step needing Xcode (`xcodegen`, both `xcodebuild`s) prints `SKIPPED` here and still exits 0;
`TEST-INSTRUCTIONS.md` has them, and `-useFixtures` runs the app with no vault and no files.

**Platform guards (every package target).** SwiftUI, UIKit, AppKit, UserNotifications and App
Intents code lives in files wrapped **entirely** in `#if canImport(SwiftUI)` (or
`canImport(UserNotifications)` / `canImport(AppIntents)`), and every target keeps at least one
Linux-compilable file holding the logic worth testing (`docs/ARCHITECTURE.md` §5). On Linux,
expect 11 harmless `no rule to process file … xcstrings/assetcatalog` warnings (none on a Mac).

## Durable rules

1. **Never read from or write to the real Obsidian vault** under
   `~/Library/Mobile Documents/iCloud~md~obsidian/`. Use `GTDFixtures` / temp dirs. Same for
   `Tools/migrate/migrate.py`: only the user runs it, on a copy, after a dry run.
2. The app never hard-deletes vault files, and only `GTDVault` touches the file system.
3. All GTD semantics live in `GTDModel` (`Reducer`, `Rules`). UI and backends don't re-implement rules.
4. Every mutation is a `GTDCommand`. Features depend on `GTDAppCore` + `DesignSystem`, never on `GTDVault`/`GTDServices`.
5. The codec round-trips unknown frontmatter and body sections losslessly. A change to
   `GTDMarkdown` keeps the round-trip tests green.
6. UI follows `docs/STYLEGUIDE.md` (run its §9 checklist). Core principle: **no lying defaults** —
   undecided = empty; a suggestion is dashed, never persisted until confirmed.
7. An error is never swallowed: `AppModel.send` throws, `perform`/`report` reach the shell's alert.
8. Out of scope unless the user says otherwise: everything in REQUIREMENTS §12.
9. Gate before reporting done: `scripts/check.sh`. Report failures verbatim; never disable a test.
10. **No work without a ticket** (`docs/TICKETS.md`): open a GitHub issue before anything else, label it
    `in progress`, set its **Branch:** and claim the next free **Version:** (`scripts/check-tickets.sh --status`
    prints it; `project.yml`'s `MARKETING_VERSION` gets the same number) the moment work starts, rewrite its
    **State**/**Remaining** before every push and before your context could end, close it via `Closes #N` in
    the PR. `scripts/check-tickets.sh` enforces this, including version collisions.
    **When you hand the user something to test, name the version in chat** ("this is 0.2"), so they can
    check the stamp bottom right (or the Dock name `GTD - 0.2`) and know they run the right build.
11. Actions minutes only for code: a docs-only commit ends its subject with `[skip ci]`; deploys run on
    tags or dispatch only (`.github/workflows/README.md`).

## Making a change

1. Read the README of every module you touch, then `docs/CONTRIBUTING-AGENTS.md` for its route.
2. Logic goes in a Linux-compilable file and gets a test; the SwiftUI file holds no decisions.
3. A new field crosses `GTDModel` → `GTDMarkdown` (+ round-trip test) → `Reducer`/`Rules` →
   `GTDFixtures` (regenerate the sample vault) → `DesignSystem` → the feature view.
4. Check the test you added fails when you break what it tests.
5. Run `scripts/check.sh`, fix the docs your change made untrue (below), and name in your report
   every file you could not compile here.

## Keeping this file current

Loaded into every agent session, so a wrong line misleads every future agent. Treat it like code:
**if your change makes a statement in CLAUDE.md, README.md, `docs/ARCHITECTURE.md` or a module
README untrue, fix that statement in the same commit.**

| You did this | Update this |
| --- | --- |
| Added/renamed/removed a target, script, folder or command | "Where things are" / "Commands" here, ARCHITECTURE §2 |
| Pushed, finished a subagent, changed the plan, or are about to run out of context | the issue body (`gh issue edit N --body-file …`) |
| Changed a public contract or the vault layout/format | ARCHITECTURE §3/§4 and the module README |
| Made or reversed a product/technical decision | ARCHITECTURE §6 (one row, with date) |
| Closed or widened a gap | the row in `docs/TRACEABILITY.md`, and `docs/KNOWN_ISSUES.md` |
| Learned a non-obvious gotcha (build quirk, platform trap, flaky test) | the module README; here only if it hits *every* task |
| The requirements or style guide note changed in the vault | re-copy it, then check ARCHITECTURE §5–§6 still agree |

Keep it short (< ~90 lines): an index plus invariants, detail in `docs/` or a module README.
Only write what you verified — commands must have been run, and backticked paths must exist
(`scripts/check-docs.sh` checks them here, in README.md, in ARCHITECTURE and in module READMEs).
State what is true now, not history or plans; delete rather than hedge.
