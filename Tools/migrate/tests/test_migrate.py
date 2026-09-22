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
    for rule in ("M1", "M2", "M3", "M4", "M5", "M6", "M7"):
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
    assert fm.get_scalar("status") == "someday"
    assert fm.get_scalar("reviewReason") == "migrated from to-do — decide Next vs Someday"
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


def test_m1_readlist_context_moves_note_to_read_list(vault):
    report = migrate.run(vault, apply=True, now=NOW)
    assert not (vault / "Actions/Read some book.md").exists()
    fm, body = note(vault, "Lists/Read/Read some book.md")
    # stripped to what a list item carries: optional `created` only
    assert [e.key for e in fm.entries if e.kind == "key"] == ["created"]
    assert fm.get_scalar("created") == "2026-01-06T08:00:00+01:00"
    assert not fm.has("contexts")
    assert not fm.has("status")
    assert not fm.has("timeEstimate")
    assert "Recommended by a friend." in body  # body kept as-is
    assert "Finish chapter 3" in body
    assert any(
        rule == "M1" and path == "Actions/Read some book.md" for rule, path, _ in report.changes
    )


def test_m1_readlist_context_is_never_left_in_config_or_known_contexts(vault):
    migrate.run(vault, apply=True, now=NOW)
    fm, _ = note(vault, "GTD/Config.md")
    assert "reading" not in fm.get_list("contexts")
    assert "reading" not in fm.get_list("onTheGoContexts")


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
    fm, body = note(vault, "Inbox/Empty waiting.md")  # the filename is the title
    assert fm.get_scalar("created") is not None
    assert body.strip() == ""


def test_m2_maybe_items_become_inbox_captures_not_maybe_actions(vault):
    report = migrate.run(vault, apply=True, now=NOW)
    assert not (vault / "Actions_legacy/04_Maybe/Maybe someday.md").exists()
    assert not (vault / "Actions/Maybe someday.md").exists()  # never imported as an action
    fm, body = note(vault, "Inbox/Maybe someday.md")  # named after the old file
    assert [e.key for e in fm.entries if e.kind == "key"] == ["created"]
    assert not fm.has("status")  # never written by the script
    # body = the old body only; the title lives in the filename, not prepended to the body
    assert not body.strip().startswith("Maybe someday")
    assert body.strip().startswith("# Why?")
    assert "Might redo the garden someday." in body
    assert "Plan garden layout" in body
    assert any(rule == "M2" and "Maybe someday.md" in path for rule, path, _ in report.changes)


def test_m2_maybe_item_with_skeleton_body_gets_an_empty_body(vault):
    migrate.run(vault, apply=True, now=NOW)
    assert not (vault / "Actions_legacy/04_Maybe/Skeleton maybe.md").exists()
    fm, body = note(vault, "Inbox/Skeleton maybe.md")
    assert fm.get_scalar("created") is not None
    assert body == ""


def test_m2_maybe_captures_keep_creation_order(vault):
    migrate.run(vault, apply=True, now=NOW)
    a, _ = note(vault, "Inbox/Maybe someday.md")
    b, _ = note(vault, "Inbox/Skeleton maybe.md")
    assert a.get_scalar("created") < b.get_scalar("created")


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


def inbox_names(vault):
    return sorted(p.name for p in (vault / "Inbox").glob("*.md"))


def test_m4_splits_inbox_lines_into_title_named_files(vault):
    report = migrate.run(vault, apply=True, now=NOW)
    assert not (vault / "Inbox.md").exists()
    # plain line: the title carries it all -> empty body
    fm, body = note(vault, "Inbox/Some freeform reminder without a bullet.md")
    assert fm.get_scalar("created") is not None
    assert body == ""
    # sanitizing changed it -> the full line stays in the body
    _, body = note(vault, "Inbox/Call Nonexistent Note.md")
    assert body.strip() == "Call [[Nonexistent Note]]"
    _, body = note(vault, "Inbox/remote.md")
    assert body.strip() == "[[remote]]"
    _, body = note(vault, "Inbox/Connect Maximus.md")
    assert body.strip() == "[ ] Connect Maximus"
    # a line with no title ("- []") is skipped, and said so in the report
    assert any(rule == "M4" and "'[]'" in msg for rule, path, msg in report.changes)
    assert ".md" not in inbox_names(vault) and "Untitled.md" not in inbox_names(vault)
    # no timestamp-named files are created any more
    assert not any(migrate.TIMESTAMP_CAPTURE_RE.match(n) for n in inbox_names(vault) if n != "2026-09-21 090000.md")


