# GTD App — Requirements (v1)

Status: requirements agreed 2026-09-18. Tech stack deliberately **undecided** (see §12).
Source: [[GTD my own setup]], scan of `Actions/` + `Actions_legacy/`, research of existing tools.

## 1. Goals and principles

- Implement David Allen's GTD (capture → clarify → organize → reflect → engage) in one app that I trust.
- Fix the two failures of the current setups: **no efficient overview** of what to do, **no efficient inbox flow**.
- Few inputs per item. No field that doesn't carry information (no `priority`, no `type`, no tags).
- **No lying defaults**: an undecided field is empty, never pre-filled with a fake value. Suggestions must look different from confirmed values.
- Folders are for storage, `status` is for workflow.
- "GTD must be a living system. Staleness is hell." — the app actively surfaces stale things.

## 2. Platform and data (non-functional)

- N1. Works on **macOS and iOS**, **fully offline**.
- N2. Data store stays **markdown files + YAML frontmatter in the Obsidian vault, synced via iCloud**. Files remain readable/editable in Obsidian.
- N3. Sync-safe by design: one writer per file where possible, atomic new-file writes, no shared append-only files across devices.
- N4. The app replaces TaskNotes (its views and modals); the note-per-action data is kept.
- N5. Device split:
  - **iPhone**: capture, inbox processing, reduced Next view (on-the-go contexts only), routines.
  - **Mac**: everything, incl. full overview, projects, weekly review.
- N6. Undo for the last filing/status change.

## 3. Capture

- C1. Apple Shortcut on iPhone and Mac (global hotkey on Mac): text prompt → saved. Target: under 3 seconds, must not require Obsidian or the app to be running.
- C2. **Voice dictation** capture (Shortcut / Action Button), stored as transcribed text.
- C3. Each capture creates **one file** in `Inbox/` with a timestamp filename and `created` timestamp. No single `Inbox.md`.
- C4. Out of scope v1: photos/files, share sheet.

## 4. Inbox processing (clarify)

- I1. Started by a button on the home screen. **One item at a time, LIFO, forced order, no skipping.** Only exit: quit the session.
- I2. **Card UI** (Tinder-like on iPhone; same card, keyboard-driven on Mac): raw captured text (editable) + two fields:
  - **Why?** — why is this relevant / what do I gain?
  - **What?** — the next action (may be a short checklist doable in one sitting).
- I3. Metadata via **chips**, no dropdowns: context(s), time estimate bucket (≤10 / ≤30 / ≤60 / 60+ min). Optional: `defer`, `due`, project link.
- I4. Card leaves via swipe (iPhone) / key (Mac) to one of:
  - **Next** (blocked if Next is at cap → must demote something or choose Backlog)
  - **Backlog**
  - **Maybe**
  - **Knowledge** → folder picker with my categories + **free folder tree browsing/creating** in `Knowledge/`, last-used preselected
  - **Project** → pick existing / create new project (and area), then define first next action(s)
  - **Waiting** → requires who + follow-up date (§7)
  - **Trash**
- I5. **Defer to weekly review**: escape hatch for items that don't fit the process. App **asks for a reason** why it doesn't fit; item + reason appear in the weekly review so the system gap can be fixed.
- I6. Counter ("3 of 14 left"), undo last card.
- I7. Because of LIFO, capture → immediate processing doubles as the "create action now" workflow.

## 5. Actions

- A1. One markdown note per action in `Actions/`. Body: `# Why?` and `# What?`.
- A2. An action may hold multiple checkboxes **if completable in one sitting**. When a **second checkbox** is added, the app shows a button suggesting **"Turn into project"**.
- A3. Commitment tiers (via `status`): **Next (hard cap 15)** / **Backlog** / **Maybe**. Further statuses: `in-progress`, `waiting`, `done`, `trash`.
- A4. Contexts — closed list, chip picker, editable in settings: `mac`, `phone`, `home`, `campus`, `errands`, `calls`, `reading`, `deep-work`. On-the-go set for iPhone view: `phone`, `errands`, `calls`, `reading` (configurable).
- A5. Done actions vanish from all views immediately (`completedDate` set); files older than 30 days are archived to `Archive/YYYY/MM/`.

### Frontmatter schema (actions)

