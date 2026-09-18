# GTD

A personal Getting-Things-Done app for macOS and iOS. Native SwiftUI, fully offline; the data
store is the markdown notes in my Obsidian vault (synced via iCloud).

- `docs/REQUIREMENTS.md` — what the app does (v1; snapshot of the note in the vault, which stays the source of truth)
- `docs/ARCHITECTURE.md` — how it is built: modules, vault layout, frozen contracts, decisions
- `docs/STYLEGUIDE.md` — binding UI rules: tokens, components, gestures, keys, copy, icons
- `agent_task/` — the work split into task briefs for parallel subagents; start at `agent_task/README.md`

## Status

Build-out. The scaffold from `agent_task/00-foundation.md` is in place: every target of
`Packages/GTDKit` exists and builds, the frozen contracts compile, and `InMemoryBackend` +
`GTDFixtures` let the UI be built before the vault layer lands. The modules themselves are being
filled in by the remaining briefs.

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

`scripts/check.sh` is the gate for every change. On a machine without Xcode (the Linux
containers the build-out agents run in) the `xcodebuild` and `xcodegen` steps print
`SKIPPED` and the script still exits 0 — so asset catalogs, string catalogs and the app target
are only validated on a Mac.

The Swift commands behind it, and how to run a single test, are listed in `CLAUDE.md` under
"Commands".

## Layout

```
App/                  the app shell (@main); the Xcode project is generated from project.yml
Packages/GTDKit/      all code, split into small targets — see docs/ARCHITECTURE.md §2
scripts/              check.sh (the gate) and check-docs.sh
docs/                 requirements, style guide, architecture
agent_task/           build-out briefs, one per task
```