def test_m4_collides_with_a_capture_renamed_by_m7_in_the_same_run(vault):
    # "Inbox/2026-09-20 080000.md" says "Buy milk" and so does a line of Inbox.md: the older,
    # already-existing capture keeps the plain name, the Inbox.md line gets " 2".
    migrate.run(vault, apply=True, now=NOW)
    old_fm, _ = note(vault, "Inbox/Buy milk.md")
    assert old_fm.get_scalar("created") == "2026-09-20T08:00:00+02:00"
    new_fm, body = note(vault, "Inbox/Buy milk 2.md")
    assert new_fm.get_scalar("created") == NOW.isoformat()
    assert body == ""


def test_m4_preserves_line_order_in_created(vault):
    migrate.run(vault, apply=True, now=NOW)
    order = ["Buy milk 2", "Call Nonexistent Note", "Some freeform reminder without a bullet", "remote", "Connect Maximus"]
    created = [note(vault, f"Inbox/{t}.md")[0].get_scalar("created") for t in order]
    assert created == sorted(created)
    assert len(set(created)) == len(created)


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


def test_m6_moves_empty_body_action_to_inbox_named_after_it_with_empty_body(vault):
    report = migrate.run(vault, apply=True, now=NOW)
    assert not (vault / "Actions/Empty task.md").exists()
    fm, body = note(vault, "Inbox/Empty task.md")
    assert [e.key for e in fm.entries if e.kind == "key"] == ["created"]
    assert body == ""  # the title is the filename, not repeated in the body
    # nothing disappears silently: the report names the frontmatter keys that were dropped
    msg = next(m for r, p, m in report.changes if r == "M6" and p == "Actions/Empty task.md")
    assert "dropped frontmatter: status, contexts" in msg


def test_m6_keeps_created(vault):
    migrate.run(vault, apply=True, now=NOW)
    fm, _ = note(vault, "Inbox/Empty task.md")
    assert fm.get_scalar("created") == "2026-01-13T08:00:00+01:00"
    fm, _ = note(vault, "Inbox/Empty waiting.md")  # imported by M2, then emptied
    assert fm.get_scalar("created") == "2026-01-08T09:00:00+01:00"


def test_m6_falls_back_to_date_created_then_to_the_run_time(vault):
    (vault / "Actions/Old style.md").write_text(
        "---\nstatus: next\ndateCreated: 2025-05-05T10:00:00+02:00\n---\n# Why?\n\n# What?\n", encoding="utf-8"
    )
    (vault / "Actions/No date.md").write_text("---\nstatus: next\n---\n# Why?\n\n# What?\n", encoding="utf-8")
    report = migrate.run(vault, apply=True, now=NOW)
    fm, _ = note(vault, "Inbox/Old style.md")
    assert [e.key for e in fm.entries if e.kind == "key"] == ["created"]
    assert fm.get_scalar("created") == "2025-05-05T10:00:00+02:00"
    msg = next(m for r, p, m in report.changes if p == "Actions/Old style.md")
    assert "dateCreated" in msg and "dropped frontmatter: status" in msg
    fm, _ = note(vault, "Inbox/No date.md")
    assert fm.get_scalar("created") is not None


