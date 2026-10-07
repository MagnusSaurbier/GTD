# GTDMarkdown

Markdown ⇄ model: YAML frontmatter and `# Heading` body sections, via Yams. The only target that
parses or produces note text. Formats: `docs/ARCHITECTURE.md` §3, REQUIREMENTS §5.

## How it stays lossless (N2)

`encode(decode(text)) == text`, byte for byte — including unknown keys and their order, unknown
body sections, comments, CRLF, a missing final newline, a BOM and `---` inside the body.

Reading goes through Yams (quoting, flow/block styles, escapes). **Writing never re-serialises.**
`decode` stashes the whole original file in `NotePassthrough`; `encode` decodes that original again
into a *reference* entity and patches only the **lines whose decoded value actually changed**.
So a field nobody touched cannot be reformatted, and changing one field changes one line.

An entity with an empty passthrough (one the app just created) is rendered from `NoteTemplates`
and then patched the same way.

## Public API

- `NoteCodec.decode*` / `encode(_:)` per entity + `encodeRoutineLog`, `noteKind(text:)`,
  `decodeListItem(id:text:layout:timeZone:)` — a list item's list and its finished flag come
  from the path (§5a), so it takes the layout rather than reading a key that does not exist —
  `routineLogName`, `unknownContexts(in:known:)`, `Keys`, `Headings`.
  `decode*`/`encode` take an optional `timeZone:` (default `.current`) for timestamps.
- `FrontmatterDocument` — split, read (`scalar`/`list`/`int`/`day`/`timestamp`/`mappings`),
  patch (`setValue`/`setLines`/`removeValue`/`setBody`).
- `BodySections`, `CheckboxList`/`CheckboxItem`, `Wikilink`, `RawText`/`RawLine`, `YAMLScalar`.
- `NoteCodecError.unreadable(path:reason:)` → `.vaultIssue` for `GTDVault` to surface.

## Invariants

- `timeEstimate: 0` decodes as *undecided* and is never written (§1 "no lying defaults"); an
  existing `0` in a file is left alone rather than rewritten. `waitingFor:` is the same kind of
  field (W1/D39): an action with no who writes **no line**, and clearing the who removes the line
  and nothing else.
- **An action's body is read and written whole** (2026-09-24). `decodeAction` hands the text
  below the frontmatter to `Action.body`; `encode` writes it back — `RawText.block` with the
  file's terminator — only when it differs from the stored file's body, so an untouched body
  keeps every byte. Which part of it is the `What?` or the lead paragraph is `GTDModel.NoteBody`'s
  business, not the codec's (the two share one heading grammar). A note being *moved* into
  `Actions/` (a promoted list item, L4) arrives with the item's notes already at the top of its
  body, put there by the reducer.
- **Legacy `status:` words are read, never rewritten** (R-1): `backlog` and `maybe` decode as
  `.someday`, `trash` as `ActionStatus.legacyTrashed`. Because the encoder patches only lines
  whose *decoded* value changed, such a file keeps its own word on disk until the status really
  changes. `ActionStatus.acceptedRawValues` is what the error message lists.
- **A legacy `defer:` reads as waiting** (#86): `decodeAction` folds an open non-Someday note's defer date
  into `status: waiting` + that follow-up date with no who (`Action.foldingDeferIntoWaiting`;
  a waiting note keeps its own who and date). `encode` patches against that folded reading, so
  an untouched note keeps every byte; once anything changed it also writes the folded lines for
  real against `decodeStoredAction` (the file as written): `status: waiting`, `followUpDate:`,
  and no `defer:`. Closed and Someday notes keep their `defer:` as written (a deferred Someday item stays Someday).
- `CheckboxList.parseLine` accepts exactly what `GTDModel.Checkbox.scan` accepts (`-`/`*`, a
  space, `[ ]`/`[x]`/`[X]`) — the reducer indexes checkboxes with the model's scanner.
- Refused rather than guessed (each throws `.unreadable` with path + reason): unknown or missing
  `status` (a word outside `ActionStatus.acceptedRawValues`), invalid YAML, duplicate frontmatter keys, a routine `time` that is not `HH:mm` or a `day` that is not a weekday name, an unknown routine-step `result`, a routine
  log file whose name is not `<yyyy-MM-dd>--<device>.md`, an inbox item without `created`, and
  a routine log whose `entries:` is something other than a list or empty — reading that as
  "no entries" would let the next logged step regenerate the file over the day's history.
  Unknown *contexts* are kept as written — nothing is lost, so they are reported, not refused.
- `Action.modified`, `Project.referenceFiles` and note titles come from the file system, not the
  file text; the codec never writes them.
- **A list item is allowed to have no frontmatter at all** (§5a): `created` is optional and
  nothing else is written, so a note typed in Obsidian is a valid item. Only a path that is not
  `<lists>/<list>/[Done/]<note>.md` is refused.
- `GTDConfig.favouriteLists` is `Optional` in the file too (R-5): the key is absent until the
  user chooses, `[]` is a real choice, and the derived default is never written.

## Gotchas

- Swift treats `"\r\n"` as one `Character`. Split lines with `RawText.split` (unicode scalars),
  never with a `Character` scan.
- `encodeRoutineLog` regenerates the file (entries sorted by `at`) — it is the one encoder that
  does not patch, because `[RoutineLogEntry]` has no passthrough. It writes `at` in the given
  time zone, so pass the same one when comparing output.
- `encode(_ action:)` rewrites the body as one block when its text changed, so a body with
  *mixed* line endings comes out uniform (the file's dominant terminator) after an edit, and its
  trailing blank lines are dropped. Frontmatter lines are still patched one by one.
- A key hidden inside a multi-line quoted scalar confuses the line scanner. Reading is still
  correct, and nothing breaks because only the schema's own keys are ever patched.

## Testing

`cd Packages/GTDKit && swift test --filter GTDMarkdownTests` (145 tests, Linux-clean).
`RoundTripTests` covers every `GTDFixtures.SampleVault` file plus ~40 hand-written nasty cases;
`FidelityTests` covers the other direction (what is written reads back unchanged);
`FuzzRoundTripTests` generates ~1 800 notes from a seeded PRNG — shuffled key order, block
vs flow lists, nested mappings, block scalars, comments, unknown keys, unknown and oddly-spelled
headings, CRLF, BOM, no final newline — and asserts both halves of N2 on each, then damages every
sample-vault file twelve ways and requires each result to round-trip or be refused. A failing
`#expect` prints the seed; `Fuzz(seed:)` reproduces that one note.

Two rewrites of a damaged file are deliberate and pinned by those tests: a note that lost its
`kind:` gets it back (otherwise it cannot be classified at all), and a file whose frontmatter
lost its closing `---` gets a fresh frontmatter block **above** its unchanged text.
