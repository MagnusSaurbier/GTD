# Manual test script (Mac + iPhone)

For the person with the devices. Everything below was written without a compiler and without a
simulator, so treat a failure as expected work, not as a surprise. Tick the boxes as you go and
note what broke — `TEST-INSTRUCTIONS.md` has the table to write it into.

> **Never point the app at the real vault under
> `~/Library/Mobile Documents/iCloud~md~obsidian/`.** Every step below uses a **copy**. Make one
> first: duplicate your vault folder (or copy
> `Packages/GTDKit/Sources/GTDFixtures/Resources/SampleVault`) to `~/Desktop/GTD Test Vault`.

## 0. Build

```sh
brew install xcodegen
scripts/check.sh --app        # package tests, then xcodegen + the macOS app
open GTD.xcodeproj            # run the GTD scheme on My Mac and on an iPhone simulator
```

## 1. Fixtures pass (no vault, nothing can be written)

Run with the `-useFixtures` launch argument (Product → Scheme → Edit Scheme → Arguments).

- [ ] **Mac:** window opens at ≥ 900×560; sidebar lists Inbox · Next · Backlog · Waiting · Maybe ·
      Projects · Deferred, then Review and Routines, with live counts.
- [ ] Inbox shows ~6 raw captures and a `Process inbox` button; process two cards with the
      buttons/keys — the counter goes `n of m left` and the queue shrinks.
- [ ] Tick off a Next item → undo toast → `Undo` (and `⌘Z`) puts it back.
- [ ] Complete the last open action of a project → **What's next?** appears.
- [ ] `⌘1…⌘7` move the sidebar, `⌘N` opens capture, `⌘I` opens processing, `⌘,` opens Settings.
- [ ] **iPhone:** three tabs (Next · Inbox · Routines), inbox tab carries a count badge, the gear
      on Next opens Settings, and a routine runs to its end screen.
- [ ] Dark mode and Dynamic Type at the largest accessibility size: nothing clipped or overlapping
      (STYLEGUIDE §9 checklist).

## 2. Real files (the copy)

Run **without** `-useFixtures`.

- [ ] Onboarding: pick `~/Desktop/GTD Test Vault`. The counts it shows match the folder.
- [ ] Quit and relaunch: it opens straight into the app — no second folder prompt (Gate 3).
- [ ] File an inbox card to Next: `Actions/<Title>.md` appears with `status: next` and the text
      under `# What?`. Nothing else in the file changed (`git diff` inside the copy, or `diff`
      against a backup) — unknown frontmatter keys and body sections must be byte-identical (N2).
- [ ] Edit the same note in Obsidian (or TextEdit) while the app runs: the app shows the change
      within a few seconds.
- [ ] Rename an action in the detail editor: the file moves and the project note's step link
      follows it, in one go.
- [ ] Trash a card: the file is in `GTD/Trash/`, not deleted.
- [ ] `Settings → Change vault…` then pick the copy again: everything still works.

## 3. Two devices (Mac + iPhone, same iCloud vault copy)

- [ ] Capture on the iPhone (quick-capture button or the Shortcut from `Shortcuts/README.md`) →
      the card appears on the Mac after iCloud syncs, and vice versa.
- [ ] Run the same routine on both devices on the same day: two log files,
      `GTD/RoutineLog/<day>--<device>.md`, one per device — never one shared file (N3, R5).
- [ ] Change something on device A while device B is asleep; wake B: it picks the change up on
      foreground without a restart.
- [ ] Undo on device B something device A changed since: the app must **refuse** the undo with a
      message ("the file changed"), never silently overwrite (T16).

## 4. Notifications (D2, R3)

- [ ] First launch after onboarding asks for notification permission once, not on every launch.
- [ ] Give an action a `due` date of tomorrow and a `defer` date of tomorrow; set the morning time
      in Settings to two minutes from now. Both fire in the morning slot.
- [ ] Give a routine a time two minutes out: it fires, and tapping it opens that routine's runner.
- [ ] Tapping a due/defer notification opens that action; a waiting one opens the waiting list.
- [ ] Complete the action, then wait for the next plan (or background the app): the pending
      notification for it disappears (Settings → Notifications toggles switch kinds off too).
- [ ] Turn a kind off in Settings: its pending notifications go away.

## 5. Capture under three seconds (C1)

- [ ] With the app **not running**, run the capture Shortcut (`Shortcuts/README.md`, recipe A)
      and stopwatch it: text prompt → saved, under 3 s, one new file in `Inbox/`.
- [ ] Same with the `Capture to Inbox` App Intent (recipe B), app suspended. If it fails, note it:
      the intent may need `openAppWhenRun = true` (documented in `GTDIntents`' README).
- [ ] `Start Routine` and `Process inbox` intents open the app **on that screen** (they leave a
      `PendingRoute` the shell consumes on foreground).

## 6. Screenshots for the record

Capture at least: Mac overview, inbox card mid-processing, Next on iPhone, a routine step, the
weekly-review wizard. Attach them to the verification log in `TEST-INSTRUCTIONS.md`.
