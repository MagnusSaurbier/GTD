# Manual test script (Mac + iPhone)

For the person with the devices. Each check is **what to do** and **what you must see** — if the
second half does not happen, that is the bug, whatever the first half looked like.
`TEST-INSTRUCTIONS.md` has the table to write failures into, and its Gates 1–3 are what you do
*before* this file: build the package, build and launch the app, check that the vault bookmark
survives a relaunch.

The 2026-09-21 rework changed the inbox, the tiers and the lists (`docs/inbox-rework/IMPLEMENTATION-GUIDE.md`
§1 is the delta). §1–§3 below are written against the **new** flow; anything that still says
Backlog or Maybe on screen is a bug.

> **§0–§8 never touch the real vault under
> `~/Library/Mobile Documents/iCloud~md~obsidian/`.** They all use a **copy**. Make one first:
> duplicate your vault folder (or copy
> `Packages/GTDKit/Sources/GTDFixtures/Resources/SampleVault`) to `~/Desktop/GTD Test Vault`.
>
> **§9 is the one deliberate exception**: it is the checklist for the day you point the app at
> the real thing, and it is for you, not for an agent. CLAUDE.md rule 1 — no agent reads or
> writes the real vault — is unchanged by it.

## 0. Build

```sh
brew install xcodegen
scripts/check.sh --app        # package tests, then xcodegen + the macOS app
open GTD.xcodeproj            # run the GTD scheme on My Mac and on an iPhone simulator
```

Run everything in §1 with the `-useFixtures` launch argument (Product → Scheme → Edit Scheme →
Arguments). Nothing can be written to any vault in that mode.

## 1. The two-step inbox card (I2–I4c, STYLEGUIDE §3.5/§3.6)

The centre of the rework. Do this one on **both** platforms: iPhone drives it with buttons and
swipes, Mac with keys. Open it with the `Process inbox` button, `⌘I`, or `gtd://inbox`.

### 1.1 Step 1 — the small card

