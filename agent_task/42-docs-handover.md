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

_(fill in when done)_
