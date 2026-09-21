# GTD App — Requirements (v1)

Status: requirements agreed 2026-09-18; inbox flow, tiers and lists revised 2026-09-21 (merged from [[GTD App Inbox UI Rework]], which keeps the decision log D1–D40). Tech stack deliberately **undecided** (see §13).
Source: [[GTD my own setup]], scan of `Actions/` + `Actions_legacy/`, research of existing tools.

## 1. Goals and principles

- Implement David Allen's GTD (capture → clarify → organize → reflect → engage) in one app that I trust.
- Fix the two failures of the current setups: **no efficient overview** of what to do, **no efficient inbox flow**.
- Few inputs per item. No field that doesn't carry information (no `priority`, no `type`, no tags).
- **No lying defaults**: an undecided field is empty, never pre-filled with a fake value. Suggestions must look different from confirmed values.
- Folders are for storage, `status` is for workflow. (Deliberate exceptions: a list is defined by its folder, §5a; trashed notes live in `GTD/Trash/`.)
- "GTD must be a living system. Staleness is hell." — the app actively surfaces stale things.

## 2. Platform and data (non-functional)

- N1. Works on **macOS and iOS**, **fully offline**.
- N2. Data store stays **markdown files + YAML frontmatter in the Obsidian vault, synced via iCloud**. Files remain readable/editable in Obsidian.
- N3. Sync-safe by design: one writer per file where possible, atomic new-file writes, no shared append-only files across devices.
- N4. The app replaces TaskNotes (its views and modals); the note-per-action data is kept.
- N5. Device split:
  - **iPhone**: capture, inbox processing, reduced Next view (on-the-go contexts only), **lists (full)**, routines.
  - **Mac**: everything, incl. full overview, projects, weekly review.
- N6. Undo for the last filing/status change.
- N7. **Mac keybinds are rebindable in settings** (defaults in I9).

## 3. Capture

- C1. Apple Shortcut on iPhone and Mac (global hotkey on Mac): text prompt → saved. Target: under 3 seconds, must not require Obsidian or the app to be running.
- C2. **Voice dictation** capture (Shortcut / Action Button), stored as transcribed text.
- C3. Each capture creates **one file** in `Inbox/` with a timestamp filename and `created` timestamp. No single `Inbox.md`.
- C4. Out of scope v1: photos/files, share sheet.

## 4. Inbox processing (clarify)

- I1. Started by a button on the home screen. **One item at a time, LIFO, forced order, no skipping.** Only exit: quit the session.
- I2. **Two-step card UI** (same cards on iPhone and Mac; Mac is keyboard-driven, I9).
  - **Step 1 — small card** showing the **full capture text** (scrolls if long; no truncation). The first decision is the *kind* of item, made with **buttons only, no gestures**: **Action** / **Knowledge or List** / **Trash**, plus a de-emphasised fourth option **Defer to weekly review** (I5).
  - **Title**: the original inbox entry stays the title; it becomes editable when clicked. What? is a separate field and does not replace it. The file keeps its timestamp name while in the inbox and is **renamed on filing** to the title (sanitised, truncated to ~60 chars); the full text stays in the note.
- I3. **Action** → the card opens in place and asks for:
  - **Why?** — why is this relevant / what do I gain?
  - **What?** — the next action (may be a short checklist doable in one sitting).
  - Metadata via **chips**, no dropdowns: context(s), time estimate bucket (≤10 / ≤30 / ≤60 / 60+ min). Optional chips: `defer`, `due`, **project** (I4a).
- I4. The opened action card leaves via:
  - **Swipe right = Next**, **swipe left = Someday**. Swipes exist only on the opened action card.
  - **Waiting** button → asks for **follow-up date (mandatory)** and **who to wait on (optional)** (§7).
  - **Done** button (2-minute rule: "I just did it") → files the note as `done` without requiring context/time.
  - **Swipe down / `Esc`** → collapses back to the step-1 card (misjudged from the title). Trash is only reachable from step 1.
  - **Required fields**: Next requires **Why? + What? + context + time**; Someday requires only What?; lists and Trash require nothing. The card refuses to leave and highlights what is missing.
  - **Next at cap (15)**: swiping right opens a **forced demote dialog** — pick a current Next item to demote to Someday, or cancel.
  - **Deferred items** get a tier swipe as usual; the item is hidden until its `defer` date and resurfaces in the tier it was swiped to. Resurfacing into a full Next triggers the demote dialog.
