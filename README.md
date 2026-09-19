# GTD

A personal Getting-Things-Done app for macOS and iOS. Native SwiftUI, fully offline; the data
store is the markdown notes in my Obsidian vault (synced via iCloud).

- `docs/REQUIREMENTS.md` — what the app does (v1; snapshot of the note in the vault, which stays the source of truth)
- `docs/ARCHITECTURE.md` — how it is built: modules, vault layout, frozen contracts, decisions
- `docs/STYLEGUIDE.md` — binding UI rules: tokens, components, gestures, keys, copy, icons
- `docs/TRACEABILITY.md` — every requirement → the code and tests that implement it, with a status
- `docs/MANUAL_TEST.md` — the checks that need a Mac or an iPhone, ending in the first-real-use checklist
- `agent_task/` — the work split into task briefs for parallel subagents; start at `agent_task/README.md`

## Status

Build-out. Every target of `Packages/GTDKit` is implemented and tested on Linux, and the app
shell wires them together: the vault backend behind onboarding, the iPhone tabs and the Mac
window, deep links, notifications and background refresh (`App/README.md`). Everything that needs
an Apple SDK was written without a compiler — `TEST-INSTRUCTIONS.md` and `docs/MANUAL_TEST.md`
are the checks that close that gap on a Mac.

`docs/TRACEABILITY.md` says where every requirement stands, including the six that are only
partly met; each of those has a follow-up brief (`agent_task/50-*.md` … `55-*.md`).

The build-out ends with `agent_task/42-docs-handover.md`, which rewrites `CLAUDE.md`, this file and
the architecture doc to describe the code as built. Agent instructions live in `CLAUDE.md`;
its "Keeping this file current" section says when and how to update them.

## Setup

```bash
brew install xcodegen      # macOS only; generates the (git-ignored) Xcode project
```

Nothing else is needed: the only third-party dependency is Yams, pinned in
`Packages/GTDKit/Package.swift` and resolved by SwiftPM.

## Build and test

```bash
scripts/check.sh          # swift build + swift test + scripts/check-docs.sh (+ iOS simulator build)
scripts/check.sh --app    # additionally: xcodegen generate, then build the macOS app
```

```bash
scripts/benchmark.sh      # the performance numbers: scan, one command, queries, codec
scripts/benchmark.sh 3000 # …against a bigger generated vault
```

`scripts/check.sh` is the gate for every change. On a machine without Xcode (the Linux
containers the build-out agents run in) the `xcodebuild` and `xcodegen` steps print
`SKIPPED` and the script still exits 0 — so asset catalogs, string catalogs and the app target
are only validated on a Mac.

The Swift commands behind it, and how to run a single test, are listed in `CLAUDE.md` under
"Commands".

## Run it

```bash
scripts/check.sh --app    # generates GTD.xcodeproj
open GTD.xcodeproj        # run the GTD scheme on "My Mac" or an iPhone simulator; ⌘U for the tests
```

On first launch the app asks for the Obsidian folder that holds the Actions notes and remembers
it as a security-scoped bookmark. Add the launch argument `-useFixtures` (Product → Scheme → Edit
Scheme → Arguments) to run on the sample snapshot instead, touching no files at all — that is what
the UI tests use. Signing is yours: set `DEVELOPMENT_TEAM` in `project.yml` before building for a
device; macOS and the simulator build unsigned. `docs/MANUAL_TEST.md` is the checklist for
testing against a real (copied!) vault.

## Layout

```
App/                  the app shell (@main); the Xcode project is generated from project.yml
AppTests/             unit tests for the shell's own logic
AppUITests/           launch-and-navigate smoke tests (always -useFixtures)
Packages/GTDKit/      all code, split into small targets — see docs/ARCHITECTURE.md §2
Shortcuts/            capture Shortcut recipes
scripts/              check.sh (the gate), check-docs.sh, benchmark.sh
docs/                 requirements, style guide, architecture, traceability, manual test script
agent_task/           build-out briefs, one per task
```
