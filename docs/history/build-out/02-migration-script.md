# T02 — One-time vault migration script

**Wave 0 · fully independent of the Swift code**

## Model recommendation

**Difficulty:** Medium · **Recommended model:** Sonnet

Python + pytest against a synthetic fixture vault, rules spelled out one by one, dry-run by default, full backup before `--apply`, nothing deleted. Well inside Sonnet's reliable range. Safety net: before the user runs `--apply` on the real vault, have an Opus pass (or `/code-review`) read the script once — the only real risk is format-preserving YAML edits, and the dry-run report exposes those.

## Goal

A reviewable, idempotent, dry-run-by-default Python script that brings the existing vault into
the layout and schema the app expects.

## Requirements covered

All of §11 (M1–M6), schema in §5, layout in ARCHITECTURE §3.

## Owns

`Tools/migrate/` (`migrate.py`, `README.md`, `tests/`, `tests/fixtures/`).

## Behaviour

- `python3 migrate.py --vault <path>` → **dry run**: prints a per-file plan and writes
  `migration-report.md` (counts per rule, every file touched, every decision it could not make).
- `--apply` performs it, after creating a full timestamped backup copy of the affected folders
  next to the vault (`<vault>/../GTD-migration-backup-<ts>/`). Refuse to run `--apply` if the
  backup fails. Nothing is ever deleted: removed duplicates and replaced files go to the backup.
- Idempotent: a second run reports zero changes.
- Python 3 stdlib + `pyyaml` (or `ruamel.yaml` if needed to preserve formatting). Preserve
  unknown frontmatter keys and note bodies exactly.

## Rules (from §11)

- **M1** `Actions/`: contexts → closed enum (`@Mac`→`mac`, `Phone`→`phone`, `Home`→`home`,
  `tum-stammgelände`→`campus`, `readlist`→`reading`, `conversations`→`calls`; `10min` →
  `timeEstimate: 10` and removed from contexts; drop `live`); `timeEstimate: 0` → key removed;
  remove `priority`, `type`, `tags`, `Ressources`, and `scheduled` when it is the TaskNotes default;
  `status: to-do` → `backlog` **plus** `reviewReason: "migrated from to-do — decide Next vs Backlog"`
  (the Next/Backlog decision is made by the user in the first review, respecting the cap).
  Unknown context values are reported, not guessed.
- **M2** `Actions_legacy/03_Waiting` → `Actions/` with `status: waiting`, `waitingFor`/`followUpDate`
  left empty + `reviewReason`; `04_Maybe` → `status: maybe`; strip bodies that are only empty
  template boilerplate.
- **M3** duplicates between `Actions_legacy/01_Next_Actions` and `Actions/` (same title or same
  normalized body) are moved to the backup; non-duplicates are reported for manual decision.
  `02_Done` untouched.
- **M4** each non-empty line/bullet of `Inbox.md` → one file in `Inbox/` (timestamp filename,
  `created` = migration time, staggered by 1 s to keep order); dangling wikilinks are listed in the report.
- **M5** `Projects/`: create `<Folder>/<Folder>.md` with `kind:` **left for the user** — the script
  writes a proposal table (area vs project, heuristics: has subfolders → area) into the report and
  reads decisions back from a `projects.decisions.yaml` the user edits; only then creates the notes
  (`kind`, `status: active`, empty Outcome/Why/Steps/Log sections).
- **M6** action notes with empty `# Why?` and `# What?` → moved to `Inbox/` as captures with their title as text.
- Also create `GTD/Config.md` (defaults), `GTD/Routines/Morning.md` + `Bedtime.md` from
  `Actions_legacy/zz_templates/Dayplan_template.md`, and the empty folders from ARCHITECTURE §3.

## Acceptance

- `pytest` suite over a synthetic fixture vault covering every rule, idempotency, backup creation, and "unknown value → reported, untouched".
- The agent runs the script **only** against fixtures. It must not read or write the user's real vault; the user runs the dry run themselves.
- README explains the 3-step flow: dry run → edit `projects.decisions.yaml` → `--apply`.

## Result

**Status: done.** `Tools/migrate/` contains `migrate.py` (CLI + all rule logic), `frontmatter.py`
(a hand-rolled, format-preserving YAML-frontmatter line editor), `README.md`, and a `tests/`
suite run against a synthetic fixture vault under `tests/fixtures/vault/` (never a real vault).

### What was built