- I4a. **Project chip / picker**: projects are found by **expanding the area folder tree** or by **text search**. A new project is **created inline with only a name** (lands in `Projects/no_area/`, P1). When a capture is really a project, the card **stays an action** — it is treated as the first action and the project is created alongside in the picker; there is no separate "convert to project" path.
- I4b. **Knowledge or List** → an empty, **optional notes panel** opens (content goes to the note body). The **bottom navbar** holds all targets in a **fixed row with stable positions**:
  - **Knowledge** → folder picker with my categories + **free folder tree browsing/creating** in `Knowledge/`, last-used preselected. The picker **also lists active projects' folders**, so project reference material is filed here (the Action branch is for actions only).
  - **Each favourite list** (favourites selectable in settings) → files the item instantly into that list (§5a).
  - Trailing **"More…"** → sheet with all lists.
- I4c. **Trash** → the file is **moved to `GTD/Trash/`**, never deleted, so undo keeps working and iCloud sync can't lose a file irrecoverably. **The app never hard-deletes a vault file and does not purge the trash**; I empty `GTD/Trash/` by hand when I want to.
- I5. **Defer to weekly review**: escape hatch for items that don't fit the process. Available in **step 1 only** (from an opened card: collapse first). App **asks for a reason** why it doesn't fit; item + reason appear in the weekly review so the system gap can be fixed.
- I6. Counter ("3 of 14 left"), undo last card. Undo after a tier swipe / list filing returns to the **opened card with the entered fields intact**; undo after step-1 Trash or Defer brings back the small card.
- I7. Because of LIFO, capture → immediate processing doubles as the "create action now" workflow.
- I8. **Captures containing several items** (dictation): no split function — process the card as one item and quick-capture the rest by hand.
- I9. **Default Mac keys** (rebindable, N7). Step 1: `a` Action, `k` Knowledge/List, `x` Trash, `d` Defer to review. Opened action card: `→` Next, `←` Someday, `Esc` collapse, `p` Project chip, `w` Waiting, `⌘↩` Done, `Tab` through fields. Knowledge/List navbar: `1` Knowledge, `2`–`9` lists in row order, `0` More…. `⌘Z` undo.

## 5. Actions

- A1. One markdown note per action in `Actions/`. Body: `# Why?` and `# What?`.
- A2. An action may hold multiple checkboxes **if completable in one sitting**. When a **second checkbox** is added, the app shows a button suggesting **"Turn into project"**.
- A3. Commitment tiers (via `status`): **Next (hard cap 15)** / **Someday** (the single "not now" tier — the former Backlog and Maybe merged; the "how committed am I?" judgement happens in the weekly review deck, not during inbox processing). Further statuses: `in-progress`, `waiting`, `done`. Trash is not a status: trashed notes move to `GTD/Trash/` (I4c).
- A4. Contexts — closed list, chip picker, editable in settings: `mac`, `phone`, `home`, `campus`, `errands`, `calls`, `deep-work`. On-the-go set for iPhone view: `phone`, `errands`, `calls` (configurable). There is **no `reading` context**: all reading goes to the Read list (§5a); a must-read becomes a normal action with another context.
- A5. Done actions vanish from all views immediately (`completedDate` set); files older than 30 days are archived to `Archive/YYYY/MM/`.

### Frontmatter schema (actions)

