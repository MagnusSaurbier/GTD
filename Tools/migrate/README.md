# GTD vault migration

A one-time script that brings an existing Obsidian vault into the layout and frontmatter
schema the GTD app expects (`docs/ARCHITECTURE.md` §3, `docs/REQUIREMENTS.md` §11).

It is **dry-run by default**, makes a **full backup before `--apply`**, and **never deletes
anything** — removed duplicates and files it moves out of their old location only ever exist
in the backup after that, never nowhere.

Requires Python 3.9+. Standard library only; if [PyYAML](https://pyyaml.org/) happens to be
installed it's used to read `projects.decisions.yaml` (a script-owned control file, not a vault
note), otherwise a small built-in parser handles that one file instead.

## The 3-step flow

### 1. Dry run

```sh
python3 migrate.py --vault /path/to/your/vault
```

This **only** writes `<vault>/migration-report.md` — it does not touch any note, and it does
not create backups, folders, or anything else. Read the report. It has two lists:

- **Changes (planned)** — every write/move/removal the script would make, one line per file,
  tagged with the rule that caused it (`M1`–`M6`, plus `Config`, `Routines`, `Folders` for the
  scaffold it creates).
- **Needs a decision** — everything it found but refused to guess at: an unknown `contexts`
  value, a legacy `01_Next_Actions` file that isn't a duplicate of anything in `Actions/`, a
  dangling `[[wikilink]]` in `Inbox.md`, or a `Projects/` folder it can't classify (see step 2).

Run it as many times as you like; it never writes anything but the report until you pass
`--apply`.

### 2. Resolve every "needs a decision" item

Most of these you fix by hand in the vault (rename an unknown context, decide what to do with
a non-duplicate legacy action) and they'll disappear from the report next dry run.

**Projects/ classification (M5)** is different: the script proposes area vs. project for each
top-level `Projects/*` folder (heuristic: has subfolders → area, otherwise → project) but never
acts on a proposal by itself. Create or edit `<vault>/projects.decisions.yaml` — the report gives
you the exact line to add for each undecided folder:

```yaml
Projects/Applications: area
Projects/Karriereplanung: project
```

Keys are vault-relative paths; values are `area` or `project`. Only listed, top-level folders are
read from this file — a project nested inside an area (e.g. `Projects/Applications/DAAD`) is
classified automatically once its area is decided, unless it already has its own note (see below).
Re-run the dry run to confirm the report is happy with your decisions before applying.

### 3. Apply

```sh
python3 migrate.py --vault /path/to/your/vault --apply
```

This first copies every folder it might touch (`Actions/`, `Actions_legacy/`, `Projects/`,
`Inbox.md`) into `<vault>/../GTD-migration-backup-<timestamp>/`, **and refuses to make any
change at all if that backup fails.** Only then does it perform the plan and rewrite
`migration-report.md` to say what actually happened.

Running `--apply` again is safe: once every "needs a decision" item is resolved, it reports
**zero changes** (idempotent). Items still needing a decision are reported again every run —
that's just a reminder, not a change.

## What each rule does (REQUIREMENTS §11)

| Rule | What it does |
| --- | --- |
| M1 | Normalizes `Actions/` frontmatter: maps legacy context tags to the closed enum, turns a `10min` context into `timeEstimate: 10`, drops `live`, removes a `timeEstimate: 0`, removes `priority`/`type`/`tags`/`Ressources` and a default-empty `scheduled`, and turns `status: to-do` into `status: backlog` + a `reviewReason` explaining why. Unknown context values are left untouched and reported, never guessed. |
| M2 | Imports `Actions_legacy/03_Waiting` (→ `status: waiting`, empty `waitingFor`/`followUpDate`) and `04_Maybe` (→ `status: maybe`) into `Actions/`, with a `reviewReason`, boilerplate-only bodies cleared, and the same M1 frontmatter cleanup applied. |
| M3 | Removes files in `Actions_legacy/01_Next_Actions` that duplicate a note already in `Actions/` (same title or same normalized body). Anything left over is reported for a manual decision. `02_Done` is never touched. |
| M4 | Turns each non-blank line of `Inbox.md` into its own file in `Inbox/`, timestamped 1 second apart to preserve order; `[[wikilinks]]` with no matching note anywhere in the vault are reported as dangling. |
| M5 | Classifies `Projects/*` folders into areas vs. projects from `projects.decisions.yaml` (step 2 above) and creates the index note (`kind`, and `status: active` + empty Outcome/Why/Steps/Log sections for a project). A folder that already has its own note is left alone. |
| M6 | Any action note (original, or freshly imported by M2) whose `# Why?` and `# What?` sections are both empty is moved to `Inbox/` as a plain capture, titled after the note. |
| — | Also creates `GTD/Config.md` (default contexts/cap), `GTD/Routines/Morning.md` and `Bedtime.md` (split out of `Actions_legacy/zz_templates/Dayplan_template.md` by its `## Morning` / `## Bedtime` headings — review the placeholder `time:` the script picks), and the empty `Archive/`, `Knowledge/`, `Inbox/`, `GTD/Reviews/`, `GTD/RoutineLog/`, `GTD/Trash/` folders from the vault layout. Anything it already finds in place is left as-is. |

## Review checklist before you run `--apply` on your real vault

1. Read the dry-run `migration-report.md` end to end, not just the counts.
2. For every **M1** unknown-context item: either rename the context in the note, or add it to
   the app's context list later — the script will not guess a mapping for you.
3. For every **M3** non-duplicate legacy action: decide by hand whether to keep it (move it into
   `Actions/` yourself), file it elsewhere, or leave it in `Actions_legacy/` for now.
4. For every **M4** dangling link: fix the link or accept that the capture will reference a note
   that doesn't exist yet.
5. Fill in `projects.decisions.yaml` for every **M5** item and re-run the dry run until that
   section is empty (or you're deliberately leaving some folders for a later run).
6. Skim the **Changes (planned)** list once more for anything that looks like the wrong call
   for your vault — this script encodes one specific person's migration rules, not universal
   ones.
7. Have someone (or another session, at higher reasoning effort) re-read `migrate.py` once,
   focused on the frontmatter edits — that's the one part of this script where a bug could
   corrupt a note's data instead of just misfiling it.
8. Only once all of that looks right: run with `--apply`, then read the applied
   `migration-report.md` and spot-check a handful of the changed files in the vault (and that
   the backup directory next to the vault has everything you'd want to recover).
9. If anything looks wrong after `--apply`, nothing was deleted — restore the affected files
   from `<vault>/../GTD-migration-backup-<timestamp>/` by hand.

## Tests

```sh
pytest
```

Runs entirely against the synthetic fixture vault in `tests/fixtures/vault/` (copied into a
temp directory per test — the checked-in fixture is never mutated). This script must never be
pointed at a real vault by an agent; only a human runs it there, after reading the dry-run
report themselves.
