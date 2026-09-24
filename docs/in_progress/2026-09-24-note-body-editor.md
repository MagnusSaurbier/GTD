# The action detail shows the whole note body as one live-preview markdown editor

**Status:** in progress · **Branch:** `feature/note-body-editor` · **PR:** — · **Opened:** 2026-09-24 · **Last updated:** 2026-09-24 · **Agent:** local

## Goal

User request (2026-09-24, with a screenshot of the Waiting detail column): the detail view
shall no longer show distinct `Why?` / `What?` fields. It shows the note's whole `.md` body —
everything that is not frontmatter — in one body section, rendered like Obsidian's live
preview (all markdown rendered except the line being edited, which shows as plain text).
Status, Context, Time, dates and Project stay as they are. If an action's body lacks the
`# Why?` / `# What?` sections, the app adds them.

Requirement rows touched: A1 (`docs/TRACEABILITY.md`), STYLEGUIDE §4.4 detail column.

## State

- Worktree `.claude/worktrees/body-editor` on `feature/note-body-editor`, branched from
  `origin/feature/markdown-live-preview` (the `NoteEditor`) with `origin/main` merged in (4c4b1b0).
- Nothing else yet.

## Remaining

1. `GTDModel`: `Action.body` becomes the stored body text; `preamble`/`why`/`what` become
   computed views over it (`NoteBody` section splitter, Linux-tested). Reducer/fixtures follow.
2. `GTDMarkdown`: `decodeAction` reads the whole body, `encode` writes it back only when it
   changed (round-trip tests stay green).
3. `FeatureOverview`: `ActionEditModel.body`/`setBody` (headings ensured), one `NoteEditor`
   in `ActionDetailView` instead of the two sections.
4. `scripts/check.sh`, docs (ARCHITECTURE §3/§6, TRACEABILITY A1, STYLEGUIDE §4.4 copy,
   module READMEs, MANUAL_TEST), then push and open a PR.

## Handover

The main checkout is on another session's branch; work only in the worktree. Launch with
`-useFixtures` and the walkthrough bundle id (memory: gtd-app-walkthrough-setup). This branch
carries the unmerged `feature/list-editing-shortcuts` and `feature/markdown-live-preview` work.

## Outcome

—
