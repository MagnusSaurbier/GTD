# GTD App — Inbox UI Rework

Status: **merged into [[GTD App Requirements]] on 2026-09-21** (started 2026-09-19). This note remains as the decision log (D1–D40) with the reasons and rejected alternatives; the requirements doc is authoritative from now on.

## 1. Decided

### Categories

- D1. **Backlog and Maybe are merged** into one "not now" tier (**Someday**). Reason: keeps the clarify decision tree small; the "how committed am I?" judgement moves out of inbox processing and into the weekly review deck (promote / keep / trash).
- D2. New separate category: **Lists** — items that are only relevant in a specific situation. Initial lists: **Read**, **Watch**, **Wish**. List items are not commitments (no Why?/What?, no time estimate, no cap).

### Inbox processing flow (two steps)

- D3. **Step 1 — small card showing only the title.** First decision is the *kind* of item: **Action** / **Knowledge or List** / **Trash**.
- D4. **Action** → the card opens and asks for **Why?**, **What?**, **time** and **context** markers. Then a swipe decides the tier: **right = Next**, **left = Someday**.
- D5. **Knowledge/List** → an empty, **optional notes panel** opens (content goes to the note body). The **bottom navbar** holds all targets: **Knowledge** (opens the folder picker) and **every list** (each files the item instantly).
- D6. **Trash** → removes the note (see O3 for how).
- D7. *(revised 2026-09-21)* Swipe meanings: **right = Next**, **left = Someday** (opened action card only), **down = collapse** (D10). The earlier **down = Trash gesture is dropped** — Trash is a button.

- D8. *(was O1, 2026-09-21)* **Step-1 choice is made with buttons only** — three labelled buttons below the card (Action / Knowledge or List / Trash). No gestures in step 1. Rejected: tap + vertical swipes, three-way swipe.
- D9. *(was O3)* **Trash is a move, not a delete**: file goes to `Trash/` and is purged after ~30 days, so undo keeps working and iCloud sync can't lose a file irrecoverably.
- D10. *(was O4)* **Backing out of an opened card**: swipe down / `Esc` collapses it back to the step-1 card. Trash is only reachable from step 1.
- D11. *(was O14, partly)* **The step-1 card shows the full capture text** and scrolls if long (no truncation, no peek gesture). Still open: where the title becomes editable and when the file is renamed from timestamp to title — see O14.
- D12. *(was O6)* **Required fields per target**: Next requires **Why? + What? + context + time**; Someday requires only What?; Lists and Trash require nothing. The card refuses to leave and highlights what is missing.
- D13. *(was O15)* **Done button on the opened action card** (2-minute rule): files the note as `done` without requiring context/time.
- D14. *(was O16)* **Next at cap (15)**: swiping right opens a **forced demote dialog** — pick a current Next item to demote to Someday, or cancel.
- D15. *(was O17)* **Deferred actions** get a tier swipe as usual (`defer`/`due` chips stay optional). The item is hidden until its defer date and resurfaces in the tier it was swiped to; resurfacing into a full Next triggers the demote dialog (D14).
- D16. *(was O7)* The merged tier is called **Someday**, stored as `status: someday`. (Earlier drafts of this note called it "Later".)
- D17. *(was O8)* **List items are one note each in `Lists/<name>/`** (e.g. `Lists/Read/`). Promoting a list item to an action is a file move into `Actions/` plus a status change. Rejected: `status: list` inside `Actions/`, one markdown file per list.
- D18. *(was O8 remainder)* **Folders are the lists**: each subfolder of `Lists/` is a list; settings can add / rename / remove lists (creates / renames the folder). List notes carry no `status` — the folder is the only marker.
- D19. *(was O10)* **The `reading` context is dropped.** All reading goes to the Read list; a must-read becomes a normal action with another context. M1's `readlist → reading` mapping changes to map to the Read list.
- D20. *(was O9)* **Navbar is a fixed row** (Knowledge + lists in stable positions); **which lists appear in the row (favourites) is selectable in settings**. Still open: how non-favourite lists are reached from the card — see O9.
- D21. *(was O18, partly)* **Lists are fully available on iPhone** (browse, finish, promote, edit) — E2 needs an exception to its reduced-Next-view rule.
- D22. *(was O9 remainder)* Non-favourite lists are reached via a **trailing "More…" item** in the navbar row, opening a sheet with all lists.
- D23. *(was O18, partly)* **Finishing a list item = check off → archived as done**: the note moves to an archive folder inside its list (e.g. `Lists/Read/Done/`) and is kept as a log. Exact folder name still to be fixed.
- D24. *(was O11)* **Lists never appear in the weekly review** — no deck, no "skim your lists" prompt. The Someday deck gets a staleness aid (sort by last touched, project-linked first, "untouched > 30 days" stat).
- D25. *(was O5)* **Defer to weekly review lives in step 1 only**, as a fourth, de-emphasised option next to the three buttons. From an opened card: collapse first (D10).
- D26. *(was O18 remainder)* **Promoting a list item**: "Make action" moves the note to `Actions/` and opens it as the normal opened action card (Why?/What?/context/time, then tier swipe; D12 and D14 apply).
- D27. *(was O14 remainder)* **The original inbox entry stays the title**; it becomes editable when clicked. What? is a separate field and does not replace the title. Still open: when the file is renamed — see O14.
- D28. *(was O19)* **Multi-item captures: manual re-capture.** No split function; process the card as one item and quick-capture the rest by hand.
- D29. *(was O20)* **Undo returns to the opened card with entered fields intact** (after a tier swipe / list filing); undo after step-1 Trash or Defer brings back the small card.
- D30. *(was O14 last bit)* **File rename happens on filing**: the timestamp name stays while the item is in the inbox; on filing the filename becomes the title, sanitised and truncated to ~60 chars. Full text stays in the note.
- D31. *(was O12)* **`04_Maybe` migration: run all 45 items through the new inbox flow** (import as inbox captures; each becomes Someday, a list item, Knowledge or Trash). Not imported as `maybe`.

