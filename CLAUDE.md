# Instructions for agents working in this repo

<!-- PHASE: build-out -->
**Project phase: build-out.** The app is being built from the briefs in `agent_task/`.
Sections marked *(build-out only)* are deleted by T42 when the phase ends — if you are reading
this and `agent_task/42-docs-handover.md` has a filled-in Result, but this marker is still here,
this file is stale: fix it (see "Keeping this file current").

## Where things are

- `docs/REQUIREMENTS.md` — what the app does. Snapshot; the living copy is a note in the user's vault.
- `docs/ARCHITECTURE.md` — modules, dependency direction, vault layout, contracts, decisions.
- `Packages/GTDKit/Sources/<Target>/README.md` — per-module notes (purpose, public API, invariants, gotchas). Read the one for the module you touch.
- `agent_task/` — *(build-out only)* task briefs; shared rules in `agent_task/README.md`.

## Commands

_T00 fills this in with commands it has actually run (build, test, single test, app build, run
in simulator, regenerate the Xcode project). Until then nothing is buildable._

## Durable rules (apply in every phase)

1. **Never read from or write to the real Obsidian vault** under
   `~/Library/Mobile Documents/iCloud~md~obsidian/`. Use `GTDFixtures` / temp directories.
2. The app never hard-deletes vault files, and only `GTDVault` touches the file system.
3. All GTD semantics live in `GTDModel` (`Reducer`, `Rules`). UI and backends don't re-implement rules.
4. Every mutation is a `GTDCommand`. Features depend on `GTDAppCore` + `GTDDesign`, never on `GTDVault`/`GTDServices`.
5. The codec round-trips unknown frontmatter and body sections losslessly. Any change to
   `GTDMarkdown` must keep the round-trip tests green.
6. Product principles for every screen: few inputs, chips not dropdowns, **no lying defaults**
   (undecided = empty; suggestions look different from confirmed values).
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
| Requirements changed in the vault note | re-copy to `docs/REQUIREMENTS.md`, note the date at its top |

Rules for editing this file:

- Keep it short (< ~80 lines). It is an index plus invariants; detail belongs in `docs/` or module READMEs.
- Only write what you verified. Commands must have been run; paths must exist (`scripts/check-docs.sh` checks backticked repo paths in this file and in README.md).
- Don't describe history or plans here ("we will…", "recently…"). State what is true now.
- Delete rather than hedge: a missing instruction is better than a wrong one.
