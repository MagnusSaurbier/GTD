# Capture Shortcuts (C1, C2, C3, R3)

Two independent ways to capture into the GTD inbox in under three seconds, with neither Obsidian
nor the GTD app running. Ship both; **A is the default** because it has zero dependency on the
app ever being installed, built or even finished. `.shortcut` files cannot be authored from code,
so these are step-by-step recipes — build them once in the Shortcuts app on each device, using
the exact action names below.

## A. Pure Shortcut recipe (recommended default)

Works today, needs nothing from this repo except the vault folder. Five actions:

1. **Ask for Input** (Input Type: Text, Prompt: "Capture") — text variant.
   Voice variant: **Dictate Text** (Language: default) instead — the transcript becomes the
   input to the rest of the shortcut (C2).
2. **Format Date** — Date: *Current Date*, Format: *Custom*, Custom Format: `yyyy-MM-dd HHmmss`.
   Name this result `Stamp` (long-press the result chip → Rename Variable) — you'll reference it
   twice.
3. **Format Date** — Date: *Current Date*, Format: *ISO 8601*. This becomes the `created:` value;
   name it `Created`.
4. **Text** — contents exactly:

   ```
   ---
   created: [Created]
   ---
   [Provided Input]
   ```

   ("[Created]" and "[Provided Input]" are the Shortcuts variable chips for step 3's result and
   step 1's dictated/typed text — insert them, don't type the brackets.) This matches
   `GTDVault.InboxWriter`'s own template (`---\ncreated: <iso8601>\n---\n<body>\n`) and is what
   `NoteCodec.decodeInboxItem` parses; `CaptureCodecRoundTripTests` in `GTDIntentsTests` pins the
   literal string above once T10's codec lands. A capture is exactly one YAML key
   (`created`) followed by the raw text — no title, no tags, nothing else to fill in.
5. **Save File** — Service: *iCloud Drive* (wherever the Obsidian vault lives), File Path:
   `<vault>/Inbox/[Stamp].md` (insert the `Stamp` variable; the full path looks like
   `Obsidian/MyVault/Inbox/2026-09-19 081204.md`), Input: the **Text** result from step 4.
   Turn **off** "Ask Where to Save" and **off** "Overwrite If File Already Exists" — a capture is
   the one thing with no other copy; two captures in the same second must never collide. (Version
   B's `InboxWriter` appends `-1`, `-2`… on a same-second collision; a plain Shortcut cannot do
   that automatically, so with Overwrite off a same-second second capture safely fails instead of
   destroying the first — re-run it a second later.)

### Variants

| Trigger | Platform | Setup |
| --- | --- | --- |
| Global hotkey | Mac | Shortcuts → the shortcut's settings (`⌘I`) → *Add Keyboard Shortcut*. |
| Home Screen icon | iPhone | Share sheet → *Add to Home Screen* on the shortcut. |
| Back Tap | iPhone | Settings → Accessibility → Touch → Back Tap → Double/Triple Tap → pick the shortcut. |
| Action Button (voice, C2) | iPhone 15 Pro+ | Settings → Action Button → Shortcut → pick the **Dictate Text** variant. |
| Menu bar / Spotlight | Mac | Shortcuts app menu bar item, or run by name via Spotlight. |

Use the dictate-text variant of step 1 for every voice trigger; everything else in the recipe is
identical.

### Troubleshooting

- **"Shortcuts Would Like to Access iCloud Drive" / folder permission prompt** — appears the
  *first* time this shortcut (or any shortcut) writes to a folder inside Obsidian's iCloud
  container. It can only be granted interactively, so run the shortcut once manually (tap it in
  the Shortcuts app) right after building it; a Back Tap / Action Button trigger before that first
  manual run will silently fail. This is the same constraint T01 recorded for the app's own
  bookmark.
- **Evicted `Inbox/` folder** — if nothing in `Inbox/` has been opened in Obsidian for a while,
  iCloud may evict the folder placeholder and **Save File** can hang or fail with "could not be
  found". Fix: open the vault in the Files app or Obsidian once so `Inbox/` re-downloads, or mark
  the folder "Keep Downloaded" (Files app → folder → `⋯` → Keep Downloaded).