| Field | Notes |
| --- | --- |
| `status` | `next` / `backlog` / `maybe` / `in-progress` / `waiting` / `done` / `trash` |
| `contexts` | list, closed enum |
| `timeEstimate` | minutes, empty if undecided (never `0`) |
| `project` | wikilink to project note, optional |
| `defer` | date; hidden until then |
| `due` | date; hard deadline |
| `waitingFor`, `followUpDate` | required when `status: waiting` |
| `created`, `completedDate` | set by app |
| `reviewReason` | set when deferred to weekly review from inbox |

Dropped: `priority`, `type`, `tags`, `scheduled`, `Ressources`.

## 6. Areas and projects

- P1. **Two levels**: **Areas** (ongoing, never finished — e.g. Applications, Karriereplanung) contain **Projects** (finite, with an outcome). Both are folders under `Projects/`; each project has a project note (index).
- P2. Project note: **outcome ("done when…") + why** header, **step checklist**, status, log.
- P3. Project status: `active` / `on-hold` / `someday` / `done`. **Only active projects put actions into Next** (these count toward the 15 cap). On-hold/someday projects are reviewed weekly.
- P4. Future steps are checklist lines in the project note; a step is **promoted** into a real action note. **Multiple parallel active actions per project are allowed.** A project is **stalled** when active with zero open actions → badge + surfaced in weekly review.
- P5. Completing a project action prompts: "What's next for <project>?" with the step list for one-tap promotion.
- P6. Project view (Mac): outcome/why header, **inline reorder/edit/check/promote steps**, **reference files of the folder**, **dated log** of completed actions.
- P7. No project deadlines/milestones in v1 (actions carry `due`).

## 7. Waiting-for, dates, tickler

- W1. Setting `waiting` requires **who/what** (free text) and **follow-up date** (default +7 days).
- W2. Waiting view: what · who · waiting since N days · follow-up date; sorted by staleness. Overdue follow-ups surface in Next as **"chase"** items.
- D1. `defer` hides an item from all lists until the date, then it reappears with a badge. `due` shows a warning badge as it approaches.
- D2. **Local notifications** for resurfacing deferred items, approaching deadlines, and follow-ups. No Apple Calendar/Reminders sync in v1.
- D3. Mac: calendar strip showing defer, due and follow-up dates on one timeline.

## 8. Engage views

- E1. **Next view** (default screen): filter chips for **context** and **time available**, below a plain list of actions (project shown as label). Max 15 items + chase items.
- E2. **iPhone**: Next view hard-filtered to on-the-go contexts; tick off actions; no full task overview.
- E3. **Mac overview**: sidebar with live counts (Inbox · Next · Backlog · Waiting · Maybe · Projects · Deferred), list in the middle, note preview/editor on the right. Primary grouping **by area/project**; context and time are filters, not groupings.
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
2. **Next ↔ Backlog ↔ Maybe deck** — cards: Next (keep / demote), then Backlog and Maybe (promote / keep / trash), then on-hold & someday projects. Ends with Next ≤ 15.
3. **Systems check with live stats**
   - Prompts: trust in inbox / next / triggers — did anything slip? Workload manageable or piling up? Routines working?
   - Stats shown alongside: captured vs processed, done this week, age of Next items, items untouched > 30 days.
   - **Automatic routine audit**: per-step **7-day heatmap** per routine (rows = steps), completion %, trend vs last week.
4. **Reflection + next-week goals**
   - Prompt to **review the reMarkable journal notes** of the week.
   - The 8 questions (wanted to achieve → last week's goals shown alongside; achieved; behavior to change; what to stop; how did I grow; how to grow further; what to try out; goal for next week).
   - Saved as dated note `KW xx.md` in the vault.

## 11. Migration (one-time)

- M1. Normalize `Actions/` frontmatter: contexts → closed enum (`@Mac`→`mac`, `Phone`→`phone`, `Home`→`home`, `tum-stammgelände`→`campus`, `readlist`→`reading`, `conversations`→`calls`, `10min`→`timeEstimate: 10`, drop `live`); `timeEstimate: 0` → empty; remove `priority`, `type`, default `scheduled`; `to-do` → `next`/`backlog` (decided in first review, respecting the cap).
- M2. Import `Actions_legacy/03_Waiting` (19) → `waiting` (who/follow-up filled in first review) and `04_Maybe` (45) → `maybe`; strip empty boilerplate bodies.
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
- Swipe direction mapping for the 7 card targets (4 directions + buttons for the rest).
- Behaviour when Next is at 15 during inbox processing (forced demote dialog vs auto-Backlog).
- Storage format of the routine log and review stats.
