# T10 — Markdown codec (`GTDMarkdown`)

**Wave 1 · needs T00**

## Model recommendation

**Difficulty:** Hard · **Recommended model:** Opus

Byte-for-byte lossless round-tripping is deceptively hard: Yams re-serialisation does not preserve formatting, so this needs a line-level patching strategy designed up front, plus tolerant parsing of legacy TaskNotes data. Bugs here silently corrupt the user's notes on every write. Sonnet tends to get the happy path and miss the nasty cases (CRLF, `---` in body, key order, empty keys).

## Goal

Lossless conversion between vault markdown files and `GTDModel` entities.

## Requirements covered

N2, §5 schema, P2, R1, R5, §1 "no lying defaults". Formats: ARCHITECTURE §3.

## Owns

`Packages/GTDKit/Sources/GTDMarkdown/`, `Tests/GTDMarkdownTests/`.

## Deliverables

- `FrontmatterDocument`: splits a file into YAML frontmatter + body; keeps the original YAML node
  tree (Yams `Node`) so unknown keys, their order and their formatting survive a re-encode. Files
  without frontmatter are valid.
- `BodySections`: splits a body into `# Heading` sections, preserving unknown sections and
  pre-heading text byte-for-byte. Case-insensitive match for `Why?`, `What?`, `Outcome`, `Steps`, `Log`.
- `NoteCodec` decode/encode for: `InboxItem`, `Action`, `Area`, `Project`, `Routine`,
  routine-log day file, `GTDConfig`; encode-only for `WeeklyReview`.
  `NotePassthrough` carries whatever is needed for lossless re-encoding.
- Checkbox parsing (`- [ ]`, `- [x]`, `* [ ]`, tab/space nesting) shared by actions, project steps
  (incl. `→ [[Action]]` promotion suffix) and routine templates (nested items = sub-steps).
- Wikilink helpers: `[[path|alias]]` ⇄ `NoteID`, tolerant of missing `.md` and of bare titles.
- Date handling: `Day` as `yyyy-MM-dd`; timestamps ISO-8601 with offset; accept the TaskNotes
  formats found in the vault (e.g. `2026-09-13T23:20:17.632+02:00`).
- Tolerant decoding: legacy/unknown `status` or context values decode into a `VaultIssue`-friendly
  thrown error with path + reason — never crash, never coerce silently.

## Acceptance

- Property-style round-trip tests: `encode(decode(text)) == text` for every file in
  `GTDFixtures/SampleVault` and for hand-written nasty cases (CRLF, no trailing newline, empty
  frontmatter, `---` inside body, unicode/umlaut titles, tabs).
- Changing one field changes only that key's line in the output.
- Empty optional fields are omitted or left as empty keys as found — `timeEstimate: 0` is never emitted.
- `scripts/check.sh` passes.

## Result

**Status: done.** `scripts/check.sh` passes; `GTDMarkdownTests` has **108 tests**, all Linux-clean.

### Strategy (decided up front, as the brief asks)

Reading goes through Yams; **writing never re-serialises**. `decode` stashes the whole original
file in `NotePassthrough["source"]`. `encode` re-reads that original, decodes it *again* into a
**reference entity**, and patches only the lines whose *decoded value* differs from the entity's.
Two consequences fall out for free:

- `encode(decode(text)) == text`, byte for byte — a field nobody touched is never rewritten, so
  formatting, key order, comments, unknown keys and unknown sections cannot be disturbed.
- changing one field changes exactly one line.

Entities with an empty passthrough (created by the app) render from `NoteTemplates` and are then
patched the same way, so new files have the same shape as existing ones.

### What was built

- `RawText`/`RawLine` — line splitting that keeps each line's own terminator, on **unicode
  scalars** (Swift merges `"\r\n"` into one `Character`; a `Character` scan silently breaks CRLF).
- `FrontmatterDocument` — `---` split (only line 0 may open it), Yams for reading
  (`scalar`/`list`/`int`/`day`/`timestamp`/`mappings`/`mappingNode`), a top-level key-line scanner
  for patching (`setValue`/`setLines`/`removeValue`/`setBody`), insertion in schema order without
  moving existing keys, BOM and `...` terminator support.
- `BodySections` — split at level-1 ATX headings, fenced code aware, case/punctuation-insensitive
  matching (`Why?` ≡ `why`), patching that keeps the heading line and the blank line before the
  next section.
- `CheckboxList`/`CheckboxItem` — nesting from visual indent (tab = 4 columns), `→`/`->`
  promotion suffix, shared by actions, project steps and routine templates.
- `Wikilink` — `[[path|alias#heading]]` ⇄ `NoteID`, tolerant of a missing `.md` and of bare titles
  (`isBare` tells `GTDVault` it still needs resolving).
- `YAMLScalar` — hand-written quoting and ISO-8601 (not `ISO8601DateFormatter`, whose output
  differs between Apple Foundation and corelibs). Accepts `…T23:20:17.632+02:00`, `Z`, `±HHmm`,
  `±HH`, a space separator, and no offset at all.
- `NoteCodec` — decode + encode for inbox, action, area, project, routine, routine log, config,
  weekly review; `noteKind(text:)` for dispatch, `routineLogName`, `unknownContexts(in:known:)`,
  `Keys`/`Headings`, `NoteCodecError.vaultIssue`.

### Tests

- `RoundTripTests` — every file of `GTDFixtures.SampleVault` (both the rendered and the committed
  on-disk copy), ~40 hand-written nasty cases (CRLF, mixed endings, no trailing newline, empty/no
  frontmatter, `---` in the body, `...` terminator, BOM, comments, empty keys, block sequences,
  folded/literal scalars, quoted keys, unknown keys and sections, tabs, umlauts/emoji/CJK, fenced
  code with a `#` heading, duplicate headings, `timeEstimate: 0`), each also through **three**
  consecutive round trips.