### Projects and Waiting

- D32. *(was O2, part a)* **Project is an optional field (chip) on every opened action card**, like context. **Waiting is a target button** on the opened action card (asks who / since). Step 1 stays at three kinds + Defer.
- D33. *(was O2, part b)* **When a capture is really a project, the card stays an action**: the captured item is treated as the first action and a **new project is created inline in the project picker**. No separate "convert to project" path.
- D34. *(was O2, part c)* **Project picker**: projects are found either by **expanding the area folder structure** (tree) or by **text search**. **Projects do not require an area** (area-less projects sit at the top level of the tree).
- D35. *(was O2, part d)* **Creating a project inline needs only a name.** Area, outcome etc. are optional and can be added later.
- D36. *(was O21)* **Project reference material goes through the Knowledge branch**: the Knowledge folder picker also lists active projects' folders as targets. The Action branch stays for actions only.

### Mac keys

- D37. *(was O13)* Default mapping, **all keybinds rebindable in settings**. Step 1: `a` Action, `k` Knowledge/List, `x` Trash, `d` Defer to review. Opened action card: `→` Next, `←` Someday, `Esc` collapse, `p` Project chip, `w` Waiting, `⌘↩` Done, `Tab` through fields. Knowledge/List navbar: `1` Knowledge, `2`–`9` lists in row order, `0` More…. `⌘Z` undo.

### Loose ends settled 2026-09-21

- D38. *(was O22)* Finished list items are archived in **`Lists/<name>/Done/`** (completes D23).
- D39. *(was O23)* **Waiting button** asks for a **follow-up date (mandatory)** and **who to wait on (optional)**.
- D40. *(was O24)* **Projects folder structure** — area-less projects live in `no_area/`:

  ```
  projects/
    area 1/
      project 1
      project 2
    area 2/
      project 3
    no_area/
      project 4
      project 5
  ```

  A project created inline with name only (D35) lands in `projects/no_area/`; assigning an area later moves it into that area's folder. The picker tree (D34) mirrors this structure.

### Settled while planning the implementation (2026-09-21)

- D41. **Trash stays `GTD/Trash/` and is never purged** — revises D9. The app keeps its "never hard-delete a vault file" invariant; the trash is emptied by hand.
- D42. **Projects: full scope** — `Projects/no_area/` for area-less projects *and* re-assigning a project's area moves its folder (reverses the earlier "project/area rename refused" decision for the area part).
- D43. **UI details** (now in [[GTD App UI Style Guide]] §3.5/§3.6/§4): step 1 = three equal neutral buttons, `Defer to review` as quiet link; opened action card bar = `Waiting` · `Done` · `⋯` (tiers by swipe, `⋯` repeats Next/Someday); Lists = 4th iPhone tab and a single Mac sidebar row; rebindable keys = inbox flow + review deck only, `⌘` shortcuts fixed; the session's quit button is `Close` because `Done` files a card.

## 2. Open decisions

*None — all points settled 2026-09-21.*

## 3. Requirements sections updated by the merge

I2–I4 (card UI and targets), A3 + frontmatter schema (`status: someday`, no `list` field — `Lists/<name>/` folders, `Trash/` folder; `reading` context removed), E2 (lists fully available on iPhone), E3 (sidebar: Inbox · Next · Someday · Waiting · Lists · Projects · Deferred), §10.2 (review deck), M1/M2 (migration), §13 (swipe mapping entry is superseded by this note).
