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

- Implemented and committed on `feature/note-body-editor` (see the commit after the ticket
  move): `GTDModel/Entities/NoteBody.swift` (new, 10 tests), `Action.body` stored with
  `preamble`/`why`/`what` computed over it, `NoteCodec.decodeAction`/`encode` read and write
  the body whole (only when changed), `promoteListItem` puts the item's notes into the draft's
  preamble, `ActionEditModel` has `.body`/`setBody`/`displayBody`, `ActionDetailView` shows one
  `NoteEditor` with no `Why?`/`What?` labels. Sample vault regenerated (one blank line in
  `Look into that podcast app.md`).
- `swift test`: 1 410 package tests green. `scripts/check-docs.sh` ok. Scratch macOS app build
  (own `derivedDataPath`, walkthrough bundle id) succeeded; the one warning is pre-existing on
  `feature/markdown-live-preview` (`NoteEditor.swift:189`, main-actor call).
- **Seen off-screen, not on screen:** an `NSHostingView` probe (scratch SwiftPM executable,
  alpha-0 window, `cacheDisplay` → PNG) rendered the Mac detail on fixtures: chips unchanged,
  then one body with `Notes`, `Why?`, `What?` as headings, bold/code/checkboxes rendered, the
  missing `# Why?` inserted. The walkthrough app could not be screenshotted (user's Space was a
  full-screen app; AX tree empty). Caret-line plain rendering not re-checked (it is the
  `NoteEditor`'s existing behaviour). iOS never run.
- Docs updated: ARCHITECTURE §3 + §6 row, TRACEABILITY A1, STYLEGUIDE §4.4 detail sentence
  (the vault copy of STYLEGUIDE still needs the same sentence), MANUAL_TEST §3.7, GTDModel /
  GTDMarkdown / FeatureOverview READMEs.

## Remaining

1. `scripts/check.sh` tail green, push, open the PR (base `main`; the branch also carries the
   unmerged `feature/list-editing-shortcuts` + `feature/markdown-live-preview` commits).
2. On screen (MANUAL_TEST §3.7): Mac detail, typing under `# What?`, the first edit writing the
   added heading, iPhone.
3. Copy the STYLEGUIDE §4.4 detail-column sentence into the vault's living STYLEGUIDE note.

## Handover

The main checkout is on another session's branch; work only in the worktree. Launch with
`-useFixtures` and the walkthrough bundle id (memory: gtd-app-walkthrough-setup). This branch
carries the unmerged `feature/list-editing-shortcuts` and `feature/markdown-live-preview` work.

## Outcome

—
