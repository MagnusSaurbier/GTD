import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest

import migrate
from frontmatter import read_note

FIXTURES = Path(__file__).resolve().parent / "fixtures"
NOW = datetime(2026, 9, 19, 12, 0, 0, tzinfo=timezone.utc)


def read(vault: Path, relpath: str) -> str:
    return (vault / relpath).read_text(encoding="utf-8")


def note(vault: Path, relpath: str):
    fm, body = read_note(read(vault, relpath))
    return fm, body


def snapshot(vault: Path) -> dict[str, str]:
    return {
        str(p.relative_to(vault)): p.read_bytes()
        for p in vault.rglob("*")
        if p.is_file() and "migration-report.md" not in p.name
    }


# --------------------------------------------------------------------------
# Dry run
# --------------------------------------------------------------------------


def test_dry_run_writes_only_the_report(vault):
    before = snapshot(vault)
    report = migrate.run(vault, apply=False, now=NOW)
    after = snapshot(vault)
    assert before == after  # nothing besides migration-report.md changed
    assert (vault / "migration-report.md").is_file()
    assert report.changed_count > 0  # there is a real plan


def test_dry_run_report_mentions_every_rule(vault):
    migrate.run(vault, apply=False, now=NOW)
    text = read(vault, "migration-report.md")
    for rule in ("M1", "M2", "M3", "M4", "M5", "M6"):
        assert rule in text


# --------------------------------------------------------------------------
# M1 — Actions/ frontmatter normalization
# --------------------------------------------------------------------------


def test_m1_maps_contexts_drops_live_and_cleans_keys(vault):
    migrate.run(vault, apply=True, now=NOW)
    fm, body = note(vault, "Actions/Call dentist.md")
    assert fm.get_list("contexts") == ["phone", "home"]
    assert fm.get_scalar("timeEstimate") is None  # was 0 -> removed
    for key in ("priority", "type", "tags", "Ressources", "scheduled"):
        assert not fm.has(key)
    assert fm.get_scalar("status") == "backlog"
    assert fm.get_scalar("reviewReason") == "migrated from to-do — decide Next vs Backlog"
    assert "Molar hurts." in body  # body untouched


def test_m1_10min_context_becomes_time_estimate(vault):
    migrate.run(vault, apply=True, now=NOW)
    fm, _ = note(vault, "Actions/Quick call.md")
    assert fm.get_list("contexts") == ["phone"]
    assert fm.get_scalar("timeEstimate") == "10"


def test_m1_unknown_context_is_reported_and_file_left_untouched(vault):
    before = read(vault, "Actions/Mystery task.md")
    report = migrate.run(vault, apply=True, now=NOW)
    after = read(vault, "Actions/Mystery task.md")
    assert before == after  # byte-identical: nothing guessed
    assert any("Bike" in msg and path == "Actions/Mystery task.md" for _, path, msg in report.unresolved)


def test_m1_already_clean_file_is_untouched(vault):
    before = read(vault, "Actions/Write report.md")
    migrate.run(vault, apply=True, now=NOW)
    after = read(vault, "Actions/Write report.md")
    assert before == after


# --------------------------------------------------------------------------
# M2 — import Actions_legacy/03_Waiting and 04_Maybe
# --------------------------------------------------------------------------


def test_m2_imports_waiting_with_empty_fields_and_review_reason(vault):
    migrate.run(vault, apply=True, now=NOW)
    assert not (vault / "Actions_legacy/03_Waiting/Wait for Bob.md").exists()
    fm, body = note(vault, "Actions/Wait for Bob.md")
    assert fm.get_scalar("status") == "waiting"
    assert fm.get_scalar("waitingFor") is None
    assert fm.get_scalar("followUpDate") is None
    assert "reviewReason" in [e.key for e in fm.entries if e.kind == "key"]
    assert fm.get_list("contexts") == ["phone"]
    assert "Waiting on Bob" in body


