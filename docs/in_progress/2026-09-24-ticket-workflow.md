# Every change is tracked by a ticket; docs commits cost no Actions minutes

**Status:** in progress · **Branch:** `docs/ticket-workflow` · **PR:** https://github.com/MagnusSaurbier/GTD/pull/2 · **Opened:** 2026-09-24 · **Last updated:** 2026-09-24 · **Agent:** local

## Goal

The user made `docs/open_tickets/` and `docs/in_progress/` and asked for a rule every agent
(local or cloud) must follow: a ticket before any work, moved to in progress when work starts,
kept current (branch, state, what remains) so an interrupted session can be picked up, and moved
to `docs/history/` when the PR merges. Also: only significant functionality changes may trigger
cloud deployments or GitHub Actions; docs commits trigger nothing.

## State

- Committed and pushed on `docs/ticket-workflow`; PR #2 open. All three doc checks green; both
  checkers exercised in a scratch repo (missing/stale/merged ticket, good and bad workflows).
- Written `docs/TICKETS.md` (the rule + template), READMEs in the three ticket folders,
  `.github/workflows/README.md` (CI policy; the repo has no workflows yet),
  `scripts/check-tickets.sh` and `scripts/check-workflows.sh`, both wired into `scripts/check.sh`.
- `.claude/settings.json` runs the ticket board at every session start.
- `CLAUDE.md`, `docs/CONTRIBUTING-AGENTS.md`, `docs/follow-ups/README.md`, `scripts/check-docs.sh`
  updated to point at the rule.

## Remaining

1. Review and merge PR #2.
2. After merge: move this file to `docs/history/`, fill in **Outcome**, commit on `main` with `[skip ci]`.

## Handover

Docs-only change; nothing to compile. The main checkout is on another session's branch with
uncommitted edits — this work lives in the worktree `.claude/worktrees/ticket-workflow`.

## Outcome

—
