# Agent task board

Each `NN-*.md` file is a self-contained brief for one subagent. Before starting, every agent reads:

1. `docs/REQUIREMENTS.md` (the sections listed in its task)
2. `docs/ARCHITECTURE.md` (all of it — it contains the frozen contracts)
3. its own task doc

## Waves and dependencies

```
Wave 0   00 foundation ──────────────┐        01 vault-access spike (needs a human + devices)
         02 migration script (indep.)│
                                     ▼
Wave 1   10 markdown codec    11 reducer+rules   12 design system   13 notifications   14 stats
(all     15 vault store (I/O first; parsing integration once 10 lands)
parallel)20 inbox   21 next   22 projects   23 waiting+dates   24 routines   25 overview shell   26 settings+onboarding
                                     ▼
Wave 2   16 vault backend (needs 10, 11, 15)     27 weekly review (needs 12, 14, 20)     30 capture (needs 15)
                                     ▼
Wave 3   40 app integration (needs everything)   →   41 QA + hardening
```

| # | Task | Owns | Needs |
| --- | --- | --- | --- |
| 00 | Foundation & contracts | whole scaffold | — |
| 01 | Spike: vault access on device | `Spikes/VaultAccess/` | — |
| 02 | Migration script | `Tools/migrate/` | — |
| 10 | Markdown codec | `GTDMarkdown` | 00 |
| 11 | Reducer & rules | `GTDModel/Reducer`, `GTDModel/Rules` | 00 |
| 12 | Design system | `GTDDesign` | 00 |
| 13 | Notifications | `GTDNotifications` | 00 |
| 14 | Stats & routine audit | `GTDStats` | 00 |
| 15 | Vault store | `GTDVault` | 00 (10 for integration tests) |
| 16 | Vault backend & undo | `GTDServices` | 10, 11, 15 |
| 20 | Inbox processing | `FeatureInbox` | 00 |
| 21 | Next view | `FeatureNext` | 00 |
| 22 | Projects | `FeatureProjects` | 00 |
| 23 | Waiting, deferred, calendar strip | `FeatureWaiting` | 00 |
| 24 | Routines | `FeatureRoutines` | 00 |
| 25 | Mac overview shell & lists | `FeatureOverview` | 00 (links 20–24 public views) |
| 26 | Settings & onboarding | `FeatureSettings` | 00 |
| 27 | Weekly review wizard | `FeatureReview` | 12, 14, 20 |
| 30 | Capture: Shortcuts & App Intents | `GTDIntents`, `Shortcuts/` | 15 |
| 40 | App integration | `App/`, `project.yml` | all |
| 41 | QA & hardening | tests, fixes anywhere (small) | 40 |

## Rules for every agent

- **Branch:** `task/NN-slug` off `main`, ideally in its own git worktree. One task = one branch = one PR/merge.
- **Ownership:** edit only the paths under "Owns" in your task doc. `Package.swift`,
  `docs/ARCHITECTURE.md` and other targets' public API are read-only. If you need a change
  there, make the minimal edit and list it under **Contract changes** in your task doc.
- **Gate:** `scripts/check.sh` (swift build + swift test, plus an iOS-simulator build of the
  package) must pass before you report done. Report failures verbatim; do not disable tests.
- **Never touch the real vault** (`~/Library/Mobile Documents/iCloud~md~obsidian/…`). Use
  `GTDFixtures` or a temp directory. Only T01 and T02 deal with real data, and only through a human.
- **No new dependencies** beyond Yams without writing the reason into your task doc.
- **Status:** when finished, fill in the `## Result` section at the bottom of your task doc
  (what was built, deviations, contract changes, open issues) and commit it on your branch.
- Commit messages: `TNN: <summary>`.
- Keep scope: anything listed in REQUIREMENTS §12 is out of scope. Don't build it, don't stub it.

## Orchestrator notes

- Run 00 alone and merge it before launching Wave 1; its public API is what makes the rest parallel.
- Wave 1 merges are conflict-free by construction (disjoint directories). Merge 10/11/15 first, then launch 16.
- 01 needs the user to run an app on their iPhone and Mac; schedule it early, since a negative
  result changes 15 (fallback: app-owned iCloud container + Obsidian vault relocated/symlinked).
- 02 produces a script only; the user runs it against the real vault after reviewing a dry-run.