- `frontmatter.py`: parses only the frontmatter subset this vault actually uses (scalars, flow
  lists `[a, b]`, block lists `- item`); every other line (comments, unknown keys, unknown
  structures) is an opaque passthrough that round-trips byte-for-byte. Editing one key never
  changes any other line's bytes — verified directly in `tests/test_frontmatter.py`.
- `migrate.py`: a pure `plan(vault, now, decisions_path) -> (Report, list[Op])` (read-only, no
  filesystem writes) followed by `make_backup` + `execute_ops` only under `--apply`. Dry run
  writes nothing but `migration-report.md`. All of M1–M6 plus `GTD/Config.md`,
  `GTD/Routines/{Morning,Bedtime}.md` (parsed from `Dayplan_template.md`'s `## Morning`/
  `## Bedtime` headings) and the empty scaffold folders (ARCHITECTURE §3) are implemented.
  `--apply` backs up `Actions/`, `Actions_legacy/`, `Projects/`, `Inbox.md` into
  `<vault>/../GTD-migration-backup-<ts>/` (atomic temp-dir + rename; refuses to touch the vault
  at all if the backup raises) before executing anything.
- M1 and M2 (and the M6 empty-body check) run as one unified in-memory pass
  (`collect_action_documents` / `plan_actions`) rather than three independent passes over disk.
  This matters for idempotency: an imported `Actions_legacy/03_Waiting` note whose body turns out
  to be only boilerplate is stripped to empty *and* routed straight to `Inbox/` in the same
  `--apply`, instead of first landing in `Actions/` and only being swept to `Inbox/` on a second
  run.
- `pytest`: **40 passed** (`tests/test_frontmatter.py` unit-tests the editor in isolation;
  `tests/test_migrate.py` covers every rule, unknown-value reporting without guessing, backup
  creation + refusal-on-failure with no partial mutation, full-migration idempotency, and two CLI
  subprocess smoke tests). Run: `cd Tools/migrate && pytest -q` → `40 passed in 0.42s`.

### Deviations / assumptions (none of these are in the brief verbatim; flagged for review)

- `status: to-do` → `backlog` + `reviewReason` (brief's own Behaviour/Rules section) rather than
  REQUIREMENTS §11's older wording ("`to-do` → `next`/`backlog`, decided in review") — the task
  brief is more specific and was treated as authoritative.
- "TaskNotes default" `scheduled` is treated as: key present with an empty/null value. A
  non-empty `scheduled` value is left alone (not covered by the brief's wording either way).
- `projects.decisions.yaml` is **read** if present at `<vault>/projects.decisions.yaml` but never
  auto-generated by the script (the brief says the dry run's only write is the report); the
  report instead prints the exact `path: area|project` line to add for every undecided folder.
  Keys are full vault-relative paths (e.g. `Projects/Applications`), matching how every other
  rule reports paths.
- "Boilerplate" body (M2) = both `# Why?` and `# What?` sections are blank or one of a small
  placeholder set (`...`, `tbd`, `todo`, `n/a`, `-`).
- Routine `time:` defaults are placeholders (Morning `07:00`, Bedtime `22:00`) since neither the
  brief nor `Dayplan_template.md` specifies exact times; the report flags them "review". If the
  template lacks a `## Morning`/`## Bedtime`-ish heading (or the template file is missing
  entirely), that routine is reported unresolved instead of fabricated.
- M3 duplicate detection = same normalized filename stem **or** same whitespace-normalized body
  text; `Actions_legacy/02_Done` is never read at all (brief: "untouched").
- PyYAML is used only for `projects.decisions.yaml` (a script-owned control file, not a vault
  note) with a small built-in fallback parser if it's absent (this repo has it installed, but
  the test suite's own `pytest` runs in a separate interpreter without it, so both code paths are
  exercised by the suite as-is).

### Gate

No `scripts/check.sh` exists in this worktree (T00/Wave 0's scaffold task hasn't landed here;
T02 is independent of it per `agent_task/README.md`'s wave diagram). Ran the gate the brief
itself specifies instead:

```
cd Tools/migrate && pytest -q
........................................                                 [100%]
40 passed in 0.42s
```

Also exercised the CLI directly end-to-end against a scratch copy of the fixture vault (dry run
→ `--apply` → `--apply` again): report counts, backup contents and idempotency all matched
expectations; output is not pasted here per the "no long logs" instruction.

### Open issues

- Never run against a real vault by design; a human must do the dry run themselves and read the
  report before anyone runs `--apply`.
- If the real vault's `contexts`/`scheduled`/legacy folder conventions differ from what's encoded
  here in ways the fixtures don't cover, the dry-run report is the safety net — every value this
  script doesn't recognize is reported, never guessed.