def test_m2_boilerplate_body_is_stripped_and_then_routed_to_inbox_by_m6(vault):
    # "Empty waiting.md"'s body is only placeholder text ("..."); once that boilerplate is
    # stripped the note has no real Why?/What? content left, so M6 sends it straight to
    # Inbox/ in the same run rather than leaving a hollow action note behind.
    migrate.run(vault, apply=True, now=NOW)
    assert not (vault / "Actions_legacy/03_Waiting/Empty waiting.md").exists()
    assert not (vault / "Actions/Empty waiting.md").exists()
    bodies = [read_note(f.read_text(encoding="utf-8"))[1].strip() for f in (vault / "Inbox").glob("*.md")]
    assert "Empty waiting" in bodies


def test_m2_imports_maybe_without_waiting_fields(vault):
    migrate.run(vault, apply=True, now=NOW)
    fm, _ = note(vault, "Actions/Maybe someday.md")
    assert fm.get_scalar("status") == "maybe"
    assert not fm.has("waitingFor")
    assert fm.get_list("contexts") == ["home"]


# --------------------------------------------------------------------------
# M3 — duplicates in Actions_legacy/01_Next_Actions
# --------------------------------------------------------------------------


def test_m3_duplicate_is_removed(vault):
    canonical_before = read(vault, "Actions/Call dentist.md")
    migrate.run(vault, apply=True, now=NOW)
    assert not (vault / "Actions_legacy/01_Next_Actions/Call dentist.md").exists()
    # the Actions/ copy is untouched by M3 itself (M1 still normalizes it, separately)
    assert (vault / "Actions/Call dentist.md").exists()


def test_m3_non_duplicate_is_reported_and_left_in_place(vault):
    before = read(vault, "Actions_legacy/01_Next_Actions/Unique legacy task.md")
    report = migrate.run(vault, apply=True, now=NOW)
    after = read(vault, "Actions_legacy/01_Next_Actions/Unique legacy task.md")
    assert before == after
    assert any(
        path == "Actions_legacy/01_Next_Actions/Unique legacy task.md" for _, path, _ in report.unresolved
    )


def test_m3_done_folder_is_never_touched(vault):
    before = read(vault, "Actions_legacy/02_Done/Old done task.md")
    report = migrate.run(vault, apply=True, now=NOW)
    after = read(vault, "Actions_legacy/02_Done/Old done task.md")
    assert before == after
    assert not any("02_Done" in path for _, path, _ in report.changes)
    assert not any("02_Done" in path for _, path, _ in report.unresolved)


# --------------------------------------------------------------------------
# M4 — Inbox.md -> Inbox/*.md
# --------------------------------------------------------------------------


def test_m4_splits_inbox_lines_into_files(vault):
    migrate.run(vault, apply=True, now=NOW)
    assert not (vault / "Inbox.md").exists()
    # 3 lines from Inbox.md (M4) + 2 captures from empty-body actions (M6: "Empty task" and
    # the imported-then-boilerplate-stripped "Empty waiting")
    files = sorted((vault / "Inbox").glob("*.md"))
    assert len(files) == 5
    bodies = []
    for f in files:
        fm, body = read_note(f.read_text(encoding="utf-8"))
        assert fm.get_scalar("created") is not None
        bodies.append(body.strip())
    assert "Buy milk" in bodies
    assert any("Call [[Nonexistent Note]]" == b for b in bodies)
    assert any("Some freeform reminder without a bullet" == b for b in bodies)


def test_m4_reports_dangling_wikilink(vault):
    report = migrate.run(vault, apply=True, now=NOW)
    assert any("Nonexistent Note" in msg for _, _, msg in report.unresolved)


# --------------------------------------------------------------------------
# M5 — Projects/ classification
# --------------------------------------------------------------------------


