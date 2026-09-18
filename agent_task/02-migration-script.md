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

_(fill in when done)_
