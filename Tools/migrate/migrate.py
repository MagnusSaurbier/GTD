#!/usr/bin/env python3
"""One-time migration of an existing Obsidian vault into the layout and schema
the GTD app expects (see docs/ARCHITECTURE.md §3 and docs/REQUIREMENTS.md §11
in the app repo).

Usage:
    python3 migrate.py --vault /path/to/vault              # dry run (default)
    python3 migrate.py --vault /path/to/vault --apply       # perform it

See README.md in this directory for the full review flow. In short:

    1. dry run -> read migration-report.md
    2. resolve every "needs a decision" item; for Projects/ classification,
       create/edit <vault>/projects.decisions.yaml (see README) and re-run the dry run
    3. --apply

This script never deletes anything. `--apply` first makes a full timestamped
backup of every folder it touches, next to the vault, and refuses to make any
change if that backup fails. Running it again after `--apply` is safe: it
reports zero changes once everything is resolved (idempotent).

The agent that wrote this script must never point it at a real vault; it is
exercised only against the synthetic fixtures in tests/.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

from frontmatter import Frontmatter, read_note, write_note

# --------------------------------------------------------------------------
# Rule tables (REQUIREMENTS §11, M1-M6)
# --------------------------------------------------------------------------

CONTEXT_MAP = {
    "@Mac": "mac",
    "Phone": "phone",
    "Home": "home",
    "tum-stammgelände": "campus",
    "conversations": "calls",
}
KNOWN_CONTEXTS = {"mac", "phone", "home", "campus", "errands", "calls", "deep-work"}
READLIST_CONTEXT = "readlist"  # legacy word; never in KNOWN_CONTEXTS — routed to Lists/Read/ instead (A4, M1)
READLIST_TARGET_DIR = "Lists/Read"
REMOVE_KEYS = ("priority", "type", "tags", "Ressources")
BOILERPLATE_MARKERS = {"", "...", "tbd", "todo", "n/a", "-"}
CLEAN_ACTION_BODY = "# Why?\n\n# What?\n"
PROJECT_BODY = "# Outcome\n\n# Why?\n\n# Steps\n\n# Log\n"
AFFECTED_FOR_BACKUP = ["Actions", "Actions_legacy", "Projects", "Inbox.md"]
EMPTY_FOLDERS = ["Archive", "Knowledge", "Inbox", "GTD/Reviews", "GTD/RoutineLog", "GTD/Trash", "GTD/Routines"]
DEFAULT_CONFIG_FM = [
    "contexts: [mac, phone, home, campus, errands, calls, deep-work]",
    "onTheGoContexts: [phone, errands, calls]",
    "nextCap: 15",
]
ROUTINE_SPECS = {
    "Morning": ("07:00", ("morning",)),
    "Bedtime": ("22:00", ("bedtime", "evening")),
}


@dataclass(frozen=True)
class Op:
    """A single planned filesystem change. Never executed during a dry run."""

    kind: str  # "write" | "delete" | "mkdir"
    path: str  # vault-relative, "/"-separated
    content: Optional[str] = None


class Report:
    def __init__(self) -> None:
        self.changes: list[tuple[str, str, str]] = []
        self.unresolved: list[tuple[str, str, str]] = []
        self.counts: dict[str, int] = {}
        self.unresolved_counts: dict[str, int] = {}

    def add_change(self, rule: str, path: str, message: str) -> None:
        self.changes.append((rule, path, message))
        self.counts[rule] = self.counts.get(rule, 0) + 1

    def add_unresolved(self, rule: str, path: str, message: str) -> None:
        self.unresolved.append((rule, path, message))
        self.unresolved_counts[rule] = self.unresolved_counts.get(rule, 0) + 1

    @property
    def changed_count(self) -> int:
        return len(self.changes)

    def render(self, applied: bool, now: datetime) -> str:
        lines: list[str] = ["# GTD vault migration report", ""]
        mode = "APPLIED" if applied else "DRY RUN — nothing was written except this report"
        lines += [f"Mode: {mode}", f"Generated: {now.isoformat()}", "", "## Counts", ""]
        all_rules = sorted(set(self.counts) | set(self.unresolved_counts))
        if all_rules:
            for rule in all_rules:
                lines.append(
                    f"- {rule}: {self.counts.get(rule, 0)} changed, "
                    f"{self.unresolved_counts.get(rule, 0)} needs a decision"
                )
        else:
            lines.append("_nothing to do_")
        lines += ["", "## Changes" + ("" if applied else " (planned)"), ""]
        if self.changes:
            for rule, path, msg in self.changes:
                lines.append(f"- [{rule}] `{path}` — {msg}")
        else:
            lines.append("_none_")
        lines += ["", "## Needs a decision", ""]
        if self.unresolved:
            for rule, path, msg in self.unresolved:
                lines.append(f"- [{rule}] `{path}` — {msg}")
        else:
            lines.append("_none_")
        lines.append("")
        return "\n".join(lines)


class InboxNamer:
    """Hands out strictly increasing timestamps, 1s apart, for synthesised inbox files."""

    def __init__(self, base: datetime):
        self._t = base

    def next(self) -> datetime:
        t = self._t
        self._t = self._t + timedelta(seconds=1)
        return t


# --------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------


def relpath(vault: Path, path: Path) -> str:
    return str(path.relative_to(vault)).replace(os.sep, "/")


def get_section(body: str, heading: str) -> str:
    target = heading.strip().lower()
    out: list[str] = []
    in_section = False
    for line in body.split("\n"):
        stripped = line.strip()
        if re.match(r"^#{1,6}\s+", stripped):
            in_section = re.sub(r"^#{1,6}\s+", "", stripped).strip().lower() == target
            continue
        if in_section:
            out.append(line)
    return "\n".join(out).strip()


def is_boilerplate_body(body: str) -> bool:
    why = get_section(body, "Why?").strip().lower()
    what = get_section(body, "What?").strip().lower()
    return why in BOILERPLATE_MARKERS and what in BOILERPLATE_MARKERS


def normalize_title(filename: str) -> str:
    return re.sub(r"\s+", " ", Path(filename).stem).strip().lower()


def normalize_body_for_compare(body: str) -> str:
    return re.sub(r"\s+", " ", body).strip().lower()


def wikilink_target_exists(vault: Path, target: str) -> bool:
    norm = target.split("|")[0].split("#")[0].strip().lower()
    return any(p.stem.lower() == norm for p in vault.rglob("*.md"))


def split_headings(text: str) -> list[tuple[str, list[str]]]:
    heading_re = re.compile(r"^#{1,6}\s+(.*)$")
    sections: list[tuple[str, list[str]]] = []
    heading: Optional[str] = None
    body_lines: list[str] = []
    for line in text.split("\n"):
        m = heading_re.match(line)
        if m:
            if heading is not None:
                sections.append((heading, body_lines))
            heading = m.group(1).strip()
            body_lines = []
        elif heading is not None:
            body_lines.append(line)
    if heading is not None:
        sections.append((heading, body_lines))
    return sections


def render_checkbox_lines(lines: list[str]) -> str:
    while lines and lines[0].strip() == "":
        lines = lines[1:]
    while lines and lines[-1].strip() == "":
        lines = lines[:-1]
    return "\n".join(lines) + ("\n" if lines else "")


def load_decisions(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    try:
        import yaml  # optional; only ever used for this script-owned control file

        data = yaml.safe_load(text) or {}
        return {str(k).strip(): str(v).strip() for k, v in data.items()}
    except Exception:
        result: dict[str, str] = {}
        for line in text.split("\n"):
            line = line.split("#", 1)[0].strip()
            if not line or ":" not in line:
                continue
            k, v = line.split(":", 1)
            result[k.strip().strip("\"'")] = v.strip().strip("\"'")
        return result


# --------------------------------------------------------------------------
# M1: normalize Actions/ frontmatter (shared with the M2 import path)
# --------------------------------------------------------------------------


def normalize_contexts(fm: Frontmatter, report: Report, relp: str, rule: str) -> bool:
    contexts = fm.get_list("contexts")
    if not contexts:
        return False
    new_contexts: list[str] = []
    time_estimate_from_ctx: Optional[int] = None
    for c in contexts:
        if c == "live":
            continue
        if c == "10min":
            time_estimate_from_ctx = 10
            continue
        mapped = CONTEXT_MAP.get(c, c)
        if mapped not in KNOWN_CONTEXTS:
            report.add_unresolved(rule, relp, f"unknown context value {c!r} — left as-is, decide manually")
        new_contexts.append(mapped)
    new_contexts = list(dict.fromkeys(new_contexts))  # de-dup, keep order
    mutated = False
    if new_contexts != contexts:
        fm.set_list("contexts", new_contexts)
        mutated = True
    if time_estimate_from_ctx is not None and apply_time_estimate(fm, time_estimate_from_ctx):
        mutated = True
    return mutated


def apply_time_estimate(fm: Frontmatter, minutes: int) -> bool:
    if fm.get_scalar("timeEstimate") == str(minutes):
        return False
    fm.set_scalar("timeEstimate", minutes)
    return True


def normalize_time_estimate_zero(fm: Frontmatter) -> bool:
    current = fm.get_scalar("timeEstimate")
    if current is not None and str(current).strip() == "0":
        fm.remove("timeEstimate")
        return True
    return False


def strip_removable_keys(fm: Frontmatter) -> list[str]:
    removed = []
    for key in REMOVE_KEYS:
        if fm.has(key):
            fm.remove(key)
            removed.append(key)
    return removed


def strip_default_scheduled(fm: Frontmatter) -> bool:
    if not fm.has("scheduled"):
        return False
    val = fm.get_scalar("scheduled")
    if val in (None, "", "null", "~"):
        fm.remove("scheduled")
        return True
    return False


def normalize_todo_status(fm: Frontmatter) -> bool:
    # `someday` is the only fallback word the script ever writes (never `backlog`/`maybe`,
    # A3/R-1) — the real Next-vs-Someday call is still made in the first weekly review.
    if fm.get_scalar("status") == "to-do":
        fm.set_scalar("status", "someday")
        fm.set_scalar("reviewReason", "migrated from to-do — decide Next vs Someday")
        return True
    return False


def normalize_action_frontmatter(fm: Frontmatter, report: Report, relp: str, rule: str) -> tuple[bool, list[str]]:
    mutated = normalize_contexts(fm, report, relp, rule)
    mutated = normalize_time_estimate_zero(fm) or mutated
    removed = strip_removable_keys(fm)
    mutated = bool(removed) or mutated
    mutated = strip_default_scheduled(fm) or mutated
    return mutated, removed


LEGACY_IMPORT_SPECS = (
    # (subdir, status, reviewReason, needs waitingFor/followUpDate)
    ("Actions_legacy/03_Waiting", "waiting", "migrated from Actions_legacy/03_Waiting — fill in who/follow-up", True),
)
# Actions_legacy/04_Maybe is handled separately (see plan_maybe_captures): those 45 items are
# imported as plain inbox captures and run through the new inbox flow (REQUIREMENTS §11 M2),
# not as `status: maybe` actions — `maybe` is a legacy word this script never writes.


@dataclass
class ListItemDoc:
    """An Actions/ note being routed to a list folder (currently only `readlist` -> Lists/Read/)
    instead of staying an action: stripped to what a list item carries (L1 — optional `created`
    only), title = filename, body kept verbatim."""

    created: Optional[str]
    body: str
    target_relpath: str
    source_relpath: str


@dataclass
class ActionDoc:
    """One note that will end up in (or be routed out of) Actions/, fully normalized in memory.

    M1 (normalize existing notes) and M2 (import Actions_legacy/03_Waiting) and M6 (empty body ->
    inbox) all operate on the *same* in-memory pass so a note that only becomes empty after M2's
    boilerplate strip is routed straight to Inbox/ in this run, instead of round-tripping through
    Actions/ first — that would otherwise take two `--apply` runs to settle and break idempotency.
    04_Maybe no longer goes through this pass at all (see `plan_maybe_captures`): it becomes a
    plain inbox capture, not an action.
    """

    fm: Frontmatter
    body: str
    target_relpath: str  # where it lives in Actions/ if it is kept there
    source: str  # "existing" | "imported"
    source_relpath: str  # the file to remove if this doc is emptied or (for imports) always
    original_text: Optional[str] = None  # "existing" only: to detect a real no-op
    removed_keys: list[str] = None  # type: ignore[assignment]
    import_status: Optional[str] = None


def collect_action_documents(
    vault: Path, report: Report
) -> tuple[list[ActionDoc], list[ListItemDoc]]:
    docs: list[ActionDoc] = []
    list_docs: list[ListItemDoc] = []
    seen_targets: set[str] = set()

    actions_dir = vault / "Actions"
    if actions_dir.is_dir():
        for path in sorted(actions_dir.glob("*.md")):
            relp = relpath(vault, path)
            original_text = path.read_text(encoding="utf-8")
            parsed = read_note(original_text)
            if parsed is None:
                report.add_unresolved("M1", relp, "no frontmatter found — skipped")
                continue
            fm, body = parsed
            if READLIST_CONTEXT in fm.get_list("contexts"):
                list_docs.append(
                    ListItemDoc(
                        created=fm.get_scalar("created"),
                        body=body,
                        target_relpath=f"{READLIST_TARGET_DIR}/{path.name}",
                        source_relpath=relp,
                    )
                )
                continue
            _, removed = normalize_action_frontmatter(fm, report, relp, "M1")
            normalize_todo_status(fm)
            docs.append(
                ActionDoc(fm=fm, body=body, target_relpath=relp, source="existing", source_relpath=relp,
                           original_text=original_text, removed_keys=removed)
            )
            seen_targets.add(relp)

    for subdir, status, reason, needs_waiting in LEGACY_IMPORT_SPECS:
        src_dir = vault / subdir
        if not src_dir.is_dir():
            continue
        for path in sorted(src_dir.glob("*.md")):
            relp = relpath(vault, path)
            target_relpath = f"Actions/{path.name}"
            if target_relpath in seen_targets:
                report.add_unresolved("M2", relp, f"target {target_relpath} already exists — resolve manually")
                continue
            parsed = read_note(path.read_text(encoding="utf-8"))
            if parsed is None:
                report.add_unresolved("M2", relp, "no frontmatter — skipped, needs manual import")
                continue
            fm, body = parsed
            normalize_action_frontmatter(fm, report, relp, "M2")
            fm.set_scalar("status", status)
            fm.set_scalar("reviewReason", reason)
            if needs_waiting:
                if not fm.has("waitingFor"):
                    fm.set_scalar("waitingFor", None)
                if not fm.has("followUpDate"):
                    fm.set_scalar("followUpDate", None)
            if is_boilerplate_body(body):
                body = CLEAN_ACTION_BODY
            docs.append(
                ActionDoc(fm=fm, body=body, target_relpath=target_relpath, source="imported",
                           source_relpath=relp, import_status=status)
            )
            seen_targets.add(target_relpath)

    return docs, list_docs


def plan_list_items(report: Report, ops: list[Op], docs: list[ListItemDoc]) -> None:
    for doc in docs:
        fm_lines = [f"created: {doc.created}"] if doc.created is not None else []
        ops.append(Op("write", doc.target_relpath, write_note(Frontmatter.parse(fm_lines), doc.body)))
        ops.append(Op("delete", doc.source_relpath))
        report.add_change(
            "M1", doc.source_relpath, f"readlist context — moved to {doc.target_relpath} as a Read list item"
        )


def plan_maybe_captures(vault: Path, report: Report, ops: list[Op], namer: InboxNamer) -> None:
    """04_Maybe items become plain inbox captures (REQUIREMENTS §11 M2): the script no longer
    guesses `status: maybe` for them — each runs through the new inbox flow by hand instead."""
    src_dir = vault / "Actions_legacy" / "04_Maybe"
    if not src_dir.is_dir():
        return
    for path in sorted(src_dir.glob("*.md")):
        relp = relpath(vault, path)
        text = path.read_text(encoding="utf-8")
        parsed = read_note(text)
        title = path.stem
        body = parsed[1] if parsed is not None else text
        capture_body = f"{title}\n\n{body.strip()}\n" if body.strip() else f"{title}\n"
        dt = namer.next()
        target_rel = f"Inbox/{dt:%Y-%m-%d %H%M%S}.md"
        capture_fm = Frontmatter.parse([f"created: {dt.isoformat()}"])
        ops.append(Op("write", target_rel, write_note(capture_fm, capture_body)))
        ops.append(Op("delete", relp))
        report.add_change("M2", relp, f"04_Maybe item — imported to {target_rel} as an inbox capture")


def plan_actions(vault: Path, report: Report, ops: list[Op], docs: list[ActionDoc], namer: InboxNamer) -> None:
    for doc in docs:
        is_empty = get_section(doc.body, "Why?") == "" and get_section(doc.body, "What?") == ""
        if is_empty:
            title = Path(doc.target_relpath).stem
            dt = namer.next()
            target_rel = f"Inbox/{dt:%Y-%m-%d %H%M%S}.md"
            capture_fm = Frontmatter.parse([f"created: {dt.isoformat()}"])
            ops.append(Op("write", target_rel, write_note(capture_fm, title)))
            ops.append(Op("delete", doc.source_relpath))
            report.add_change("M6", doc.source_relpath, f"empty Why?/What? — moved to {target_rel} as a capture")
            continue

        new_text = write_note(doc.fm, doc.body)
        if doc.source == "existing":
            if new_text != doc.original_text:
                ops.append(Op("write", doc.target_relpath, new_text))
                extra = f" (removed {', '.join(doc.removed_keys)})" if doc.removed_keys else ""
                report.add_change("M1", doc.target_relpath, "normalized frontmatter" + extra)
        else:
            ops.append(Op("write", doc.target_relpath, new_text))
            ops.append(Op("delete", doc.source_relpath))
            report.add_change(
                "M2", doc.source_relpath, f"imported to {doc.target_relpath} (status: {doc.import_status})"
            )


# --------------------------------------------------------------------------
# M3: duplicates between Actions_legacy/01_Next_Actions and Actions/
# --------------------------------------------------------------------------


def plan_duplicates(vault: Path, report: Report, ops: list[Op]) -> None:
    legacy_dir = vault / "Actions_legacy" / "01_Next_Actions"
    if not legacy_dir.is_dir():
        return
    actions_dir = vault / "Actions"
    existing_titles: set[str] = set()
    existing_bodies: set[str] = set()
    if actions_dir.is_dir():
        for p in actions_dir.glob("*.md"):
            existing_titles.add(normalize_title(p.name))
            parsed = read_note(p.read_text(encoding="utf-8"))
            body = parsed[1] if parsed else p.read_text(encoding="utf-8")
            existing_bodies.add(normalize_body_for_compare(body))
    for path in sorted(legacy_dir.glob("*.md")):
        relp = relpath(vault, path)
        text = path.read_text(encoding="utf-8")
        parsed = read_note(text)
        body = parsed[1] if parsed else text
        is_dup = normalize_title(path.name) in existing_titles or normalize_body_for_compare(body) in existing_bodies
        if is_dup:
            ops.append(Op("delete", relp))
            report.add_change("M3", relp, "duplicate of an Actions/ note — removed (kept in backup)")
        else:
            report.add_unresolved("M3", relp, "no matching Actions/ note found — decide manually (keep, file, or discard)")


# --------------------------------------------------------------------------
# M4: Inbox.md -> Inbox/<file per line>.md
# --------------------------------------------------------------------------


def plan_inbox_split(vault: Path, report: Report, ops: list[Op], namer: InboxNamer) -> None:
    inbox_md = vault / "Inbox.md"
    if not inbox_md.is_file():
        return
    text = inbox_md.read_text(encoding="utf-8")
    any_line = False
    for raw in text.split("\n"):
        stripped = raw.strip()
        if stripped == "":
            continue
        any_line = True
        content_line = re.sub(r"^[-*]\s+", "", stripped)
        for m in re.finditer(r"\[\[([^\]|]+)(?:\|[^\]]+)?\]\]", content_line):
            target = m.group(1)
            if not wikilink_target_exists(vault, target):
                report.add_unresolved("M4", "Inbox.md", f"dangling link [[{target}]] in line: {content_line!r}")
        dt = namer.next()
        target_rel = f"Inbox/{dt:%Y-%m-%d %H%M%S}.md"
        fm = Frontmatter.parse([f"created: {dt.isoformat()}"])
        ops.append(Op("write", target_rel, write_note(fm, content_line)))
        report.add_change("M4", "Inbox.md", f"line -> {target_rel}")
    if any_line:
        ops.append(Op("delete", "Inbox.md"))


# --------------------------------------------------------------------------
# M5: classify Projects/ folders into areas vs projects
# --------------------------------------------------------------------------


def plan_projects(vault: Path, report: Report, ops: list[Op], decisions_path: Path) -> None:
    projects_dir = vault / "Projects"
    if not projects_dir.is_dir():
        return
    decisions = load_decisions(decisions_path) if decisions_path.is_file() else {}
    top = sorted((d for d in projects_dir.iterdir() if d.is_dir() and not d.name.startswith(".")))
    for folder in top:
        _plan_project_folder(vault, folder, decisions, report, ops)


def _plan_project_folder(vault: Path, folder: Path, decisions: dict[str, str], report: Report, ops: list[Op]) -> None:
    relp = relpath(vault, folder)
    note_path = folder / f"{folder.name}.md"
    subfolders = sorted(d for d in folder.iterdir() if d.is_dir() and not d.name.startswith("."))
    heuristic = "area" if subfolders else "project"

    if note_path.is_file():
        parsed = read_note(note_path.read_text(encoding="utf-8"))
        existing_kind = parsed[0].get_scalar("kind") if parsed else None
        if existing_kind:
            if existing_kind == "area":
                for sub in subfolders:
                    _plan_project_folder(vault, sub, decisions, report, ops)
            return

    decision = decisions.get(relp)
    if decision not in ("area", "project"):
        report.add_unresolved(
            "M5",
            relp,
            f"classify as area or project (heuristic: {heuristic}) — "
            f"add `{relp}: {heuristic}` to projects.decisions.yaml and re-run",
        )
        return

    target_rel = relpath(vault, note_path)
    if decision == "area":
        fm = Frontmatter.parse(["kind: area"])
        ops.append(Op("write", target_rel, write_note(fm, f"# {folder.name}\n")))
        report.add_change("M5", relp, "created area note")
        for sub in subfolders:
            _plan_project_folder(vault, sub, decisions, report, ops)
    else:
        fm = Frontmatter.parse(["kind: project", "status: active"])
        ops.append(Op("write", target_rel, write_note(fm, PROJECT_BODY)))
        report.add_change("M5", relp, "created project note")


# --------------------------------------------------------------------------
# Config, routines, scaffold folders
# --------------------------------------------------------------------------


def plan_config(vault: Path, report: Report, ops: list[Op]) -> None:
    config_path = vault / "GTD" / "Config.md"
    if config_path.is_file():
        return
    fm = Frontmatter.parse(list(DEFAULT_CONFIG_FM))
    ops.append(Op("write", "GTD/Config.md", write_note(fm, "# GTD Config\n")))
    report.add_change("Config", "GTD/Config.md", "created with default settings")


def plan_routines(vault: Path, report: Report, ops: list[Op]) -> None:
    template_path = vault / "Actions_legacy" / "zz_templates" / "Dayplan_template.md"
    targets = {name: (vault / "GTD" / "Routines" / f"{name}.md", *spec) for name, spec in ROUTINE_SPECS.items()}
    if not template_path.is_file():
        for name, (path, _, _) in targets.items():
            if not path.is_file():
                report.add_unresolved(
                    "Routines",
                    f"GTD/Routines/{name}.md",
                    "no Actions_legacy/zz_templates/Dayplan_template.md found — create this routine manually",
                )
        return
    sections = split_headings(template_path.read_text(encoding="utf-8"))
    for name, (path, time_default, match_words) in targets.items():
        if path.is_file():
            continue
        body_lines = None
        for heading, lines in sections:
            if any(w in heading.lower() for w in match_words):
                body_lines = lines
                break
        if body_lines is None:
            report.add_unresolved(
                "Routines",
                f"GTD/Routines/{name}.md",
                f"no matching '{name}' section found in Dayplan_template.md — create manually",
            )
            continue
        fm = Frontmatter.parse([f'time: "{time_default}"'])
        content = write_note(fm, render_checkbox_lines(body_lines))
        ops.append(Op("write", relpath(vault, path), content))
        report.add_change(
            "Routines", relpath(vault, path), f"created from Dayplan_template.md (default time {time_default} — review)"
        )


def plan_empty_folders(vault: Path, report: Report, ops: list[Op]) -> None:
    for rel in EMPTY_FOLDERS:
        if not (vault / rel).is_dir():
            ops.append(Op("mkdir", rel))
            report.add_change("Folders", rel, "created empty folder")


# --------------------------------------------------------------------------
# Orchestration
# --------------------------------------------------------------------------


def plan(vault: Path, now: datetime, decisions_path: Optional[Path] = None) -> tuple[Report, list[Op]]:
    report = Report()
    ops: list[Op] = []
    namer = InboxNamer(now)
    decisions_path = decisions_path or (vault / "projects.decisions.yaml")

    plan_inbox_split(vault, report, ops, namer)
    plan_maybe_captures(vault, report, ops, namer)

    action_docs, list_docs = collect_action_documents(vault, report)
    plan_actions(vault, report, ops, action_docs, namer)
    plan_list_items(report, ops, list_docs)

    plan_duplicates(vault, report, ops)

    plan_projects(vault, report, ops, decisions_path)
    plan_config(vault, report, ops)
    plan_routines(vault, report, ops)
    plan_empty_folders(vault, report, ops)

    return report, ops


def make_backup(vault: Path, now: datetime) -> Path:
    """Copy every folder `plan()` might touch to `<vault>/../GTD-migration-backup-<ts>/`.

    Builds the backup in a temp directory and renames it into place atomically so a
    failed backup never leaves a partial one behind; callers must not run any mutating
    op unless this returns successfully.
    """
    ts = now.strftime("%Y%m%d-%H%M%S")
    backup_dir = vault.parent / f"GTD-migration-backup-{ts}"
    suffix = 2
    while backup_dir.exists():  # e.g. a second run within the same second
        backup_dir = vault.parent / f"GTD-migration-backup-{ts}-{suffix}"
        suffix += 1
    tmp_dir = vault.parent / f".{backup_dir.name}.tmp"
    if tmp_dir.exists():
        shutil.rmtree(tmp_dir)
    tmp_dir.mkdir(parents=True)
    try:
        for rel in AFFECTED_FOR_BACKUP:
            src = vault / rel
            if not src.exists():
                continue
            dst = tmp_dir / rel
            if src.is_dir():
                shutil.copytree(src, dst)
            else:
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst)
    except Exception:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        raise
    tmp_dir.rename(backup_dir)
    return backup_dir


def execute_ops(vault: Path, ops: list[Op]) -> None:
    for op in ops:
        target = vault / op.path
        if op.kind == "mkdir":
            target.mkdir(parents=True, exist_ok=True)
        elif op.kind == "write":
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(op.content, encoding="utf-8")
        elif op.kind == "delete":
            if target.is_file():
                target.unlink()
        else:
            raise ValueError(f"unknown op kind: {op.kind}")


def write_report(vault: Path, report: Report, applied: bool, now: datetime) -> Path:
    report_path = vault / "migration-report.md"
    report_path.write_text(report.render(applied, now), encoding="utf-8")
    return report_path


def run(vault: Path, apply: bool, now: Optional[datetime] = None, decisions_path: Optional[Path] = None) -> Report:
    vault = Path(vault)
    now = now or datetime.now().astimezone()
    report, ops = plan(vault, now, decisions_path)
    if apply:
        make_backup(vault, now)  # raises, and nothing below runs, if this fails
        execute_ops(vault, ops)
    write_report(vault, report, applied=apply, now=now)
    return report


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(prog="migrate.py", description="One-time GTD vault migration (dry run by default).")
    parser.add_argument("--vault", required=True, help="path to the vault root (the folder containing Actions/)")
    parser.add_argument("--apply", action="store_true", help="perform the migration (default: dry run only)")
    parser.add_argument(
        "--decisions", default=None, help="path to projects.decisions.yaml (default: <vault>/projects.decisions.yaml)"
    )
    args = parser.parse_args(argv)

    vault = Path(args.vault).expanduser().resolve()
    if not vault.is_dir():
        print(f"error: --vault {vault} is not a directory", file=sys.stderr)
        return 2

    decisions_path = Path(args.decisions).expanduser().resolve() if args.decisions else None
    now = datetime.now().astimezone()

    try:
        report = run(vault, apply=args.apply, now=now, decisions_path=decisions_path)
    except Exception as exc:  # noqa: BLE001 - top-level CLI guard
        print(f"error: {exc}", file=sys.stderr)
        if args.apply:
            print("refusing to continue — the backup did not complete, so nothing in the vault was changed.", file=sys.stderr)
        return 1

    mode = "APPLIED" if args.apply else "DRY RUN"
    print(f"{mode}: {report.changed_count} change(s), {len(report.unresolved)} item(s) need a decision.")
    print(f"See {vault / 'migration-report.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