def test_m6_placeholder_bullets_count_as_content_and_note_stays(vault):
    # regression: `- ` / `- [ ]` placeholders must NOT make an Actions/ note "empty"
    before = read(vault, "Actions/Placeholder task.md")
    body = read_note(before)[1]
    assert migrate.get_section(body, "Why?") == "-"
    report = migrate.run(vault, apply=True, now=NOW)
    assert read(vault, "Actions/Placeholder task.md") == before
    assert not (vault / "Inbox/Placeholder task.md").exists()
    assert not any(p == "Actions/Placeholder task.md" for r, p, _ in report.changes if r == "M6")


def test_m6_leaves_done_actions_alone(vault):
    # regression: an empty-bodied action the user already completed must not return to the inbox
    path = vault / "Actions/Finished empty.md"
    path.write_text("---\nstatus: done\ncreated: 2026-09-19T11:07:33+02:00\n---\n# Why?\n\n# What?\n", encoding="utf-8")
    before = read(vault, "Actions/Finished empty.md")
    report = migrate.run(vault, apply=True, now=NOW)
    assert read(vault, "Actions/Finished empty.md") == before
    assert not (vault / "Inbox/Finished empty.md").exists()
    assert not any(p == "Actions/Finished empty.md" for r, p, _ in report.changes if r == "M6")


def test_m6_leaves_note_with_content_outside_why_what(vault):
    # regression: empty Why?/What? but a `# When?` section with a URL -> must stay in Actions/,
    # an empty-body capture would have lost the URL
    before = read(vault, "Actions/Look through job board.md")
    migrate.run(vault, apply=True, now=NOW)
    assert read(vault, "Actions/Look through job board.md") == before
    assert not (vault / "Inbox/Look through job board.md").exists()


@pytest.mark.parametrize(
    "body, empty",
    [
        ("# Why?\n\n# What?\n", True),
        ("", True),
        ("# Why?\n- \n# What?\n", False),
        ("# Why?\n\n# What?\n- [ ]\n", False),
        ("# Why?\n\n# What?\n\n# When?\nhttps://x.y\n", False),
        ("Some text\n# Why?\n\n# What?\n", False),
        ("[[Link]]\n", False),
    ],
)
def test_is_empty_action_body(body, empty):
    assert migrate.is_empty_action_body(body) is empty


def test_m6_keeps_actions_with_real_content(vault):
    migrate.run(vault, apply=True, now=NOW)
    assert (vault / "Actions/Write report.md").exists()
    assert not (vault / "Inbox/Write report.md").exists()


# --------------------------------------------------------------------------
# M7 — timestamp-named captures already in Inbox/ -> Inbox/<title>.md
# --------------------------------------------------------------------------


def test_m7_wikilink_capture_keeps_full_text_in_body(vault):
    migrate.run(vault, apply=True, now=NOW)
    assert not (vault / "Inbox/2026-09-19 110721.md").exists()
    fm, body = note(vault, "Inbox/Wohnung streichen Leute fragen.md")
    assert fm.get_scalar("created") == "2026-09-19T11:07:21+02:00"
    assert body.strip() == "[[Wohnung streichen Leute fragen]]"


def test_m7_plain_capture_gets_empty_body(vault):
    migrate.run(vault, apply=True, now=NOW)
    assert not (vault / "Inbox/2026-09-22 012557.md").exists()
    assert read(vault, "Inbox/Notiz.md") == "---\ncreated: 2026-09-22T01:25:57+02:00\n---\n"


def test_m7_keeps_review_reason_and_unknown_keys_verbatim(vault):
    migrate.run(vault, apply=True, now=NOW)
    assert not (vault / "Inbox/2026-09-19 110749.md").exists()
    assert read(vault, "Inbox/Rucksack Fahrradtasche.md") == (
        "---\ncreated: 2026-09-19T11:07:49+02:00\nreviewReason:\nsource: watch\n---\n"
    )


def test_m7_long_multiline_capture_is_cut_at_a_word_and_keeps_full_text(vault):
    migrate.run(vault, apply=True, now=NOW)
    title = "Ask the landlord whether the balcony railing can be"
    _, body = note(vault, f"Inbox/{title}.md")
    assert body.strip() == (
        "Ask the landlord whether the balcony railing can be repainted before winter\nalso the mailbox key"
    )


