# Manual test script (Mac + iPhone)

For the person with the devices. Everything below was written without a compiler and without a
simulator, so treat a failure as expected work, not as a surprise. Tick the boxes as you go and
note what broke — `TEST-INSTRUCTIONS.md` has the table to write it into, and its Gates 1–3 are
what you do *before* this file: build the package, build and launch the app, check that the vault
bookmark survives a relaunch.

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

## 1. Fixtures pass (no vault, nothing can be written)

Run with the `-useFixtures` launch argument (Product → Scheme → Edit Scheme → Arguments).

- [ ] **Mac:** window opens at ≥ 900×560; sidebar lists Inbox · Next · Backlog · Waiting · Maybe ·
      Projects · Deferred, then Review and Routines, with live counts.
- [ ] Inbox shows ~6 raw captures and a `Process inbox` button; process two cards with the
      buttons/keys — the counter goes `n of m left` and the queue shrinks.
- [ ] Tick off a Next item → undo toast → `Undo` (and `⌘Z`) puts it back.
- [ ] Complete the last open action of a project → **What's next?** appears.
- [ ] `⌘1…⌘7` move the sidebar, `⌘N` opens capture, `⌘I` opens processing, `⌘,` opens Settings.
- [ ] **iPhone:** three tabs (Inbox · Next · Routines, opening on Next), inbox tab carries a count badge, the gear
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
      message ("the file changed"), never silently overwrite — every journal entry is checked
      against the files before it is applied.

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

## 6. Accessibility (STYLEGUIDE §8)

The blind review read every custom control and fixed the clear omissions
(`docs/history/build-out/41-qa-hardening.md` has the list). These are the ones only a device can
settle. Do them with `-useFixtures`, so nothing can be
written while you sweep.

**VoiceOver (iPhone: Settings → Accessibility → VoiceOver; Mac: `⌘F5`)**

- [ ] **Inbox card:** the rotor's *Actions* lists all eight card targets (the seven of I4 plus
      `Defer to review`) and `Undo`, and each one files the card. For a VoiceOver user this is the
      only route — the swipe is not.
- [ ] **Action row:** reads as `<title>, <project>, <contexts>, <time>` — one phrase, no "middle
      dot" — then its badges in full words (`16 days old`, `due Thursday`), then `Done` for the
      completion circle.
- [ ] **Chips** read their label and announce `unset` / `suggested` / `confirmed`; a confirmed chip
      is announced as selected.
- [ ] **Routine heatmap** (Mac, weekly review → systems check): each row reads
      `<step>, <n> percent complete` and then spells the week out —
      `done Mon, Tue; skipped Wed; nothing logged Thu, Fri, Sat, Sun`. Check "nothing logged" is
      never read as "skipped": they mean different things.
- [ ] **Every swipe action has a non-swipe twin.** On each list (Next, chase, Waiting, Deferred),
      open the context menu and confirm it offers everything the swipe does.
- [ ] **Routine runner:** `Done` and `Skip` are available as VoiceOver actions on the step card.

**Dynamic Type (iPhone: Settings → Accessibility → Display & Text Size → Larger Text, to the
largest accessibility size; Mac: System Settings → Appearance → text size)**

- [ ] Nothing is clipped or overlapping on: inbox card, Next list, routine step, weekly-review
      rail and heatmap, settings.
- [ ] Badges grow with the text instead of truncating (`16 days old` must stay readable).
- [ ] The review wizard's left rail grows; its stage sub-steps stay readable.
- [ ] `RewardMoment`'s hero symbol is **known** not to scale — it uses `.font(.system(size: 56))`,
      which STYLEGUIDE §2.3 forbids. Decide it here: keep it (and add the exception to §2.3) or
      move to `.largeTitle` (`TEST-INSTRUCTIONS.md` → Unresolved #1).

**Reduce Motion / Reduce Transparency / Increase Contrast**

- [ ] Reduce Motion: the inbox card cross-fades instead of flying out, does not rotate and does
      not shake on a validation refusal — the refusal still reaches you (focus + haptic).
- [ ] Reduce Transparency: the glass action bar and the undo toast become a solid card with a
      hairline, never a blurred one.
- [ ] Increase Contrast: chip outlines thicken; text stays legible in both colour schemes.

**Keyboard only (Mac — unplug the mouse)**

- [ ] Everything in STYLEGUIDE §4.5 that exists works: `⌘N`, `⌘1…⌘7`, `⌘F`, `⌘Z`, `⌘I`, `⌘,`, and
      the inbox card's arrow keys / `P K W R` / `Esc`.
- [ ] Known gaps, do **not** file these as bugs: `⌘⏎`, `⌘⇧N/B/M`, `⌘⇧W` are not in the menu bar
      (`docs/follow-ups/50-mac-keyboard-map.md`) and `⌘F` filters only the overview's own lists
      (`docs/follow-ups/51-search-across-lists.md`).
- [ ] Full Keyboard Access on: chips and card targets can be reached and activated with `Space`.

## 7. Performance on the real thing

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

## 8. Screenshots for the record

Capture at least: Mac overview, inbox card mid-processing, Next on iPhone, a routine step, the
weekly-review wizard. Attach them to the verification log in `TEST-INSTRUCTIONS.md`.

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
   pytest -q                                         # the script's own tests, first (40)
   python3 migrate.py --vault /path/to/your/vault    # writes only migration-report.md
   ```
   - [ ] Read `migration-report.md` **end to end**, not just the counts.
   - [ ] Work through every "needs a decision" item (unknown contexts, non-duplicate legacy
         actions, dangling links, `projects.decisions.yaml` for M5). Re-run the dry run until the
         list is empty or you have decided to accept what is left.
   - [ ] Skim the "Changes (planned)" list for anything you did not expect — especially M3
         removals and M5 project notes.
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
6. **The first weekly review is the real migration.** M1 put every ambiguous `to-do` into Backlog
   with a `reviewReason`, and M2 imported waiting items with no who and no follow-up date —
   deliberately, because neither is inventable. The review is where you settle them.
   - [ ] Sweep: the review-deferred items appear **with their reason**; decide each one.
   - [ ] Waiting: fill in who and a follow-up date for every imported item (W1).
   - [ ] Deck: bring Next down to 15 or fewer. Expect this to take a while the first time.
   - [ ] The review saves `GTD/Reviews/<year>/KW <week>.md`; open it in Obsidian.
7. **Then leave it alone for a week** before changing anything. The staleness thresholds
   (14 d / 30 d / inbox 7 d) are first guesses — STYLEGUIDE §10 says to tune them after two
   reviews, with real data, not before.

If something goes wrong at any point: quit the app, restore the backup from step 1 over the
vault folder, and write down what happened in `TEST-INSTRUCTIONS.md`'s verification log.