- **Empty capture** — if Dictate Text produces nothing (silence, cancelled), **Save File** would
  still write a file with an empty body. Add an **If** (Provided Input has any value) around
  steps 2–5 if you want silence to be a no-op instead of an empty inbox card; the App Intents path
  (B) already rejects empty text (`CaptureError.emptyText`).

## B. App Intents (needs the GTD app installed, not running)

Once the app is installed, three actions register automatically with Shortcuts and Siri
(`GTDAppShortcuts` in `Sources/GTDIntents/CaptureIntents.swift`):

- **Capture to Inbox** (`CaptureToInboxIntent`) — `openAppWhenRun = false`. Runs `InboxWriter`
  directly through the app's saved vault bookmark; does **not** open, scan or index the vault, so
  it is the App-Intents equivalent of recipe A. Dialog result: "Captured." Failure modes speak for
  themselves (`CaptureError.errorDescription`): empty text, no vault chosen yet, stale bookmark
  (open the app once to refresh it), or any other write failure with its reason.
- **Start Routine** (`StartRoutineIntent(routine:)`) — `openAppWhenRun = true` (needs the loaded
  vault to run the step cards). Say or type "Morning" or "Bedtime"; opens the app at that
  routine's runner (R3).
- **Process Inbox** (`ProcessInboxIntent`) — `openAppWhenRun = true`. Opens the app straight at
  inbox processing (I1), for "capture now, clear it later today" workflows.

Build a one-tap Shortcut with a single **Capture to Inbox** action (Text parameter set to
*Ask Each Time*, or piped from **Dictate Text** for the voice variant) for the same triggers as
recipe A — or just say "Hey Siri, capture to GTD" once Siri suggests the phrase.

**Advantage over A:** collisions are handled properly (`-1`, `-2`… suffixes, see
`InboxWriter.capture`), and errors are spoken instead of Shortcuts' generic "file already exists"
failure. **Disadvantage:** requires the app to be installed and a vault already chosen — recipe A
works from a bare Shortcuts app with only a folder path, which is why A ships as the default.

**Unverified — check on a device (T30 Result):** whether iOS resolves a security-scoped bookmark
and runs `InboxWriter.capture` from `CaptureToInboxIntent.perform()` while the app is fully
suspended (not merely backgrounded), since `openAppWhenRun = false` intents in a single-target app
(no separate App Intents extension here) may still run in the app's process on demand rather than
truly standalone. If it does not, `openAppWhenRun` must flip to `true` for this intent and A stays
the only truly app-free path.

### Not shipped

- **Control Center / Lock Screen control** (`ControlWidget` running `CaptureToInboxIntent`) — a
  `ControlWidget` needs its own widget extension target, which `project.yml` does not declare yet
  (T00/T40 own that file). Flagged for T40 rather than added speculatively here.
- **Photos/files, share sheet (C4)** — out of scope per `docs/REQUIREMENTS.md` §3.

## Verifying the 3-second target (C1)

Neither recipe can be timed from this Linux container (Shortcuts requires an Apple device), so
this is the check for whoever verifies on a Mac/iPhone:

1. Stopwatch a Back Tap / Action Button / hotkey trigger from the physical gesture to the
   confirmation haptic/banner, **excluding** dictation time itself (C1 is about the capture
   mechanism, not how fast someone talks).
2. Expected budget: recipe A ≈ 0.2–0.5 s to launch the shortcut + well under 0.5 s for
   **Save File** on a synced iCloud folder ≈ **under 1 s** total, comfortably inside the 3 s
   target. Recipe B adds intent-dispatch overhead (Siri/Shortcuts → App Intents → `InboxWriter`),
   expected **under 1.5 s**, since it deliberately skips vault loading/indexing.
3. If either exceeds 3 s on-device, the usual causes are the iCloud folder permission prompt (see
   Troubleshooting) or an evicted `Inbox/` folder forcing a download before the write completes —
   both are one-time costs after the first successful run, not a steady-state 3 s miss.
