# Instructions for agents working in this repo

<!-- PHASE: build-out -->
**Project phase: build-out.** The app is being built from the briefs in `agent_task/`.
Sections marked *(build-out only)* are deleted by T42 when the phase ends — if you are reading
this and `agent_task/42-docs-handover.md` has a filled-in Result, but this marker is still here,
this file is stale: fix it (see "Keeping this file current").

## Where things are

- `docs/REQUIREMENTS.md` — what the app does. Snapshot; the living copy is a note in the user's vault.
- `docs/STYLEGUIDE.md` — binding UI rules (tokens, components, gestures, keys, copy, icons). Snapshot of a vault note, like the requirements.
- `docs/ARCHITECTURE.md` — modules, dependency direction, vault layout, contracts, decisions.
- `Packages/GTDKit/Sources/<Target>/README.md` — per-module notes (purpose, public API, invariants, gotchas). Read the one for the module you touch.
- `App/README.md` — the app shell: composition root, routing, lifecycle, and what to verify on a Mac.
- `docs/MANUAL_TEST.md` — the checks only a real Mac/iPhone with a vault copy can do; §9 is the
  first-real-use checklist for the user's own vault.
- `docs/TRACEABILITY.md` — every requirement → its module, tests and status. Read the row for the
  requirement you are about to touch; fix it if your change moves it.
- `agent_task/` — *(build-out only)* task briefs; shared rules in `agent_task/README.md`.

## Commands

From the repo root. Verified on Linux with Swift 6.4:

```bash
scripts/check.sh                             # the gate: build + test + scripts/check-docs.sh
scripts/check.sh --app                       # additionally xcodegen + build the app
cd Packages/GTDKit && swift build
cd Packages/GTDKit && swift test
cd Packages/GTDKit && swift test --filter GTDModelTests               # one test target
cd Packages/GTDKit && swift test --filter "RulesTests/sidebarCounts"  # one test
scripts/benchmark.sh                         # performance numbers (1 000 notes); takes an argument
```

**Not yet run here — verify on a Mac** (`scripts/check.sh` prints `SKIPPED` and still exits 0
without them): `brew install xcodegen`; `xcodegen generate`; `xcodebuild build -scheme GTDKit
-destination 'generic/platform=iOS Simulator'` (in `Packages/GTDKit`); `xcodebuild build -project
GTD.xcodeproj -scheme GTD -destination 'platform=macOS'`; `open GTD.xcodeproj`, run the `GTD`
scheme on My Mac or an iPhone simulator, `⌘U` for `AppTests`/`AppUITests`. The launch argument
`-useFixtures` runs the app on `InMemoryBackend` + `GTDFixtures` — no vault, no files. Signing:
set `DEVELOPMENT_TEAM` in `project.yml` for a device build; Mac and simulator build unsigned.

Regenerate the committed sample vault after editing
`Packages/GTDKit/Sources/GTDFixtures/SampleSnapshot.swift`:
`cd Packages/GTDKit && GTD_EXPORT_SAMPLE_VAULT="$PWD/Sources/GTDFixtures/Resources/SampleVault" swift test --filter exportSampleVault`

**Platform guards (every package target).** `swift build`/`swift test` must pass on Linux, so
SwiftUI, UIKit, AppKit, UserNotifications and App Intents code lives in files wrapped **entirely**
in `#if canImport(SwiftUI)` (or `canImport(UserNotifications)` / `canImport(AppIntents)`), and
every target keeps at least one Linux-compilable file holding the logic worth testing. Per-target
split: `docs/ARCHITECTURE.md` §5. `App/` is outside the package and never compiles on Linux at
all. Expect 11 harmless `no rule to process file … xcstrings/assetcatalog` warnings.

## Durable rules (apply in every phase)

1. **Never read from or write to the real Obsidian vault** under
   `~/Library/Mobile Documents/iCloud~md~obsidian/`. Use `GTDFixtures` / temp directories.
2. The app never hard-deletes vault files, and only `GTDVault` touches the file system.
3. All GTD semantics live in `GTDModel` (`Reducer`, `Rules`). UI and backends don't re-implement rules.
4. Every mutation is a `GTDCommand`. Features depend on `GTDAppCore` + `DesignSystem`, never on `GTDVault`/`GTDServices`.
5. The codec round-trips unknown frontmatter and body sections losslessly. Any change to
   `GTDMarkdown` must keep the round-trip tests green.
6. UI follows `docs/STYLEGUIDE.md` (run its §9 checklist). Core principle: **no lying defaults** —
   undecided = empty; a suggestion is dashed, never persisted until confirmed.
7. Out of scope unless the user says otherwise: everything in REQUIREMENTS §12.
8. Gate before reporting done: `scripts/check.sh` (includes `scripts/check-docs.sh`). Report failures verbatim.

## Build-out rules *(build-out only)*

- Your brief is `agent_task/NN-*.md`. Edit only the paths it owns.
- `Packages/GTDKit/Package.swift` and the contracts in ARCHITECTURE §4 are frozen — follow the
  "Contract changes" procedure in `agent_task/README.md` if you must deviate.

## Keeping this file current

This file is loaded into every agent session, so a wrong line here misleads every future agent.
Treat it like code: **if your change makes any statement in CLAUDE.md, README.md,
`docs/ARCHITECTURE.md` or a module README untrue, fix that statement in the same commit.**

Update triggers:

| You did this | Update this |
| --- | --- |
| Added/renamed/removed a target, script, folder or command | "Where things are" / "Commands" here, ARCHITECTURE §2 |
| Changed a public contract or the vault layout/format | ARCHITECTURE §3/§4 and the module README |
| Made or reversed a product/technical decision | ARCHITECTURE §6 (one row, with date) |
| Learned a non-obvious gotcha (build quirk, platform trap, flaky test) | the module README; here only if it affects *every* task |
| Finished a build-out task | its `## Result`, its module README, and anything above that it invalidated |
| Requirements or style guide changed in the vault note | re-copy to `docs/REQUIREMENTS.md` / `docs/STYLEGUIDE.md`, then check ARCHITECTURE §5–§6 still agree |

Rules for editing this file:

- Keep it short (< ~80 lines). It is an index plus invariants; detail belongs in `docs/` or module READMEs.
- Only write what you verified. Commands must have been run; paths must exist (`scripts/check-docs.sh` checks backticked repo paths in this file and in README.md).
- Don't describe history or plans here ("we will…", "recently…"). State what is true now.
- Delete rather than hedge: a missing instruction is better than a wrong one.