| Field | Notes |
| --- | --- |
| `status` | `next` / `someday` / `in-progress` / `waiting` / `done` |
| `contexts` | list, closed enum |
| `timeEstimate` | minutes, empty if undecided (never `0`) |
| `project` | wikilink to project note, optional |
| `defer` | date; hidden until then |
| `due` | date; hard deadline |
| `followUpDate` | required when `status: waiting` |
| `waitingFor` | optional free text (who/what) |
| `created`, `completedDate` | set by app |
| `reviewReason` | set when deferred to weekly review from inbox |

Dropped: `priority`, `type`, `tags`, `scheduled`, `Ressources`.

## 5a. Lists

- L1. **Lists** hold items that are only relevant in a specific situation. Initial lists: **Read**, **Watch**, **Wish**. List items are **not commitments**: no Why?/What?, no time estimate, no cap, no `status`.
- L2. **Folders are the lists**: each subfolder of `Lists/` is a list (e.g. `Lists/Read/`), one note per item. The folder is the only marker. Settings can add / rename / remove lists (creates / renames the folder) and choose the favourites shown in the inbox navbar (I4b).
- L3. **Finishing** an item (read / watched / bought) = check off → the note moves to **`Lists/<name>/Done/`** and is kept as a log.
- L4. **Promoting** an item: **"Make action"** moves the note to `Actions/` and opens it as the normal opened action card (I3/I4: required fields, tier swipe, cap dialog).
- L5. Lists are **fully available on iPhone** (browse, finish, promote, edit) — typical on-the-go lookups.
- L6. Lists **never appear in the weekly review**.

## 6. Areas and projects

- P1. **Two levels**: **Areas** (ongoing, never finished — e.g. Applications, Karriereplanung) contain **Projects** (finite, with an outcome). Both are folders under `Projects/`; each project has a project note (index). **A project does not require an area**: area-less projects live in `Projects/no_area/`; assigning an area later moves the project into that area's folder.

  ```
  Projects/
    area 1/
      project 1
      project 2
    area 2/
      project 3
    no_area/
      project 4
      project 5
  ```
- P2. Project note: **outcome ("done when…") + why** header, **step checklist**, status, log. Only the **name** is needed to create a project (I4a); everything else can be filled in later.
- P3. Project status: `active` / `on-hold` / `someday` / `done`. **Only active projects put actions into Next** (these count toward the 15 cap). On-hold/someday projects are reviewed weekly.
- P4. Future steps are checklist lines in the project note; a step is **promoted** into a real action note. **Multiple parallel active actions per project are allowed.** A project is **stalled** when active with zero open actions → badge + surfaced in weekly review.
- P5. Completing a project action prompts: "What's next for <project>?" with the step list for one-tap promotion.
- P6. Project view (Mac): outcome/why header, **inline reorder/edit/check/promote steps**, **reference files of the folder**, **dated log** of completed actions.
- P7. No project deadlines/milestones in v1 (actions carry `due`).

## 7. Waiting-for, dates, tickler

- W1. Setting `waiting` requires a **follow-up date** (default +7 days); **who/what** (free text) is optional.
- W2. Waiting view: what · who · waiting since N days · follow-up date; sorted by staleness. Overdue follow-ups surface in Next as **"chase"** items.
- D1. `defer` hides an item from all lists until the date, then it reappears with a badge. `due` shows a warning badge as it approaches.
- D2. **Local notifications** for resurfacing deferred items, approaching deadlines, and follow-ups. No Apple Calendar/Reminders sync in v1.
- D3. Mac: calendar strip showing defer, due and follow-up dates on one timeline.

## 8. Engage views

- E1. **Next view** (default screen): filter chips for **context** and **time available**, below a plain list of actions (project shown as label). Max 15 items + chase items.
- E2. **iPhone**: Next view hard-filtered to on-the-go contexts; tick off actions; no full task overview. Exception: the **Lists tab is fully available** (L5).
- E3. **Mac overview**: sidebar with live counts (Inbox · Next · Someday · Waiting · Lists · Projects · Deferred), list in the middle, note preview/editor on the right. Primary grouping **by area/project**; context and time are filters, not groupings.
- E4. Projects list: each row = project, its active action(s), remaining step count, stalled badge.

## 9. Routines

