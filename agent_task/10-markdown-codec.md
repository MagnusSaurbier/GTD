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

_(fill in when done)_