def test_m5_without_decisions_creates_nothing_and_reports_proposals(vault):
    report = migrate.run(vault, apply=True, now=NOW)
    assert not (vault / "Projects/Applications/Applications.md").exists()
    assert not (vault / "Projects/Karriereplanung/Karriereplanung.md").exists()
    unresolved_paths = {path for _, path, _ in report.unresolved}
    assert "Projects/Applications" in unresolved_paths
    assert "Projects/Karriereplanung" in unresolved_paths
    assert "Projects/Misc" in unresolved_paths
    # existing, already-migrated project note is left completely alone
    assert read(vault, "Projects/Applications/DAAD/DAAD.md") == (FIXTURES / "vault/Projects/Applications/DAAD/DAAD.md").read_text()


def test_m5_with_decisions_creates_area_and_project_notes(vault):
    shutil.copy(FIXTURES / "projects.decisions.yaml", vault / "projects.decisions.yaml")
    report = migrate.run(vault, apply=True, now=NOW)

    area_fm, _ = note(vault, "Projects/Applications/Applications.md")
    assert area_fm.get_scalar("kind") == "area"

    proj_fm, proj_body = note(vault, "Projects/Karriereplanung/Karriereplanung.md")
    assert proj_fm.get_scalar("kind") == "project"
    assert proj_fm.get_scalar("status") == "active"
    for heading in ("# Outcome", "# Why?", "# Steps", "# Log"):
        assert heading in proj_body

    # DAAD already had its own note -> not recreated, area recursion just skips it
    assert read(vault, "Projects/Applications/DAAD/DAAD.md") == (FIXTURES / "vault/Projects/Applications/DAAD/DAAD.md").read_text()

    # Misc has no decision -> still unresolved
    assert any(path == "Projects/Misc" for _, path, _ in report.unresolved)
    assert not (vault / "Projects/Misc/Misc.md").exists()


def test_m5_is_idempotent_once_decided(vault):
    shutil.copy(FIXTURES / "projects.decisions.yaml", vault / "projects.decisions.yaml")
    migrate.run(vault, apply=True, now=NOW)
    before = read(vault, "Projects/Karriereplanung/Karriereplanung.md")
    report2 = migrate.run(vault, apply=True, now=NOW)
    after = read(vault, "Projects/Karriereplanung/Karriereplanung.md")
    assert before == after
    assert report2.counts.get("M5", 0) == 0


# --------------------------------------------------------------------------
# M6 — empty-body actions -> Inbox
# --------------------------------------------------------------------------


def test_m6_moves_empty_body_action_to_inbox(vault):
    migrate.run(vault, apply=True, now=NOW)
    assert not (vault / "Actions/Empty task.md").exists()
    files = list((vault / "Inbox").glob("*.md"))
    bodies = [read_note(f.read_text(encoding="utf-8"))[1].strip() for f in files]
    assert "Empty task" in bodies


# --------------------------------------------------------------------------
# Config, routines, scaffold folders
# --------------------------------------------------------------------------


def test_config_created_with_defaults(vault):
    migrate.run(vault, apply=True, now=NOW)
    fm, _ = note(vault, "GTD/Config.md")
    assert fm.get_list("contexts") == ["mac", "phone", "home", "campus", "errands", "calls", "reading", "deep-work"]
    assert fm.get_list("onTheGoContexts") == ["phone", "errands", "calls", "reading"]
    assert fm.get_scalar("nextCap") == "15"


def test_routines_created_from_template(vault):
    migrate.run(vault, apply=True, now=NOW)
    morning_fm, morning_body = note(vault, "GTD/Routines/Morning.md")
    assert morning_fm.get_scalar("time") == "07:00"
    assert "Wake up, no snooze" in morning_body
    assert "Drink water" in morning_body
    assert "Tidy desk" not in morning_body

    bedtime_fm, bedtime_body = note(vault, "GTD/Routines/Bedtime.md")
    assert bedtime_fm.get_scalar("time") == "22:00"
    assert "Tidy desk" in bedtime_body
    assert "Wake up" not in bedtime_body