- `PatchTests` — one field changed ⇒ one line changed, on a note stuffed with unknown keys,
  comments and unknown sections; CRLF preserved while patching; promotion, log append, routine
  time, config cap.
- `FidelityTests` — the other direction: 20 awkward strings (`with: a colon`, `true`, `07:00`,
  `- dash`, quotes/backslashes, umlauts/emoji) through every free-text field, plus every field of
  every entity, plus "edit every sample-vault action in every field and read it back".
- `EncodeFromScratchTests` — fresh entities render the §3 format, and encoding
  `Fixtures.sampleSnapshot` reproduces the committed sample vault **byte for byte** (this caught
  three real encoder bugs; see below).
- `DecodeTests`, `PrimitiveTests` — field-level decoding, refusals, and the line machinery.

### Deviations and decisions (the user could not be asked)

1. **Missing or unknown `status` is refused** (`NoteCodecError.unreadable`, → `VaultIssue`), for
   actions and projects. Guessing a tier is exactly the lying default §1 forbids. Consequence:
   a hand-made note in `Actions/` without `status` shows up as an issue rather than as an action.
2. **Unknown *context* values are kept, not refused.** `contexts` is `[String]`, so nothing is
   coerced or lost; refusing would hide the action entirely. `NoteCodec.unknownContexts(in:known:)`
   lets `GTDVault` raise a `VaultIssue` without losing the note. (The brief lumps contexts in with
   status; this is the deliberate split.)
3. **`timeEstimate: 0`** decodes as undecided and is never emitted — but an existing `0` in a file
   is *left as found* rather than deleted, because losslessness wins ("left as empty keys as found").
4. **A note with neither `# Why?` nor `# What?`** is read as all-`What?`, and written back the same
   way, so hand-written notes are not shown empty.
5. **`encodeRoutineLog` regenerates** instead of patching — `[RoutineLogEntry]` has no
   passthrough and the file is app-owned and append-only. It sorts by `at`.
6. **Duplicate frontmatter keys** are refused (Yams rejects them); surfaced as a `VaultIssue`.
7. `CheckboxList.parseLine` was deliberately narrowed to exactly what `GTDModel.Checkbox.scan`
   accepts (no `+` bullets, space after the bullet), because the reducer's `toggleCheckbox`
   indexes checkboxes with the model's scanner. A test pins the two together.
8. Project steps are parsed flat (nesting under a step is flattened *if the steps change*);
   `ProjectStep` has no depth and the Steps UI is flat (P4).

### Bugs the parity test caught (worth knowing)

Encoders originally built the reference entity by decoding the *template* when an entity had no
passthrough. For the decoders that never fail (area, config, review) the template decoded to the
same values as the entity, so **nothing was written at all** — a new area/config/review note came
out empty. Fixed: no stored source ⇒ no reference ⇒ every field is written.

### Contract changes

| # | Change | Where |
| --- | --- | --- |
| T10-1 | Every `decode*`/`encode` that touches a timestamp gained `timeZone: TimeZone = .current` (defaulted — existing call sites compile unchanged). `GTDMarkdown` also exposes `FrontmatterDocument`, `BodySections`, `CheckboxList`, `Wikilink`, `RawText`, `YAMLScalar`, `NoteCodec.noteKind/routineLogName/unknownContexts/Keys/Headings` and `NoteCodecError.vaultIssue`. | `docs/ARCHITECTURE.md` §4 (one added paragraph) |

Shared files touched: `docs/ARCHITECTURE.md` (the paragraph above) — nothing else outside
`Sources/GTDMarkdown/` and `Tests/GTDMarkdownTests/`. `NoteCodecError.notImplemented` is kept for
source compatibility but is no longer thrown.

### Notes for T15/T16

- Dispatch with `NoteCodec.noteKind(text:)` (`project`/`area`/`review`) once the folder says
  `Projects/`; everything else follows the folder.
- **Always encode from the entity you decoded**, never from a hand-built copy: the passthrough is
  what keeps the user's file intact. Copying an entity keeps its passthrough, which is correct.
- `Action.modified`, `Project.referenceFiles` and titles come from the file system; the codec does
  not read or write them.
- `Wikilink.isBare` marks `[[DAAD]]`-style links that still need resolving against the index; the
  codec turns them into `NoteID("DAAD.md")` verbatim.
- A key hidden inside a multi-line quoted scalar confuses the line scanner. Reading stays correct
  and nothing breaks, because only the schema's own keys are ever patched.

### Files that could not be compiled on Linux

**None.** `GTDMarkdown` is Foundation + Yams only; every source and test file here builds and runs
on Linux. Nothing in this task needs Mac verification beyond the repo-wide `xcodebuild` step that
`scripts/check.sh` already reports as SKIPPED.

### `scripts/check.sh`

```
=== swift build (Packages/GTDKit)
Build complete! (1.54 secs)
=== swift test (Packages/GTDKit)
Build complete! (2.29 secs)
✔ Test run with 108 tests in 6 suites passed after 0.191 seconds.   (GTDMarkdownTests)
…all other targets' suites passed…
=== docs check
checking backticked paths in CLAUDE.md README.md
checking the build-out phase marker
  ok (marker and agent_task/ agree)
check-docs.sh: ok
=== xcodebuild — package for the iOS Simulator
SKIPPED: xcodebuild not available (Linux). Asset and string catalogs are compiled by Xcode's build system only — verify this step on a Mac.
=== check.sh finished
```
