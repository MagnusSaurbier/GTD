"""A minimal, format-preserving editor for the YAML frontmatter used by this vault.

This is deliberately NOT a general YAML engine. It understands exactly the subset
the vault's notes use: top-level `key: value` scalars, flow lists (`key: [a, b]`),
and block lists (`key:` followed by indented `- item` lines). Anything else — a
comment, a blank line, a key we don't recognise, a multi-line/nested value — is
kept as an opaque line and copied through untouched.

Design goal: editing one key must never change the byte representation of any
other line. That is what "format-preserving" means here and it is the whole
reason this module exists instead of `yaml.dump()` (PyYAML reorders keys,
rewrites quoting/indentation and drops comments — unacceptable for editing a
person's real notes in place).

`read_note` / `write_note` handle the full note (frontmatter delimiters + body);
`Frontmatter` handles only the lines between the `---` delimiters.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Optional

KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):(.*)$")
LIST_ITEM_RE = re.compile(r"^(\s+)-\s?(.*)$")
NEEDS_QUOTE_RE = re.compile(r'[:#\[\]{}"\']')
RESERVED_WORDS = {"true", "false", "null", "~", "yes", "no"}


@dataclass
class Entry:
    """One frontmatter entry: either a recognised `key: ...` or a raw passthrough line."""

    kind: str  # "key" | "raw"
    key: Optional[str] = None
    value_kind: Optional[str] = None  # "scalar" | "empty" | "flow_list" | "block_list"
    lines: list[str] = field(default_factory=list)


class Frontmatter:
    def __init__(self, entries: list[Entry]):
        self.entries = entries

    @classmethod
    def parse(cls, fm_lines: list[str]) -> "Frontmatter":
        entries: list[Entry] = []
        i = 0
        n = len(fm_lines)
        while i < n:
            line = fm_lines[i]
            m = KEY_RE.match(line)
            if not m:
                entries.append(Entry(kind="raw", lines=[line]))
                i += 1
                continue
            key, rest = m.group(1), m.group(2).strip()
            if rest == "":
                j = i + 1
                items: list[str] = []
                while j < n and LIST_ITEM_RE.match(fm_lines[j]):
                    items.append(fm_lines[j])
                    j += 1
                if items:
                    entries.append(Entry(kind="key", key=key, value_kind="block_list", lines=[line, *items]))
                    i = j
                else:
                    entries.append(Entry(kind="key", key=key, value_kind="empty", lines=[line]))
                    i += 1
            else:
                value_kind = "flow_list" if rest.startswith("[") else "scalar"
                entries.append(Entry(kind="key", key=key, value_kind=value_kind, lines=[line]))
                i += 1
        return cls(entries)

    def render_lines(self) -> list[str]:
        out: list[str] = []
        for e in self.entries:
            out.extend(e.lines)
        return out

    def _find(self, key: str) -> Optional[Entry]:
        for e in self.entries:
            if e.kind == "key" and e.key == key:
                return e
        return None

    def has(self, key: str) -> bool:
        return self._find(key) is not None

    def get_scalar(self, key: str, default=None):
        e = self._find(key)
        if e is None or e.value_kind not in ("scalar", "empty"):
            return default
        if e.value_kind == "empty":
            return default
        m = KEY_RE.match(e.lines[0])
        return _unquote(m.group(2).strip())

    def get_list(self, key: str) -> list[str]:
        e = self._find(key)
        if e is None:
            return []
        if e.value_kind == "flow_list":
            m = KEY_RE.match(e.lines[0])
            raw = m.group(2).strip()
            inner = raw[1:-1] if raw.endswith("]") else raw[1:]
            if not inner.strip():
                return []
            return [_unquote(it.strip()) for it in inner.split(",") if it.strip()]
        if e.value_kind == "block_list":
            items = []
            for l in e.lines[1:]:
                lm = LIST_ITEM_RE.match(l)
                if lm:
                    items.append(_unquote(lm.group(2).strip()))
            return items
        return []

    def set_scalar(self, key: str, value) -> None:
        text = _format_scalar(value)
        newline = f"{key}: {text}" if text != "" else f"{key}:"
        e = self._find(key)
        if e is not None:
            e.value_kind = "scalar" if text != "" else "empty"
            e.lines = [newline]
        else:
            self.entries.append(
                Entry(kind="key", key=key, value_kind="scalar" if text != "" else "empty", lines=[newline])
            )

    def set_list(self, key: str, items: list[str], style: Optional[str] = None) -> None:
        e = self._find(key)
        if style is None:
            style = e.value_kind if (e and e.value_kind in ("flow_list", "block_list")) else "flow_list"
        if style == "block_list" and items:
            lines = [f"{key}:"] + [f"  - {_format_scalar(it, in_list=True)}" for it in items]
            value_kind = "block_list"
        else:
            lines = [f"{key}: [{', '.join(_format_scalar(it, in_list=True) for it in items)}]"]
            value_kind = "flow_list"
        if e is not None:
            e.value_kind = value_kind
            e.lines = lines
        else:
            self.entries.append(Entry(kind="key", key=key, value_kind=value_kind, lines=lines))

    def remove(self, key: str) -> bool:
        before = len(self.entries)
        self.entries = [e for e in self.entries if not (e.kind == "key" and e.key == key)]
        return len(self.entries) != before


def _unquote(s: str) -> str:
    if len(s) >= 2 and s[0] == s[-1] and s[0] in "\"'":
        inner = s[1:-1]
        if s[0] == '"':
            inner = inner.replace('\\"', '"').replace("\\\\", "\\")
        return inner
    return s


def _format_scalar(value, in_list: bool = False) -> str:
    if value is None:
        return '""' if in_list else ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    s = str(value)
    if s == "":
        return '""' if in_list else ""
    if NEEDS_QUOTE_RE.search(s) or s != s.strip() or s.lower() in RESERVED_WORDS:
        escaped = s.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    return s


def read_note(text: str) -> Optional[tuple[Frontmatter, str]]:
    """Split a full note's text into (Frontmatter, body). None if there is no frontmatter block."""
    parts = text.split("\n")
    if not parts or parts[0].strip() != "---":
        return None
    for j in range(1, len(parts)):
        if parts[j].strip() == "---":
            fm_lines = parts[1:j]
            body = "\n".join(parts[j + 1 :])
            return Frontmatter.parse(fm_lines), body
    return None


def write_note(fm: Frontmatter, body: str) -> str:
    lines = ["---", *fm.render_lines(), "---", *body.split("\n")]
    return "\n".join(lines)
