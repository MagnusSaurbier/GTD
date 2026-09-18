# GTD

A personal Getting-Things-Done app for macOS and iOS. Native SwiftUI, fully offline; the data
store is the markdown notes in my Obsidian vault (synced via iCloud).

- `docs/REQUIREMENTS.md` — what the app does (v1; snapshot of the note in the vault, which stays the source of truth)
- `docs/ARCHITECTURE.md` — how it is built: modules, vault layout, frozen contracts, decisions
- `agent_task/` — the work split into task briefs for parallel subagents; start at `agent_task/README.md`

## Status

Planning done, no code yet. Next step: run `agent_task/00-foundation.md` (and, in parallel,
`01-spike-vault-access.md` and `02-migration-script.md`).

## Build (after T00)

```bash
brew install xcodegen
scripts/check.sh          # package build + tests (+ iOS simulator build)
scripts/check.sh --app    # generate the Xcode project and build the app
```
