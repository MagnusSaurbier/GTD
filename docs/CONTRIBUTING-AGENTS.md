# How to make a change in this repo

For agents and for future-you. `CLAUDE.md` holds the invariants; this file holds the routes
through the code for the four changes that come up most. Read the README of every module you
touch first — they are short and they carry the traps.

Four things are true of every change:

- **It has a GitHub issue before it has a branch.** `docs/TICKETS.md`: open the issue, label it
  `in progress`, set **Branch:** and claim the next free **Version:** (also in `App/Version.xcconfig`)
  when you start, keep **State** and **Remaining** current
  before every push, write **Outcome** and `Closes #N` in the PR. The issue is how the next
  agent continues if this session dies; `scripts/check-tickets.sh` fails when it is missing or
  older than the branch's code.
- **Check `docs/REQUIREMENTS.md` §12 first.** If what you are being asked for is on that list —
  an energy field, LLM suggestions, Calendar sync, recurring actions, timers — it is out of scope
  by decision, not by omission. Say so before you build it, and build it only if the user says to.
- **`scripts/check.sh` exits 0 before you report done.** No disabled tests, no skipped
  assertions. Report a failure verbatim rather than working around it.
- **A change that makes a document untrue includes the fix to that document** — `CLAUDE.md`,
  `README.md`, `docs/ARCHITECTURE.md`, `docs/TRACEABILITY.md`, `docs/KNOWN_ISSUES.md`, the module
  README. That is what keeps the next session from being misled.

There is no "frozen" file any more. `Package.swift` and the module contracts can change; they
just cannot change *quietly*, because other targets and this documentation depend on them.

## Add a field to the action schema

The longest route in the codebase, and the one where a mistake reaches the user's notes. In order:

1. **`GTDModel`** — add the property to `Action` (`Entities/Entities.swift`) and, if the user can
   set it while filing, to `ActionDraft` (`Commands/Commands.swift`, where the drafts live).
   Undecided must be representable as empty (`nil`, `[]`, `""`); a zero or a `false` that means
   "not decided" is the lying default STYLEGUIDE §1 forbids.
2. **`GTDMarkdown`** — add the key to `NoteCodec.Keys`, read it in `decodeAction`, write it in
   `encode(_ action:)`, and add it to `NoteTemplates.action` if a fresh note should carry it.
   Remember the patching model: you write a *value*, the encoder decides whether the line changed.
3. **Round-trip tests first, then the rest.** `GTDMarkdownTests` is the guarantee behind N2:
   `RoundTripTests` (a file with the key, and one without), `FidelityTests` (awkward values:
   colons, quotes, `true`, `07:00`, umlauts), `PatchTests` (changing only this field changes only
   this line). `FuzzRoundTripTests` does **not** pick a new key up by itself: it builds its notes
   from its own generator and walks its own mutation table, so add the key to both — that is what
   gets it into the ~1 800 generated notes and the damaged-file sweep.
4. **`GTDModel/Reducer` and `Rules`** — if the field has semantics (it changes what is visible,
   what counts toward the cap, what is stalled), they live here and nowhere else. Add the
   validation to the reducer and a query to `Rules`; test both in `GTDModelTests`.
5. **`GTDFixtures`** — put the field on at least one action in `SampleSnapshot.swift`, then
   regenerate the committed sample vault (the command is in `CLAUDE.md`). A test fails if you
   forget; that test is the point.
6. **UI** — a chip or row in `DesignSystem` if it is shown in more than one place, the wording in
   `DesignSystem.Copy`, then the feature views. Feature code holds no literal string or size.
   To find every place a field would show up, use `docs/TRACEABILITY.md`: it names the module and
   the view for each requirement, so "where are an action's chips drawn?" is one lookup (I3 for
   the inbox card, E3 for the Mac editor) rather than a grep.
7. **Migration** — `Tools/migrate/` only if existing notes need the key written or cleaned up.
   Anything the script cannot decide must be *reported*, never guessed. Say in
   `docs/MANUAL_TEST.md` §9 if the user has to re-run it.
8. **Docs** — the schema table in `docs/ARCHITECTURE.md` §3, the module READMEs you touched, and
   `docs/TRACEABILITY.md` if a requirement's status moved.

## Add a `GTDCommand`

1. Add the case to `GTDCommand` (`GTDModel/Commands/Commands.swift`) with the smallest payload
   that says what the user decided — not what the files should become.
2. Handle it in `Reducer.reduce`: validate (throw a `GTDError` the UI can show), mutate the
   snapshot, emit `prompts` and `extraOps`. **A path you name in `extraOps` is yours** — the
   snapshot diff will not touch it (ARCHITECTURE §4).
3. Decide whether it is undoable: `Rules.isUndoable`, plus a label in `GTDAppCore/UndoLabel`.
   One definition, both backends.
4. Tests in `GTDModelTests` (the happy path, every refusal, idempotency), and — if it writes
   files in a new shape — one in `GTDServicesTests` that drives it through the real stack
   (`AppModel` → `VaultBackend` → `FileVaultStore`) against a temp copy of the sample vault.
5. Call it from the UI with `AppModel.send` when the view has its own flow for the refusal, or
   `perform`/`report` when the shell's alert should show it. Never `try?`.

## Add or change a view

1. The logic goes in a **Linux-compilable** file (no `import SwiftUI`) — a session or list model
   like `InboxSession` or `NextListModel` — and is unit-tested. The view file is wrapped
   **entirely** in `#if canImport(SwiftUI)` and holds no decisions. This is what makes anything
   testable here at all (ARCHITECTURE §5).
2. Use `DesignSystem` for every token, component, symbol and user-facing string. If something is
   missing, add it there rather than a literal in the feature.
3. Run the STYLEGUIDE §9 checklist, including the accessibility rows: every swipe action needs a
   context-menu or keyboard twin, every badge reads in words, Dynamic Type must grow rather than
   clip (`@ScaledMetric`, not fixed frames).
4. You cannot compile it here. Say so in your report, list the files, and add anything genuinely
   risky to `TEST-INSTRUCTIONS.md`'s list rather than hoping.

## Add a target

1. Declare it in `Packages/GTDKit/Package.swift` with `exclude: excluded` (the README),
   `swiftSettings`, and `resources: uiResources` if it is a UI target with a string catalog.
   Add a test target next to it and put the target in the `GTDKit` product.
2. Respect the direction of ARCHITECTURE §2: features depend on `GTDAppCore` + `DesignSystem`
   (+ `GTDFixtures` for previews) and never on `GTDVault`/`GTDServices`. No cycles.
3. Write `Sources/<Target>/README.md` (≤ 40 lines: purpose, entry points, invariants, gotchas)
   and add the target to ARCHITECTURE §2's list.
4. Keep at least one Linux-compilable file in it, or the target is untestable here.
5. A new *app-level* target (a widget or an App Intents extension, say) is a `project.yml` change
   and cannot be verified without Xcode — see `docs/follow-ups/52-notification-actions-and-widget.md`.

## Before you say you are done

- `scripts/check.sh` exits 0, and you pasted the tail of it into your report.
- The issue body says what is committed, pushed, verified and left, with the PR URL in **PR**
  and **Outcome** filled in. The PR body says `Closes #N`. A docs-only commit ends with `[skip ci]`.
- The tests you added fail when you break the thing they test. Check it once; a test that cannot
  fail is worse than no test.
- Docs that your change made untrue are fixed in the same commit.
- Anything you could not verify — every SwiftUI file, anything needing a device — is named in
  your report, not left for someone to discover.