def test_routines_report_missing_template(vault):
    shutil.rmtree(vault / "Actions_legacy" / "zz_templates")
    report = migrate.run(vault, apply=True, now=NOW)
    assert not (vault / "GTD/Routines/Morning.md").exists()
    assert any("Dayplan_template.md" in msg for _, _, msg in report.unresolved)


def test_scaffold_folders_created(vault):
    migrate.run(vault, apply=True, now=NOW)
    for rel in ("Archive", "Knowledge", "Inbox", "GTD/Reviews", "GTD/RoutineLog", "GTD/Trash"):
        assert (vault / rel).is_dir()


# --------------------------------------------------------------------------
# Backup
# --------------------------------------------------------------------------


def test_apply_creates_a_full_backup_before_mutating(vault):
    original_call_dentist_legacy = read(vault, "Actions_legacy/01_Next_Actions/Call dentist.md")
    original_inbox = read(vault, "Inbox.md")

    migrate.run(vault, apply=True, now=NOW)

    backups = list(vault.parent.glob("GTD-migration-backup-*"))
    assert len(backups) == 1
    backup = backups[0]
    assert (backup / "Actions_legacy/01_Next_Actions/Call dentist.md").read_text() == original_call_dentist_legacy
    assert (backup / "Inbox.md").read_text() == original_inbox
    # the duplicate was in fact removed from the live vault, and Inbox.md moved away
    assert not (vault / "Actions_legacy/01_Next_Actions/Call dentist.md").exists()
    assert not (vault / "Inbox.md").exists()


def test_apply_refuses_and_makes_no_changes_if_backup_fails(vault, monkeypatch):
    before = snapshot(vault)

    def boom(*args, **kwargs):
        raise OSError("disk full (simulated)")

    monkeypatch.setattr(migrate.shutil, "copytree", boom)

    with pytest.raises(OSError):
        migrate.run(vault, apply=True, now=NOW)

    after = snapshot(vault)
    assert before == after  # no partial mutation
    assert not list(vault.parent.glob("GTD-migration-backup-*"))
    assert not list(vault.parent.glob(".GTD-migration-backup-*.tmp"))


# --------------------------------------------------------------------------
# Idempotency (end to end)
# --------------------------------------------------------------------------


def test_full_migration_is_idempotent(vault):
    shutil.copy(FIXTURES / "projects.decisions.yaml", vault / "projects.decisions.yaml")
    # remove the one file that always needs a genuine manual decision, so this test
    # can assert a truly quiet second run (see test_m3_non_duplicate_is_reported... for that path)
    (vault / "Actions_legacy" / "01_Next_Actions" / "Unique legacy task.md").unlink()

    first = migrate.run(vault, apply=True, now=NOW)
    assert first.changed_count > 0

    before = snapshot(vault)
    second = migrate.run(vault, apply=True, now=NOW.replace(hour=13))
    after = snapshot(vault)

    assert second.changed_count == 0
    # "Mystery task.md" (unknown context) and "Projects/Misc" (no decision on file) always need
    # a human decision and are reported every run; that's not a file change, so it doesn't
    # affect idempotency.
    assert {(rule, path) for rule, path, _ in second.unresolved} == {
        ("M1", "Actions/Mystery task.md"),
        ("M5", "Projects/Misc"),
    }
    # every vault file (including projects.decisions.yaml) is unchanged by the second run
    assert before == after


# --------------------------------------------------------------------------
# CLI smoke test
# --------------------------------------------------------------------------


def test_cli_dry_run_end_to_end(vault):
    result = subprocess.run(
        [sys.executable, str(Path(__file__).resolve().parent.parent / "migrate.py"), "--vault", str(vault)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert "DRY RUN" in result.stdout
    assert (vault / "migration-report.md").is_file()
    # dry run via the CLI must not have touched anything else either
    assert (vault / "Inbox.md").is_file()


def test_cli_requires_vault_argument():
    result = subprocess.run(
        [sys.executable, str(Path(__file__).resolve().parent.parent / "migrate.py")],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode != 0
