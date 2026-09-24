# Tickets — every change is a GitHub issue, opened before the work and kept current

Every piece of work in this repo — local session, cloud session, subagent, one-line fix — is
tracked by **one GitHub issue** in the MagnusSaurbier/GTD repository. The issue is the single place that says
what is being done, on which branch, what is finished and what remains.

```
open issue            →   label "in progress"        →   closed
written before any        set the moment work            by the PR ("Closes #N")
work starts               starts; body kept current      when it merges into main
```

The point is not bookkeeping. **A session can be interrupted at any time** (context limit, machine
asleep, cloud job killed) and the next agent — or the user — must be able to pick the work up from
the issue alone, without the transcript. That only works if the issue is never stale, so the rule
is strict and `scripts/check-tickets.sh` (part of `scripts/check.sh`) enforces the parts it can see.

## The rule

1. **Before starting any work, open an issue** with the body template below:
   `gh issue create --title "…" --body-file …`. Do this *before* reading code, planning or
   branching. A brief in `docs/follow-ups/` already has an issue (its README lists them);
   that issue is the ticket, the brief is its spec.
2. **The moment you or a subagent starts working on it** — the first branch, the first edit —
   add the label `in progress`, add `agent:local` or `agent:cloud`, and set **Branch:** in the
   body to the branch you work on (`gh issue edit N --add-label "in progress" --body-file …`).
   An issue may not stay unlabelled while code for it is being written.
   **Claim a version at the same time.** Every `in progress` issue owns one app version, and the
   build from its branch carries it (the shells stamp it bottom right, Settings prints it). Run
   `scripts/check-tickets.sh --status`: its `versions` line says what main is and which `0.N` is
   the next free one — one minor above the highest of main's `MARKETING_VERSION` and every open
   issue's claim. Put that number in **Version:** and in `project.yml`'s `MARKETING_VERSION`
   (one line, in the same commit as your first code). Two agents that start at the same time
   read the same board; the one whose issue edit lands second sees the collision on its next
   `check-tickets.sh` and takes the next free number. Never reuse a version another open issue
   claims, and never claim one at or below main's. On merge the branch's `project.yml` conflicts
   with main only if another version merged first; keep your own number. The checker fails the
   gate only for the current branch's own issue (no claim, a collision, `project.yml` disagreeing);
   another branch's missing claim is printed as a NOTE so that nobody's push waits on someone
   else's omission.
   Whenever you ask the user to test something on screen, say the version in chat ("build 0.2"):
   the stamp bottom right and the Dock name `GTD - 0.2` are how they confirm they run your build
   and not another session's.
3. **Keep the body current.** Rewrite **State** and **Remaining** (and **PR:** once there is
   one) at least:
   - before every `git push`,
   - whenever a subagent finishes or a decision changes the plan,
   - before you report done, and before your context could end (long sessions: every hour).
   Write it for a stranger: which branch, what is committed, what is verified on screen and what
   is not, what is left, which command to run next. GitHub records the edit time;
   `check-tickets.sh` fails when the branch has code commits newer than the issue's last edit.
   Progress notes that are not the current state (a finding, a dead end) go in issue comments.
4. **The PR body says `Closes #N`.** Merging then closes the issue. Before you open the PR, fill
   in **Outcome** (what was verified, what was cut and where that is tracked now) — after the
   merge the issue is closed and nobody comes back to it. If you find an `in progress` issue
   whose branch is already merged, close it with a filled-in Outcome — whoever finds it, does it.
5. **Abandoned work** is closed with the label `abandoned` and **Outcome** saying why it stopped
   and which branch holds the partial work (`gh issue close N --reason "not planned"`).
6. Nothing else describes work in flight — not `TEST-INSTRUCTIONS.md`, not
   `docs/KNOWN_ISSUES.md`, not a file under `docs/`, not a chat transcript. Those may *point to*
   an issue by number.

`scripts/check-tickets.sh --status` prints the board, the next free version and any problems; it runs at the start of
every agent session (`.claude/settings.json`) and inside `scripts/check.sh`. Without `gh` or
without network it prints `SKIPPED` and the rule still applies.

## Body template

Copy this verbatim — the checker looks for the bold field names and the headings.

```markdown
**Branch:** — · **PR:** — · **Agent:** — · **Version:** —

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

Empty until the PR is about to open. Then: what was verified, what was cut and where it is
tracked now, whether it is a significant functionality change (→ tag → deployment, see
`.github/workflows/README.md`).
```

**Branch** is the branch name in backticks once there is one; **PR** the PR URL; **Agent** is
`local` or `cloud`; **Version** the `<major>.<minor>` this issue claims (rule 2) — the same
string as `MARKETING_VERSION` in `project.yml` on the branch. Labels: `in progress` (state), `abandoned` (closed reason), `follow-up`
(has a spec in `docs/follow-ups/`), `agent:local` / `agent:cloud`.

## Ticket size

One issue per PR. If the work splits into several PRs, it splits into several issues, and the
parent issue lists them under **Remaining**. A subagent working on part of an issue does not
open its own; the parent agent updates the shared issue when the subagent reports.

## Useful commands

```bash
gh issue list --label "in progress"                      # what is being worked on, and by whom
scripts/check-tickets.sh --status                        # the board, and the next free version
gh issue view N                                          # the ticket
gh issue edit N --body-file body.md                      # update State / Remaining (the whole body)
gh issue edit N --add-label "in progress" --add-label "agent:local"
gh issue comment N --body "…"                            # a note that is not the current state
gh pr create --title "…" --body "Closes #N …"            # closes the issue on merge
```
