# Follow-ups — work that has not happened yet

Six briefs, written by the QA pass that closed the build-out. Each one is the spec for a GitHub
issue (`docs/TICKETS.md`); the issue, not this table, is where the state lives. Each one closes a gap
`docs/TRACEABILITY.md` records as **partial**, or a cost `scripts/benchmark.sh` measured.
They are not history: nothing in this folder has been started.

| Brief | Issue | Closes | Start it when | Size |
| --- | --- | --- | --- | --- |
| `50-mac-keyboard-map.md` | #4 | E3 — `⌘⏎`, `⌘⇧N/B/M`, `⌘⇧W` are missing from the menu bar | the app has built and run on a Mac | medium |
| `51-search-across-lists.md` | #5 | E1/E3 — `⌘F` reaches only `FeatureOverview`'s lists | the app has built and run on a Mac | small |
| `52-notification-actions-and-widget.md` | #6 | D2/R3 — notification actions, routine widget, Shortcuts picker | the app has built and run on a Mac | medium (new build target) |
| `53-stale-write-guard.md` | #7 | N3 — a write built on a pre-rename snapshot duplicates a note | any time; no device needed | judgment-heavy |
| `54-filed-at-record.md` | #8 | §10.3 — "captured vs processed" is an approximation | after two real weekly reviews | vault-format change |
| `55-incremental-reindex.md` | #9 | performance — a commit re-lists and re-assembles the whole vault | any time; no device needed | medium–hard |

"The app has built and run on a Mac" means `TEST-INSTRUCTIONS.md` Gate 2 is green: 50, 51 and 52
all touch SwiftUI files that no machine has compiled yet, and each brief says so at the top.

## Picking one up

The build-out's rules are over — there are no waves, no per-task "Owns" paths, no frozen files,
and no contract-change procedure. What is left is the ordinary one:

1. The brief's GitHub issue (table above) is the ticket: label it `in progress`, set **Branch:**,
   and keep its body current as `docs/TICKETS.md` says. The brief stays here as the spec.
2. Read `CLAUDE.md`, then `docs/CONTRIBUTING-AGENTS.md` for the shape of the change you are
   making, then the brief, then the README of every module it names.
3. Do the work. Keep GTD semantics in `GTDModel`, keep platform code behind the guards of
   `docs/ARCHITECTURE.md` §5, add the tests the brief asks for.
4. `scripts/check.sh` must exit 0. UI work also runs the `docs/STYLEGUIDE.md` §9 checklist.
5. Update what your change made untrue: `docs/TRACEABILITY.md`'s row (that is the point of the
   brief), `docs/KNOWN_ISSUES.md`, the module README, and `docs/ARCHITECTURE.md` §6 if you
   decided something.
6. The PR says `Closes #N`; fill in the issue's **Outcome** before opening it. A brief you only
   partly did keeps its issue open, with **Remaining** saying what is left.

A brief is a starting point, not a contract. If the code has moved past it, follow the code and
say so in the commit; if it turns out to be the wrong idea, delete it and write down why in
`docs/KNOWN_ISSUES.md`.