- [ ] The card shows **only** the capture timestamp (and an age badge if the capture is old),
      the note's **title — its file name** — and, when the note has one, its body underneath
      (a long capture's whole text). No `Why?`, no `What?`, no chips, no `Show all` link. A card
      longer than the card area **scrolls inside the card**; it is never truncated.
- [ ] A note made in Obsidian from the Why/What template (`Inbox/test task.md`) shows
      **`test task`**, not `# Why? -`, and no skeleton body under it; the inbox list shows the
      same name.
- [ ] Tapping the title makes it editable in place. Change it and file the card: the file is
      renamed in `Inbox/` first, and the filed note has the new name. A name another inbox note
      already has is refused on the card and nothing moves.
- [ ] The bar has three **equal, neutral** buttons: `Action` · `Knowledge / List` · `Trash`.
      None of them is accent-filled or looks preselected.
- [ ] `Defer to review` is a quiet text button between the card and the bar, not a fourth button.
- [ ] Counter reads `n of m left`, top centre. The next card peeks 8 pt below, blurred/scaled.
- [ ] **No swipe does anything on this card** — try left, right, up and down. The card must not
      move at all.

### 1.2 Step 2a — the opened action card

- [ ] `Action` **expands the card in place** (no sheet, no new screen) and the bar cross-fades.
      Focus lands in `Why?`.
- [ ] The card now shows: title (still editable) · `Why?` · `What?` · the `Context` and `Time`
      chip groups · the value chips `+ defer` `+ due` `+ project`.
- [ ] Type `- ` at the start of a `What?` line: it becomes a checkbox. Add a **second** checkbox →
      the inline `Turn into project` button appears under the field.
- [ ] **Required-field refusal (R-3).** With the card empty, swipe → (or press `→`). The card
      **springs back**, shakes once, you feel an error haptic, focus jumps to `Why?`, and
      `Why?`, `What?`, `Context` **and** `Time` each grow a leading asterisk on their label. No
      alert, no red borders.
- [ ] Type something into `Why?`: **that** asterisk disappears immediately, the other three stay.
- [ ] Fill all four and swipe → : the card flies out right, the toast says `Moved to Next`.
- [ ] Swipe ← on the next card with only `What?` filled: it files, toast `Moved to Someday`
      (Someday asks for nothing else).
- [ ] Swipe ↓ : the card **collapses back to step 1** — it does not file and it does not skip.
      Re-open it with `Action`: everything you typed is still there.
- [ ] Swipe ↑ : nothing happens, the card springs back.
- [ ] Put the keyboard up in any field, then try to swipe: **swipes are off** while a field is
      focused, and a `Done` keyboard-toolbar button dismisses the keyboard.
- [ ] `Trash` and `Defer to review` are **not** reachable from here — the bar does not offer them.
- [ ] The bar has `Waiting`, `Done` and `⋯`. The `⋯` menu (`File to`) repeats **Next** and
      **Someday**, and is how you file a card taller than the screen.
- [ ] `Done` files the card as done and asks for **nothing** (the 2-minute rule, D13).
- [ ] **Waiting sheet (W1/D39):** the follow-up date is **required** and offered as a *dashed,
      suggested* +7 d chip you must tap to confirm; `Who or what` says **(optional)**.
      `Set waiting` stays disabled until a date is confirmed. File with the who left empty — the
      note must get `followUpDate:` and **no** `waitingFor:` line.
- [ ] **The date calendar (`DayPicker`):** tap a confirmed `+ defer` / `+ due` / follow-up chip —
      the calendar opens (popover on Mac, medium sheet on iPhone) on the chosen month with that
      day filled and today in accent. **One** click on any day sets the chip to that date and
      closes the calendar at once; `‹` / `›` page months and the middle dot returns to the month
      you started on, none of them changing the date. (Before 2026-09-24 this was a stock
      graphical `DatePicker` whose clicks never reached the chip: no date could be set at all.)
- [ ] The same on a **waiting row with no who** (W1/D39's optional who — `Edit who`, clear the
      field, `Set waiting`; on a migrated vault this is *every* imported waiting item): picking a
      date in the row's calendar must set the follow-up. Until 2026-09-24 the row dropped it
      silently, because the bump it builds required a who.
- [ ] A one-time hint overlay (`← Someday` / `→ Next` / `↓ Back`) appears the first time an
      **action card** is opened — not on the session's first card.

### 1.3 The project chip (I4a/R-8)

- [ ] There is **no** `Project` filing target anywhere. A capture that is a project stays an
      action and names its project.
- [ ] `+ project` opens the picker: a search field on top, then projects **without an area
      first and without any header** (never a "No area" label), then areas with their projects.
- [ ] **Mac, with more projects than the sheet is tall (15+; the fixtures have too few — use a
      vault copy, or the Xcode preview `Project — 40 projects, must scroll` in
      `FeatureInbox/InboxPreviews.swift`):** the sheet is a grouped form — the search field is a
      full-width row whose placeholder reads `Pick a project`, **not** a label in a left column —
      and it scrolls to the last project and to the `Create project` row. Scroll down, type: the
      field still takes the text and the list filters. `Esc` closes the sheet and leaves the card
      and its draft as they were; a second `Esc` is the card's own ladder.
- [ ] Same check for the other inbox sheets on the Mac: `Knowledge` (long folder tree + the
      `Project` section + notes reachable by scrolling), `Defer to review`, `Next is full`,
      `More…` — each opens at a sensible size (about 440×520), none is a tiny strip, none clips.
      And `Make action` on a list item › `+ project` (the same picker over a list item).
- [ ] Type a name no project has: the last row reads `Create project "<text>"`. Tap it — the chip
      confirms with that name.
- [ ] File the card. In the vault copy, `Projects/no_area/<name>/<name>.md` exists with
      `kind: project`, `status: active` and **no** `area:` line, and the action's note carries
      `project: "[[Projects/no_area/<name>/<name>]]"`.
- [ ] `⌘Z` once: **both** the action and the project it just created are gone, and the card is
      back — they were one command.

### 1.4 The Next cap (I4/A3/D14)

You need a full Next list: demote or complete until the Next sidebar count reads 15.

- [ ] File a complete card to Next. The card springs back and a sheet `Next is full` appears,
      listing the current Next items with `Demote` buttons and a `Cancel`.
- [ ] There is **no** "Send to Someday instead" button on this sheet.
- [ ] `Cancel` → nothing is filed, the card is still the card, still opened.
- [ ] `Demote` on one row → that item drops to Someday **and** the card files to Next, in one go.
- [ ] Nothing is ever demoted automatically.

### 1.5 Step 2b — the opened Knowledge / List card (I4b)

- [ ] `Knowledge / List` expands the card in place. It shows the title and **one** `Notes
      (optional)` field. No chips, nothing required.
- [ ] The navbar is a fixed row with stable positions: `Knowledge` first, then the favourite
      lists in the order set in Settings (at most **four** on iPhone, **eight** on Mac), then
      `More…` last. The positions must not reorder by use.
- [ ] Tap a **list** slot: the card files instantly, toast `Added to <list>`, and the note is at
      `Lists/<list>/<capture text>.md` with your notes as the body and **no** `status:` line.
- [ ] Tap `Knowledge`: a folder tree opens with the **last-used folder as a dashed, suggested
      row** at the top; below the tree a `Projects` section lists the **active** projects'
      folders as filing targets. Pick a project folder — the note lands **inside that project's
      folder**.
- [ ] Tap `More…`: a plain list of every list; tapping one files the card.
- [ ] In `More…`, tap `New list…`, type a name, `Create`: the folder `Lists/<name>/` exists, the
      card is filed into it (toast `Added to <name>`), and the next card's navbar shows the new
      list (while no favourites are chosen). Undo brings the card back to the opened Knowledge /
      List card; the empty list stays. Typing `read` when `Read` exists, or `Done`, is refused
      under the field and the sheet stays open.
- [ ] On a vault whose `Lists/` folder is empty or missing: the navbar is `Knowledge · More…`,
      and `More…` shows `No lists yet` with an explanation and `New list…` — never an empty sheet.
- [ ] Only ↓ works as a swipe here (collapse). ← and → do nothing.

### 1.6 Trash, defer, undo, quit

- [ ] `Trash` from step 1: the toast says `Moved to Trash` and the file is in `GTD/Trash/`,
      **not** deleted. No note anywhere gains a `status: trash` line.
- [ ] `Defer to review`: the reason field is required (`Defer` is disabled while empty). The
      capture leaves the queue and reappears in the weekly review's sweep **with that reason**.
- [ ] **Undo per R-9.** Tap the toast's `Undo` (or `⌘Z`) after each of these and check *which
      card comes back*:
      - after Next / Someday / Waiting / Done → the card returns **opened as an action card**,
        with everything you typed still in it;
      - after a list or Knowledge filing → the card returns **opened as the Knowledge / List
        card**, with your notes still in it;
      - after Trash or Defer to review → the card returns as the **small step-1 card**.
- [ ] The toolbar button says `Close`, not `Done` (on this screen `Done` files a card).
- [ ] `Esc` is a ladder: focused field → blurs it; opened card → collapses it; step 1 → quits
      the session.
- [ ] **Mac, by hand:** press `A` (the caret lands in `Why?`), type a word, then `Esc` three
      times. 1st: the caret leaves the field, the sheet stays, `W`/`←`/`→` act on the card
      again. 2nd: the card collapses to the small step-1 card, and `A` reopens it with the word
      still in `Why?`. 3rd: inbox processing closes. The sheet must **never** close on the 1st or
      2nd press — also not after clicking a chip or a bar button first, and not from the
      Knowledge / List card (`K`, click into `Notes`, `Esc` `Esc` `Esc`).
- [ ] **Mac:** with a nested sheet open (`P` project, `W` waiting, `0` More…), `Esc` closes only
      that sheet; the card under it stays opened.
- [ ] Capture something new mid-session (`⌘N`): it queues **behind** a card you have already
      opened, and jumps to the front only if the current card is an untouched step-1 card.
- [ ] Process the queue to zero: the reward moment appears with `n processed · m min` and a
      per-target breakdown (`6 Next · 3 Someday · 1 Trash`).

### 1.7 Mac keyboard (N7/I9)

Unplug the mouse for this one.

- [ ] The key legend under the card **changes per step**:
      step 1 `A Action · K Knowledge / List · X Trash · D Defer to review`;
      action card `← Someday  → Next    W Waiting · ⌘↩ Done · P Project · Esc Back`;
      Knowledge / List card `1 Knowledge · 2 Read · 3 Watch · 4 Wish · 0 More… · Esc Back`.
- [ ] Each of those keys does what the legend says: `A`/`K`/`X`/`D` on step 1, `←`/`→`/`W`/`P`
      and `⌘↩` on the action card, `1`…`9`/`0` on the navbar.
- [ ] `Tab` moves title → `Why?` → `What?` → chips. `Esc` blurs a focused field so the single
      keys act on the card again.
- [ ] With no field focused: `1…8` toggle contexts and `⇧1…⇧4` pick a time bucket.
- [ ] `⌘Z` undoes the last filing from anywhere on the screen.
- [ ] Filing with a key animates the card out **in that key's direction**.

## 2. Lists (§5a, L1–L6)

- [ ] **iPhone:** there are four tabs, in the order **Inbox · Next · Lists · Routines**, and
      **Next** is selected on launch.
- [ ] The `Lists` tab shows every list with its open count. Tap one → its items; tap an item →
      the note editor (title + notes). Items show a completion circle and a title only: no
      second line, no badges, no age.
- [ ] Swipe an item to `Done`: it disappears from the open half. `Show done` at the end of the
      list reveals it, and the file has **moved** to `Lists/<list>/Done/` — byte for byte the
      same note, not a copy.
- [ ] `⌘Z` / undo puts it back into the open half.
- [ ] **Make action** (context menu on a row, or the editor's toolbar button) opens the **same
      opened action card** as the inbox's step 2a — same fields, same asterisks, same cap sheet.
      File it: the note **moves** to `Actions/`, and the notes you had written on the item are
      still in it, above `# Why?`.
- [ ] **Mac:** in the Make action sheet `Esc` first blurs the focused field (sheet stays), the
      next `Esc` cancels and closes it; the item is still in its list.
- [ ] Make an action into **Next** without a `Why?`: refused with asterisks, exactly as in §1.2.
- [ ] **Mac:** the sidebar has a single `Lists` row (count = open items across all lists),
      between `Waiting` and `Projects`. Its content column shows one **section per list**
      (header = name + count, `Show done` at the end of a section that has finished items); the
      detail column is the note editor with a `Make action` toolbar button.
- [ ] Trash an item: it goes to `GTD/Trash/`, undoably.
- [ ] Start a weekly review: **no list item ever appears in the deck or the sweep** (L6).

## 3. Everything else the rework touched

### 3.1 Someday, everywhere (A3)

- [ ] The Mac sidebar reads **Inbox · Next · Someday · Waiting · Lists · Projects · Deferred**,
      then Review and Routines, with live counts. There is **no Backlog and no Maybe row**.
- [ ] `⌘1…⌘7` move through those seven sections in that order.
- [ ] The word "Backlog" and the word "Maybe" appear **nowhere** in the app.
- [ ] The Someday list's empty state names Someday, not Backlog.
- [ ] Leading swipe on a Next row offers `Someday`; `⌘⇧N` / `⌘⇧S` move the selected action to
      Next / Someday.
- [ ] `⌘⇧N` on an action missing required fields: the **shell's alert** names them
      (`Still missing: Why?, Context, Time`). That is the known v1 behaviour, not a bug.

### 3.2 R-2 — a deferred Next item coming back into a full Next

- [ ] Give a Next item a `defer` date in the future. It disappears from Next **and the cap count
      drops by one** (a hidden item holds no slot).
- [ ] Fill Next back up to 15. Now set that item's defer date to today (or wait for it): it
      returns to Next with a `back` badge, the cap signal reads `16/15`, and **nothing has been
      demoted automatically**.
- [ ] The `Next is full` sheet appears **once per foreground** until you demote something. Put
      the app in the background and bring it back: it asks again. Demote one: it stops asking.

### 3.3 Waiting with an optional who (W1/D39)

- [ ] A waiting row whose who is empty reads `<what>` alone — never a dangling "— ".
- [ ] Its chase row in Next reads `Chase: <what>`; with a who it reads `Chase: <who> — <what>`.

### 3.4 Projects and areas (P1/R-6/R-7)

- [ ] The projects list shows area-less projects **first, without a section header** (no
      invented "No area" heading).
- [ ] Open an area-less project → the area picker. Pick an area: the project's **folder moves**
      into that area, every action's `project:` link is rewritten in the same go, and the detail
      view you have open **stays open** on the same project.
- [ ] `⌘Z`: everything is back where it was, byte for byte.
- [ ] Pick an area that already has a project of that name: refused **inline** in the picker
      (a name collision), and nothing moves.
- [ ] Renaming a project is still refused — the folder is the project's identity.

- [ ] **Mac, a project with 15+ open steps:** complete its last open action — the `What's next?`
      sheet scrolls the steps inside the sheet and its three buttons stay visible. With two or
      three steps there is no scroll view and no gap under them. Same for an action with many
      checkboxes › `Turn into project`.

### 3.5 Settings (L2/R-5, N7)

- [ ] **Mac, `⌘,`: the Settings window scrolls.** At its default size (520×560) scroll from
      Contexts down to About — every section (Lists, Favourites, Next cap, Routines,
      Notifications, Keyboard, Vault, About) is reachable. Drag the window shorter (down to
      320 pt) and taller: it resizes, and the form still scrolls to the last row.
- [ ] **Lists section:** add a list (it appears at once, and `Lists/<name>/` exists as an empty
      folder), rename one (the folder moves, items included, `Done/` too), remove one — that
      asks with a `confirmationDialog` naming the list **and its item count**, then moves the
      whole folder into `GTD/Trash/`, undoably.
- [ ] Adding a list called `Done`, or a name a list already has (in any capitalisation), is
      refused **inline in the form**, never with an alert.
- [ ] **Favourites section:** toggle and reorder. You can store up to **8**; entries past the
      first four are marked `Mac only`. The inbox navbar's order follows it immediately.
- [ ] With no favourites ever chosen, the navbar shows the first four lists alphabetically —
      and `GTD/Config.md` has **no** `favouriteLists:` line until you change something.
- [ ] **Keyboard pane (Mac only):** one row per command, grouped by screen (inbox step 1, action
      card, Knowledge/List card, review deck), each with a key recorder.
- [ ] **Rebind one** — say the action card's `W` to `F`. Its row updates, and the inbox's action
      card legend now reads `F Waiting`. Press `F` on a card: the Waiting sheet opens. Press `W`:
      nothing.
- [ ] Bind a key another command on the **same screen** already has: refused inline with
      `Already used by <command>`, never an alert. The same key on a **different** screen is fine.
- [ ] `Esc`, `Tab`, `⌘Z` and `⌘↩` are refused as bindings.
- [ ] `Reset to defaults` puts every legend back to the I9 defaults, and the reset survives a
      relaunch (it is stored per device).
- [ ] The contexts editor no longer offers `reading` as a default — but a vault whose
      `Config.md` lists it still shows it (the list in the file is yours).

### 3.7 Drag a row onto a category (E3, 2026-09-24)

Mac, on fixtures. Every row in Next, Someday, Waiting and Deferred can be dragged; the sidebar
sections Next · Someday · Waiting · Projects · Deferred and the rows of the Projects list take
the drop. Inbox, Lists, Review and Routines never highlight and never take a drop.

- [ ] Drag a Next row onto **Someday**: the section lights up light blue (`dropTargetWash`) while the row hovers,
      the item moves at once, the `Moved to Someday` toast appears, `⌘Z` brings it back.
- [ ] Drag a Someday row that has a time estimate onto **Next**: moves at once (or the shell's
      cap alert at 15/15 — no automatic demotion).
- [ ] Drag a Someday row **without** a time estimate (`Digitise the old notes`) onto **Next**:
      the opened action card appears as a sheet with the note's own title, Why?, What? and
      chips, and an asterisk on **Time** only. Pick a bucket, swipe/`→`/`⋯ → Next`: the sheet
      closes and the row is in Next. `Close` instead: nothing changed.
- [ ] Drag any row onto **Waiting**: the card opens **with the follow-up sheet already up**.
      Confirm a date → the row is in Waiting with that date; `Cancel` on the sheet shows the
      card behind it, `Close` leaves the note where it was.
- [ ] Drag a row onto **Deferred**: a small `Defer` sheet with the date chip. `Done` with a
      future date → the row is in Deferred; `Cancel` → unchanged.
- [ ] Drag a row onto **Projects**: the project picker (search, `Create project "…"`). Pick one
      → the row's meta line names it. Drag it onto Projects again and pick another: the first
      is replaced (an action names one project).
- [ ] With **Projects** selected the middle column shows projects, not actions, so there is no
      row to drag onto a project row today; the project rows still take a dropped action
      (attach, replacing the old project) for whenever a view shows both. `Move to… → Project…`
      on any action row is the reachable path.
- [ ] Drop a row on the section it is already in (Next row on Next, a deferred row on
      Deferred): no highlight, nothing happens, no toast.
- [ ] Right-click any row: the context menu ends with **Move to ▸** Next / Someday / Waiting /
      Deferred / Project…, the current section's entry disabled; each does exactly what the
      drop does. VoiceOver reaches the menu; nobody needs the gesture.
- [ ] iPhone, Next tab: long-press a row → **Move to ▸** works the same (the card, the defer
      sheet and the picker are sheets over the tab). There is no sidebar on the iPhone, so
      there is nothing to drop on there; that is by design, not a gap.

### 3.6 The weekly review deck (§10.2)

- [ ] The deck is **Next → Someday → on-hold & someday projects**. There is no Backlog phase and
      no Maybe phase.
- [ ] The Someday part is ordered **stalest first**, with project-linked items before unlinked
      ones. A note that has never been touched sorts as the stalest of all, not as the newest.
- [ ] The Someday header shows the `untouched > 30 days` count.
- [ ] Deck keys are `K` keep · `D` demote · `P` promote · `T` trash, and they follow a rebind
      made in Settings › Keyboard.
- [ ] `Promote` on a card missing required fields: the card itself **names what is missing** and
      offers `Edit` and `Keep` — no silent skip, no shell alert.
- [ ] `Edit` opens that action's editor.
- [ ] `Promote` into a full Next: the deck's own `Next is full` sheet, `Demote`-and-retry or
      `Cancel`. The deck cannot be left over cap.
- [ ] A review left half-finished before the rework resumes without crashing (its old deck phase
      either maps onto Someday or simply restarts the deck stage; the sweep's progress is kept).

## 4. Real files (the copy)

Run **without** `-useFixtures`.

- [ ] Onboarding: pick `~/Desktop/GTD Test Vault`. The counts it shows match the folder.
- [ ] Quit and relaunch: it opens straight into the app — no second folder prompt (Gate 3).
- [ ] Capture `buy milk` twice: `Inbox/buy milk.md` and `Inbox/buy milk 2.md`, neither
      overwritten. An empty capture writes nothing.
- [ ] File an inbox card to Next: the **capture file is moved**, not copied —
      `Inbox/<name>.md` is gone and `Actions/<name>.md` is there, with the capture's own
      `created:` stamp and `status: next`. File an Obsidian template note (`test task`) the same
      way: `Actions/test task.md` has one `# Why?` / `# What?` pair, no copy of the skeleton above.
- [ ] Dictate (or paste) a capture far longer than a file name can hold: `Inbox/` gets a file
      named after the text **cut at a word boundary at ~60 characters**, with the **whole** text
      as its body; filed, the whole text is the note's first paragraph, above `# Why?`.
- [ ] Nothing else in the file changed (`diff` against a backup) — unknown frontmatter keys and
      body sections must be byte-identical (N2).
- [ ] Put a note with `status: backlog` into `Actions/` by hand. The app shows it under
      **Someday**. Process a whole session without touching it: the file is still byte-identical,
      still saying `backlog`. Now change its status in the app: only then does the line become
      `status: someday` / `status: next`, and every unknown key it carried is still there.
- [ ] Edit a note in Obsidian (or TextEdit) while the app runs: the app shows the change within
      a few seconds.
- [ ] Rename an action in the detail editor: the file moves and the project note's step link
      follows it, in one go.
- [ ] Trash a card, an action and a list item: all three files are in `GTD/Trash/`, none deleted.
- [ ] **Open in Obsidian** (the copy must be a vault Obsidian knows — open the folder as a vault
      once): from an action's detail, from a project's reference file, and from
      `Settings → Vault issues`, Obsidian opens that very file — no "Vault not found". Try a file
      whose name has a space, an `&` and an umlaut. Do it on the Mac (`path=`) **and** on the
      iPhone (`vault=&file=`). On fixtures the button is absent.
- [ ] **Copy path** (beside Open in Obsidian in an action's detail): the clipboard holds the
      note's absolute path, unescaped (`open "$(pbpaste)"` in Terminal opens the file). Absent on
      fixtures, like its neighbour.
- [ ] `Settings → Change vault…` then pick the copy again: everything still works.

## 5. Two devices (Mac + iPhone, same iCloud vault copy)

- [ ] Capture on the iPhone (quick-capture button or the Shortcut from `Shortcuts/README.md`) →
      the card appears on the Mac after iCloud syncs, and vice versa.
- [ ] Run the same routine on both devices on the same day: two log files,
      `GTD/RoutineLog/<day>--<device>.md`, one per device — never one shared file (N3, R5).
- [ ] Rename or remove a list on one device; the other picks the **folder move** up on
      foreground. (This is the first command that moves a directory on a live iCloud vault —
      watch it closely.)
- [ ] Change something on device A while device B is asleep; wake B: it picks the change up on
      foreground without a restart.
- [ ] Undo on device B something device A changed since: the app must **refuse** the undo with a
      message ("the file changed"), never silently overwrite — every journal entry is checked
      against the files before it is applied, including every file inside a folder a move would
      carry back.

## 6. Notifications (D2, R3)

- [ ] First launch after onboarding asks for notification permission once, not on every launch.
- [ ] Give an action a `due` date of tomorrow and a `defer` date of tomorrow; set the morning time
      in Settings to two minutes from now. Both fire in the morning slot.
- [ ] Give a routine a time two minutes out: it fires, and tapping it opens that routine's runner.
- [ ] Tapping a due/defer notification opens that action; a waiting one opens the waiting list.
- [ ] Complete the action, then wait for the next plan (or background the app): the pending
      notification for it disappears (Settings → Notifications toggles switch kinds off too).
- [ ] Turn a kind off in Settings: its pending notifications go away.

## 7. Capture under three seconds (C1)

- [ ] With the app **not running**, run the capture Shortcut (`Shortcuts/README.md`, recipe A)
      and stopwatch it: text prompt → saved, under 3 s, one new file in `Inbox/` named after the
      text's first line. Silence (empty dictation) writes no file.
- [ ] Same with the `Capture to Inbox` App Intent (recipe B), app suspended. If it fails, note it:
      the intent may need `openAppWhenRun = true` (documented in `GTDIntents`' README).
- [ ] `Start Routine` and `Process inbox` intents open the app **on that screen** (they leave a
      `PendingRoute` the shell consumes on foreground).

## 8. Accessibility, performance, screenshots

### 8.1 Accessibility (STYLEGUIDE §8)

Do these with `-useFixtures`, so nothing can be written while you sweep.

**VoiceOver (iPhone: Settings → Accessibility → VoiceOver; Mac: `⌘F5`)**

- [ ] **Inbox card, step 1:** the rotor's *Actions* lists exactly the four exits of that step
      (`Action`, `Knowledge / List`, `Trash`, `Defer to review`) plus `Undo` — and **not** the
      tiers, which do not exist yet at that point.
- [ ] **Opened action card:** the rotor lists `Next`, `Someday`, `Waiting`, `Done`, `Back` and
      `Undo`. For a VoiceOver user this is the only route — the swipe is not.
- [ ] **Opened Knowledge / List card:** the rotor lists `Knowledge`, each favourite list by name,
      `More…` and `Back`.
- [ ] A required-field refusal is **announced**, not only shown: the asterisked labels read as
      missing and focus moves to the first of them.
- [ ] **Action row:** reads as `<title>, <project>, <contexts>, <time>` — one phrase, no "middle
      dot" — then its badges in full words (`16 days old`, `due Thursday`), then `Done` for the
      completion circle.
- [ ] **List-item row** reads the title and `Done`, and nothing else — it carries no badges.
- [ ] **Chips** read their label and announce `unset` / `suggested` / `confirmed`; a confirmed chip
      is announced as selected. The Waiting sheet's +7 d chip must read as **suggested** until
      you confirm it.
- [ ] **Routine heatmap** (Mac, weekly review → systems check): each row reads
      `<step>, <n> percent complete` and then spells the week out —
      `done Mon, Tue; skipped Wed; nothing logged Thu, Fri, Sat, Sun`. Check "nothing logged" is
      never read as "skipped": they mean different things.
- [ ] **Every swipe action has a non-swipe twin.** On each list (Next, chase, Waiting, Deferred,
      a list's items), open the context menu and confirm it offers everything the swipe does.
- [ ] **Routine runner:** `Done` and `Skip` are available as VoiceOver actions on the step card.

**Dynamic Type (iPhone: Settings → Accessibility → Display & Text Size → Larger Text, to the
largest accessibility size; Mac: System Settings → Appearance → text size)**

- [ ] Nothing is clipped or overlapping on: step-1 card, opened action card (all four labels plus
      both chip groups), Knowledge / List card **and its navbar**, Next list, a list's items,
      routine step, weekly-review rail and heatmap, settings.
- [ ] The navbar keeps its fixed slots at the largest size — labels may truncate, positions may
      not move.
- [ ] Badges grow with the text instead of truncating (`16 days old` must stay readable).
- [ ] `RewardMoment`'s hero symbol is **known** not to scale — it uses `.font(.system(size: 56))`,
      which STYLEGUIDE §2.3 forbids. Decide it here: keep it (and add the exception to §2.3) or
      move to `.largeTitle` (`TEST-INSTRUCTIONS.md` → Unresolved #1).

**Reduce Motion / Reduce Transparency / Increase Contrast**

- [ ] Reduce Motion: the card cross-fades instead of flying out, does not rotate, and does **not
      shake** on a validation refusal — the refusal still reaches you (focus + haptic +
      asterisks). Step 2 still expands, but without the spring.
- [ ] Reduce Transparency: the three glass bars and the undo toast become solid cards with a
      hairline, never blurred ones.
- [ ] Increase Contrast: chip outlines thicken; the asterisks stay legible in both colour schemes.

**Keyboard only (Mac)**

- [ ] Everything in STYLEGUIDE §4.5 that exists works: `⌘N`, `⌘1…⌘7`, `⌘Z`, `⌘I`, `⌘,`,
      `⌘⇧N`/`⌘⇧S`, plus the per-step inbox keys of §1.7 and the deck keys of §3.6.
- [ ] Known gaps, do **not** file these as bugs: `⌘⏎`, `⌘⇧W` and `Space` are not in the menu bar
      (`docs/follow-ups/50-mac-keyboard-map.md`) and `⌘F` filters only the overview's own lists
      (`docs/follow-ups/51-search-across-lists.md`).
- [ ] Full Keyboard Access on: chips and bar buttons can be reached and activated with `Space`.

### 8.2 Performance on the real thing

`scripts/benchmark.sh` measures what a machine without a device can (scan, command, queries,
codec); the numbers it printed on Linux are in `docs/history/build-out/41-qa-hardening.md`.
These four need the device.

- [ ] **Cold launch to a usable Next view** with your real vault copy (≈1 000 notes). Stopwatch
      from click to the first list being scrollable. If it is over ~2 s, the first suspect is the
      scan, not the UI — run `scripts/benchmark.sh 1000` on the Mac and compare.
- [ ] **Typing in the detail editor** stays smooth while the vault is open and syncing. The
      autosave debounce is 600 ms, so a stutter every ~0.6 s means the save path, not the field.
- [ ] **Filing a card** feels immediate: the next card appears without waiting for the file write.
- [ ] **A sync landing many files at once** (open the vault in Obsidian and let iCloud pull a
      batch) produces one refresh, not one per file, and the window does not freeze.

### 8.3 Screenshots for the record

Capture at least: Mac overview with the `Lists` row, inbox step 1, an opened action card with
asterisks showing, the Knowledge / List card with its navbar, the `Next is full` sheet, the Lists
tab on iPhone, a routine step, the weekly-review deck. Attach them to the verification log in
`TEST-INSTRUCTIONS.md`.

## 9. First real use — the one-way door

Everything above runs on a **copy**. This is the sequence for the real vault, in order. Do not
reorder it: steps 1–3 are reversible only because of step 1.

1. **Back the vault up, outside iCloud.** Copy
   `~/Library/Mobile Documents/iCloud~md~obsidian/<YourVault>` to an external disk or
   `~/Backups/`, and check the copy opens in Obsidian. Not a snapshot, not "iCloud has it" — a
   folder you can hold. Everything below assumes you can go back to it.
2. **Quit Obsidian on every device**, and let iCloud finish syncing (the folder's status icons
   settle). A migration racing a sync is the one situation the script cannot protect you from.
3. **Migration dry run** — `Tools/migrate/README.md`, step 1:
   ```sh
   cd Tools/migrate
   pytest -q                                         # the script's own tests, first (42)
   python3 migrate.py --vault /path/to/your/vault    # writes only migration-report.md
   ```
   - [ ] Read `migration-report.md` **end to end**, not just the counts.
   - [ ] Work through every "needs a decision" item (unknown contexts, non-duplicate legacy
         actions, dangling links, `projects.decisions.yaml` for M5). Re-run the dry run until the
         list is empty or you have decided to accept what is left.
   - [ ] Skim the "Changes (planned)" list for anything you did not expect — especially M3
         removals and M5 project notes.
   - [ ] Two changes are new and worth looking for by name: **M1** moves your `readlist` notes
         into `Lists/Read/` as plain list items (frontmatter stripped to what a list item
         carries, the body kept), and **M2** turns the old `04_Maybe` items into **inbox
         captures** — one file each in `Inbox/`, body = old title + old body — instead of
         `status: maybe` actions. They will reach you through inbox processing, not the deck.
   - [ ] The generated `GTD/Config.md` has **no** `reading` context, and the report never writes
         the words `backlog` or `maybe` except as the one `someday` fallback it explains.
4. **Apply** — `python3 migrate.py --vault /path/to/your/vault --apply`. It backs up
   `Actions/`, `Actions_legacy/`, `Projects/` and `Inbox.md` first and refuses to run if that
   backup fails.
   - [ ] Open the vault in **Obsidian** and look at ten notes by hand. This is the last point at
         which a mistake is cheap.
   - [ ] Re-run `--apply`: it must report **zero changes** (it is idempotent).
5. **Point the app at the vault.** Launch it *without* `-useFixtures`, pick the real vault folder
   in onboarding, and check the counts it shows match what Obsidian shows.
   - [ ] Quit and relaunch: it opens straight in, no second folder prompt.
   - [ ] Settings → any vault issues listed are ones you recognise (conflict copies, files iCloud
         has not pulled yet). The app never fixes them by itself.
   - [ ] **Tidy up the area-less projects yourself (R-6).** New projects without an area now live
         in `Projects/no_area/`. The ones your vault already has, sitting directly in `Projects/`,
         keep working exactly as before and the app will **never move them on its own** — it does
         not touch files you have not asked it about. In Obsidian, drag each of those project
         folders into `Projects/no_area/` (create the folder if it is not there yet). Two things
         it must **not** contain: a `no_area.md` note (`no_area` is a folder, not an area — the
         app reports one as a vault issue and leaves it alone), and an area of your own called
         `no_area` (the app refuses to create one). Either way you can skip this entirely and
         just pick an area for such a project in the app later — that moves its folder for you,
         rewrites the links of every action in it, and is undoable in one step.
   - [ ] Any note your vault still carries with `status: backlog` or `status: maybe` shows up
         under **Someday** and its file is **not** rewritten. That is deliberate (R-1): the word
         changes only when you change that note's status in the app.
6. **The first weekly review is the real migration.** M1 put every ambiguous `to-do` into
   **Someday** with a `reviewReason` (the fallback word is always `someday`, never
   `backlog`/`maybe`), and M2 imported waiting items with no who and no follow-up date —
   deliberately, because neither is inventable. The review is where you settle them. `readlist`
   notes are not part of this: they went straight to `Lists/Read/` as list items, and the old
   `04_Maybe` items arrived as plain inbox captures, so they show up in **inbox processing**, not
   the deck.
   - [ ] Sweep: the review-deferred items appear **with their reason**; decide each one.
   - [ ] Waiting: fill in a follow-up date for every imported item, and a who where you know one
         (the who is optional now — W1/D39).
   - [ ] Deck: bring Next down to 15 or fewer. Expect this to take a while the first time.
   - [ ] The review saves `GTD/Reviews/<year>/KW <week>.md`; open it in Obsidian.
7. **Then leave it alone for a week** before changing anything. The staleness thresholds
   (14 d / 30 d / inbox 7 d) are first guesses — STYLEGUIDE §10 says to tune them after two
   reviews, with real data, not before.

If something goes wrong at any point: quit the app, restore the backup from step 1 over the
vault folder, and write down what happened in `TEST-INSTRUCTIONS.md`'s verification log.