def test_m7_collision_with_existing_file_is_case_insensitive_and_suffixed(vault):
    migrate.run(vault, apply=True, now=NOW)
    # body "Note" vs the hand-made "note.md" (same name on a case-insensitive file system)
    assert not (vault / "Inbox/2026-09-20 080001-2.md").exists()
    fm, body = note(vault, "Inbox/Note 2.md")
    assert fm.get_scalar("created") == "2026-09-20T08:00:01+02:00"
    assert body == ""


def test_m7_skeleton_only_capture_is_left_and_reported(vault):
    before = read(vault, "Inbox/2026-09-21 090000.md")
    report = migrate.run(vault, apply=True, now=NOW)
    assert read(vault, "Inbox/2026-09-21 090000.md") == before
    assert ("M7", "Inbox/2026-09-21 090000.md") in {(r, p) for r, p, _ in report.unresolved}


def test_m7_non_timestamp_files_are_untouched(vault):
    before = read(vault, "Inbox/note.md")  # hand-made, skeleton-only body: filename is its title
    report = migrate.run(vault, apply=True, now=NOW)
    assert read(vault, "Inbox/note.md") == before
    assert not any("note.md" in p for _, p, _ in report.changes + report.unresolved)


def test_m7_empty_capture_is_reported_not_renamed(vault):
    (vault / "Inbox/2026-09-23 100000.md").write_text("---\ncreated: 2026-09-23T10:00:00+02:00\n---\n\n", encoding="utf-8")
    report = migrate.run(vault, apply=True, now=NOW)
    assert (vault / "Inbox/2026-09-23 100000.md").exists()
    assert ("M7", "Inbox/2026-09-23 100000.md") in {(r, p) for r, p, _ in report.unresolved}


def test_m7_capture_without_frontmatter_is_renamed(vault):
    (vault / "Inbox/2026-09-23 100001.md").write_text("Fix bike light\n", encoding="utf-8")
    migrate.run(vault, apply=True, now=NOW)
    assert read(vault, "Inbox/Fix bike light.md") == ""


def test_m7_collisions_among_timestamp_captures_are_numbered_in_file_order(vault):
    for i, stem in enumerate(("2026-09-23 100000", "2026-09-23 100001", "2026-09-23 100002-2")):
        (vault / f"Inbox/{stem}.md").write_text(f"---\ncreated: {i}\n---\nDuplicate idea\n", encoding="utf-8")
    migrate.run(vault, apply=True, now=NOW)
    for i, name in enumerate(("Duplicate idea.md", "Duplicate idea 2.md", "Duplicate idea 3.md")):
        fm, body = note(vault, f"Inbox/{name}")
        assert fm.get_scalar("created") == str(i)
        assert body == ""


def test_m7_dry_run_touches_nothing(vault):
    before = snapshot(vault)
    report = migrate.run(vault, apply=False, now=NOW)
    assert snapshot(vault) == before
    assert report.counts.get("M7") == 6


def test_m7_is_idempotent(vault):
    migrate.run(vault, apply=True, now=NOW)
    names = inbox_names(vault)
    second = migrate.run(vault, apply=True, now=NOW.replace(hour=13))
    assert inbox_names(vault) == names
    assert second.counts.get("M7", 0) == 0
    assert {(r, p) for r, p, _ in second.unresolved if r == "M7"} == {("M7", "Inbox/2026-09-21 090000.md")}


# --------------------------------------------------------------------------
# Capture title rule (mirrors Swift CaptureText.title + VaultLayout.sanitize)
# --------------------------------------------------------------------------


