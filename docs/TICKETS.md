# Tickets — the one rule every agent follows before, during and after a change

Every piece of work in this repo — local session, cloud session, subagent, one-line fix —
is tracked by **one markdown ticket** that moves through three folders:

```
docs/open_tickets/   →   docs/in_progress/   →   docs/history/
  written before          moved the moment         moved when the PR
  any work starts         work on it starts        is merged into main
```

The point is not bookkeeping. It is that **a session can be interrupted at any time** (context
limit, machine asleep, cloud job killed) and the next agent — or the user — must be able to pick
the work up from the ticket alone, without the transcript. That only works if the ticket is
never stale, so the rule is strict and `scripts/check-tickets.sh` (part of `scripts/check.sh`)
enforces the parts it can see.

## The rule

1. **Before starting any work, create a ticket** in `docs/open_tickets/` from the template
   below. File name: `YYYY-MM-DD-<slug>.md` (the date is the day it was opened). Do this
   *before* reading code, planning or branching. A brief in `docs/follow-ups/` counts as a
   ticket once you prepend the header block and move the file.
2. **The moment you or a subagent starts working on it** — the first branch, the first edit —
   `git mv` the ticket to `docs/in_progress/`, set `Branch:` to the branch you work on, and
   commit the move on that branch. A ticket may not sit in `open_tickets/` while code for it
   is being written.
3. **Keep the in-progress ticket current.** Update **State**, **Remaining** and
   **Last updated** at least:
   - before every `git push`,
   - whenever a subagent finishes or a decision changes the plan,
   - before you report done, and before your context could end (long sessions: every hour).
   Write it for a stranger: which branch, what is committed, what is verified on screen and what
   is not, what is left, which command to run next. `check-tickets.sh` fails when the branch has
   code commits newer than the ticket's last edit.
4. **When the PR is merged into `main`**, `git mv` the ticket to `docs/history/`, fill in
   **Outcome** (merge commit, what was verified, what was cut), and commit that on `main` with
   `[skip ci]` in the message (see `.github/workflows/README.md`). If you find an in-progress
   ticket whose branch is already merged, you do this move — whoever finds it, does it.
5. **Abandoned work** is not deleted: move the ticket to `docs/history/` with **Outcome**
   saying why it stopped and which branch holds the partial work.
6. Only tickets live in these folders (plus their `README.md`). Nothing else describes work in
   flight — not `TEST-INSTRUCTIONS.md`, not `docs/KNOWN_ISSUES.md`, not a chat transcript. Those
   files may *point to* a ticket.

`scripts/check-tickets.sh --status` prints the board and any problems; it runs at the start of
every agent session (`.claude/settings.json`) and inside `scripts/check.sh`.

## Template

Copy this verbatim — the checker looks for the bold field names and the four headings.

```markdown
# <Title in one line — what the user gets>

**Status:** open · **Branch:** — · **PR:** — · **Opened:** YYYY-MM-DD · **Last updated:** YYYY-MM-DD · **Agent:** local | cloud

## Goal

What is being changed and why, in the user's words where possible. Link the requirement
(`docs/REQUIREMENTS.md` §…) or the `docs/KNOWN_ISSUES.md` entry it closes.

## State

What is done, in the past tense, most recent first. Say what is committed (hash), what is
pushed, what ran green (`scripts/check.sh` tail), what was seen on screen and what only compiled.

## Remaining

Ordered list. The first item is the next command to run or the next file to open.

## Handover

Anything the next agent needs and cannot infer from the code: quirks, the fixture flag, which
window to look at, decisions taken and why, what NOT to do.

## Outcome

Empty until the ticket is done. Then: merge commit, date, what was verified after merge, what
was cut and where it is tracked now.
```

`Status` is one of `open`, `in progress`, `done`, `abandoned`. `Branch` is the branch name in
backticks once there is one. `PR` is the PR URL once there is one.

## Ticket size

One ticket per PR. If the work splits into several PRs, it splits into several tickets, and the
parent ticket lists them under **Remaining**. A subagent working on part of a ticket does not
open its own; the parent agent updates the shared ticket when the subagent reports.