- R1. App supports routines (initially **Morning** and **Bedtime**, from `Dayplan_template.md`), defined as markdown templates in the vault.
- R2. **Step-by-step cards**: one step per screen, big done/skip buttons, sub-steps inline. Primarily on iPhone.
- R3. Start via **scheduled local notification** (time per routine) and via **home-screen button / Shortcut**.
- R4. Journaling steps (dreams, achievements, gratitude, will-do-better) have **no text input** — journaling happens on the reMarkable. The step is just done/skip.
- R5. Log done/skipped **per step per day** (sync-safe: one log file per day or per device).
- R6. Routines never appear in action lists.

## 10. Weekly review (Mac, guided wizard, resumable)

1. **Sweep**
   1. Inbox to zero (drops into the processing card).
   2. Items **deferred to review, shown with their reason** → decide + note the system fix.
   3. Waiting-for: chase / bump / resolve.
   4. Stalled active projects → add next action or change project status.
2. **Next ↔ Someday deck** — cards: Next (keep / demote), then Someday (promote / keep / trash), then on-hold & someday projects. Ends with Next ≤ 15. **Staleness aid** for the Someday deck: sorted by last touched, project-linked first, "untouched > 30 days" stat shown. List items never enter the deck (L6).
3. **Systems check with live stats**
   - Prompts: trust in inbox / next / triggers — did anything slip? Workload manageable or piling up? Routines working?
   - Stats shown alongside: captured vs processed, done this week, age of Next items, items untouched > 30 days.
   - **Automatic routine audit**: per-step **7-day heatmap** per routine (rows = steps), completion %, trend vs last week.
4. **Reflection + next-week goals**
   - Prompt to **review the reMarkable journal notes** of the week.
   - The 8 questions (wanted to achieve → last week's goals shown alongside; achieved; behavior to change; what to stop; how did I grow; how to grow further; what to try out; goal for next week).
   - Saved as dated note `KW xx.md` in the vault.

## 11. Migration (one-time)

- M1. Normalize `Actions/` frontmatter: contexts → closed enum (`@Mac`→`mac`, `Phone`→`phone`, `Home`→`home`, `tum-stammgelände`→`campus`, `conversations`→`calls`, `10min`→`timeEstimate: 10`, drop `live`); notes with the `readlist` context move to the **Read list** (`Lists/Read/`) instead of getting a context; `timeEstimate: 0` → empty; remove `priority`, `type`, default `scheduled`; `to-do` and `backlog` → `next`/`someday` (decided in first review, respecting the cap).
- M2. Import `Actions_legacy/03_Waiting` (19) → `waiting` (follow-up date filled in first review); strip empty boilerplate bodies. The 45 items of `04_Maybe` are **imported as inbox captures and run through the new inbox flow** (each becomes Someday, a list item, Knowledge or Trash).
- M3. Remove the 37 duplicates in `Actions_legacy/01_Next_Actions`; keep `02_Done` as read-only archive.
- M4. Convert `Inbox.md` lines to one file each in `Inbox/`; resolve the 4 dangling links.
- M5. Classify existing `Projects/` folders into areas vs projects; create project notes.
- M6. 4 action notes with empty bodies go back to the inbox.

## 12. Out of scope for v1 (later features)

- LLM filing suggestions (knowledge folder, title, context/time, "this is a project").
- LLM / embedding search over knowledge base and projects.
- People / CRM (person notes, waiting-for linked to people, conversation notes).
- Energy field.
- Photo / file / share-sheet capture.
- Apple Calendar / Reminders sync.
- Project deadlines / milestones.
- Automatic parsing of reMarkable journal notes.
- Recurring actions; in-app routine editor (v1: edit the markdown template).
- Inbox processing timers, routine step timers.

## 13. Open decisions

- **Tech stack**: Obsidian plugin vs standalone app. Hard constraints from above: swipe-card UI and routine cards on iPhone, local notifications, capture without the app running, offline, iCloud markdown as store. To be evaluated next.
- Storage format of the routine log and review stats.