@pytest.mark.parametrize(
    "text, title",
    [
        ("Buy milk", "Buy milk"),
        ("  \n\t  Hello   world  \nsecond line", "Hello world"),
        ("[[Wohnung streichen Leute fragen]]", "Wohnung streichen Leute fragen"),
        ("[ ] Connect Maximus", "Connect Maximus"),
        ('a/b\\c:d*e?f"g<h>i|j[k]l#m^n', "a b c d e f g h i j k l m n"),
        ("#tag", "tag"),
        ("Grüße an Jürgen", "Grüße an Jürgen"),
        ("line\r\nnext", "line"),  # CRLF: the \r is sanitized away
        ("", None),
        ("   \n \t \n", None),
        ("[[]]", None),
        ("# ^ |", None),
    ],
)
def test_capture_title(text, title):
    assert migrate.capture_title(text) == title


def test_capture_title_cuts_at_last_word_within_60_chars():
    text = "word " * 20  # 100 chars
    title = migrate.capture_title(text)
    assert title == ("word " * 12).strip()  # 59 chars; the 13th word would not fit
    assert len(title) <= 60


def test_capture_title_hard_cuts_a_single_long_word():
    assert migrate.capture_title("x" * 70) == "x" * 60


def test_capture_title_hard_cut_when_the_60th_char_is_a_space():
    # head ends in a space -> the partial word is empty -> hard cut (then trimmed)
    text = "a" * 59 + " " + "b" * 10
    assert migrate.capture_title(text) == "a" * 59


def test_capture_title_keeps_a_short_first_word_before_an_overlong_one():
    assert migrate.capture_title("a " + "b" * 70) == "a"


def test_capture_title_counts_characters_not_code_points():
    nfd_u = "u\u0308"  # "ü" decomposed, as macOS file names often are
    assert migrate.capture_title(nfd_u * 70) == nfd_u * 60
    assert migrate.capture_title("ü" * 70) == "ü" * 60


def test_capture_body_is_full_text_only_when_title_differs():
    assert migrate.capture_body("  Notiz \n", "Notiz") == ""
    assert migrate.capture_body("[[remote]]", "remote") == "[[remote]]"
    assert migrate.capture_body("\nA\nB\n", "A") == "A\nB"


def test_skeleton_body_detection():
    assert migrate.is_skeleton_body("")
    assert migrate.is_skeleton_body("# Why?\n- \n\n# What?\n- [ ]\n")
    assert not migrate.is_skeleton_body("# Why?\nBecause\n# What?\n")
    assert not migrate.is_skeleton_body("# Notes\n")
    assert not migrate.is_skeleton_body("Buy milk")


# --------------------------------------------------------------------------
# Config, routines, scaffold folders
# --------------------------------------------------------------------------


def test_config_created_with_defaults(vault):
    migrate.run(vault, apply=True, now=NOW)
    fm, _ = note(vault, "GTD/Config.md")
    assert fm.get_list("contexts") == ["mac", "phone", "home", "campus", "errands", "calls", "deep-work"]
    assert fm.get_list("onTheGoContexts") == ["phone", "errands", "calls"]
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
    original_capture = read(vault, "Inbox/2026-09-22 012557.md")

    migrate.run(vault, apply=True, now=NOW)

    backups = list(vault.parent.glob("GTD-migration-backup-*"))
    assert len(backups) == 1
    backup = backups[0]
    assert (backup / "Actions_legacy/01_Next_Actions/Call dentist.md").read_text() == original_call_dentist_legacy
    assert (backup / "Inbox.md").read_text() == original_inbox
    # Inbox/ is modified by M7 (renames), so it is backed up too
    assert (backup / "Inbox/2026-09-22 012557.md").read_text() == original_capture
    assert not (vault / "Inbox/2026-09-22 012557.md").exists()
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
    # "Mystery task.md" (unknown context), "Projects/Misc" (no decision on file) and the
    # untitleable timestamp capture always need
    # a human decision and are reported every run; that's not a file change, so it doesn't
    # affect idempotency.
    assert {(rule, path) for rule, path, _ in second.unresolved} == {
        ("M1", "Actions/Mystery task.md"),
        ("M5", "Projects/Misc"),
        ("M7", "Inbox/2026-09-21 090000.md"),  # skeleton-only capture: no text to name it by
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
