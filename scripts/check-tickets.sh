#!/usr/bin/env bash
# Enforces docs/TICKETS.md — the parts a script can see:
#
#   scripts/check-tickets.sh            gate mode: exits 1 on any problem (called by check.sh)
#   scripts/check-tickets.sh --status   board mode: prints the board and problems, always exits 0
#                                       (run at session start by .claude/settings.json)
#
# Checks:
#  1. docs/open_tickets/ and docs/in_progress/ hold only README.md and YYYY-MM-DD-<slug>.md files.
#  2. Every ticket carries the template's header fields and the Goal/State/Remaining/Handover/
#     Outcome headings, and its Status agrees with the folder it is in.
#  3. An in-progress ticket names a branch. On a branch other than main, exactly one
#     in-progress ticket names the current branch — no code without a ticket.
#  4. An in-progress ticket is not stale: no commit on its branch (since main) that touches code
#     is newer than the last commit that touched the ticket. Docs-only commits do not count.
#  5. An in-progress ticket that is already in main's tree (its branch was merged) must be moved
#     to docs/history/ (rule 4) — reported so that whoever sees it does the move.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

STATUS_MODE=0
[ "${1:-}" = "--status" ] && STATUS_MODE=1

problems=0
problem() { echo "  PROBLEM: $*"; problems=$((problems + 1)); }

field() { # field <file> <name>  → the value after **<name>:** up to the next ·
    sed -n "s/.*\*\*$2:\*\* *\([^·]*\).*/\1/p" "$1" | head -1 | sed 's/[[:space:]]*$//'
}

check_ticket_shape() { # <file> <expected status>
    local f="$1" expected="$2" name status
    name="$(basename "$f")"
    case "$name" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md) ;;
        *) problem "$f: ticket files are named YYYY-MM-DD-<slug>.md" ;;
    esac
    head -1 "$f" | grep -q '^# ' || problem "$f: first line must be the '# Title'"
    for key in Status Branch PR Opened "Last updated" Agent; do
        grep -q "\*\*$key:\*\*" "$f" || problem "$f: header is missing **$key:**"
    done
    for h in Goal State Remaining Handover Outcome; do
        grep -q "^## $h" "$f" || problem "$f: missing '## $h' section"
    done
    status="$(field "$f" Status)"
    case "$expected" in
        open)        [ "$status" = "open" ] || problem "$f: in open_tickets/ but Status is '$status'" ;;
        in-progress) [ "$status" = "in progress" ] || problem "$f: in in_progress/ but Status is '$status'" ;;
    esac
    field "$f" "Last updated" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' \
        || problem "$f: **Last updated:** must be a YYYY-MM-DD date"
}

for dir in docs/open_tickets docs/in_progress docs/history; do
    [ -d "$dir" ] || problem "$dir/ is missing"
done

echo "open tickets"
found=0
for f in docs/open_tickets/*.md; do
    [ -e "$f" ] || continue
    [ "$(basename "$f")" = "README.md" ] && continue
    found=1
    check_ticket_shape "$f" open
    echo "  $(basename "$f") — $(head -1 "$f" | sed 's/^# //')"
done
[ "$found" -eq 0 ] && echo "  (none)"

current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
in_git=1; git rev-parse --verify main >/dev/null 2>&1 || in_git=0

echo "in progress"
found=0
tickets_for_current=0
for f in docs/in_progress/*.md; do
    [ -e "$f" ] || continue
    [ "$(basename "$f")" = "README.md" ] && continue
    found=1
    check_ticket_shape "$f" in-progress
    branch="$(field "$f" Branch | tr -d '\`')"
    echo "  $(basename "$f") — $(head -1 "$f" | sed 's/^# //')"
    echo "      branch: ${branch:-—} · updated: $(field "$f" "Last updated") · pr: $(field "$f" PR)"
    if [ -z "$branch" ] || [ "$branch" = "—" ]; then
        problem "$f: in progress but **Branch:** is empty"
        continue
    fi
    [ "$branch" = "$current_branch" ] && tickets_for_current=$((tickets_for_current + 1))
    [ "$in_git" -eq 1 ] || continue
    # 5. merged already? The ticket only reaches main's tree through the branch's merge (rule 2
    #    commits the move on the branch), so "ticket on main + still in in_progress" = move it.
    if [ "$branch" != "main" ] && git cat-file -e "main:$f" 2>/dev/null; then
        problem "$f: its branch '$branch' is merged into main — git mv the ticket to docs/history/, fill in ## Outcome, commit on main with [skip ci]"
        continue
    fi
    if git rev-parse --verify --quiet "$branch" >/dev/null; then
        # 4. stale? last code commit on the branch vs last commit touching the ticket
        last_code="$(git log -1 --format=%ct "main..$branch" -- . ':(exclude)docs' ':(exclude)*.md' ':(exclude).claude' ':(exclude).github' 2>/dev/null || true)"
        last_ticket="$(git log -1 --format=%ct "$branch" -- "$f" 2>/dev/null || true)"
        if [ -n "$last_code" ] && [ -n "$last_ticket" ] && [ "$last_code" -gt "$last_ticket" ]; then
            problem "$f: stale — '$branch' has code commits newer than the ticket's last edit ($(git log -1 --format=%h "main..$branch" -- . ':(exclude)docs' ':(exclude)*.md' ':(exclude).claude' ':(exclude).github')). Update ## State / ## Remaining and commit."
        elif [ -n "$last_code" ] && [ -z "$last_ticket" ]; then
            problem "$f: the ticket is not committed on '$branch' yet"
        fi
    elif [ "$branch" != "$current_branch" ]; then
        echo "      (branch '$branch' not present in this checkout — fetch it or check the PR)"
    fi
done
[ "$found" -eq 0 ] && echo "  (none)"

# 3. code on a branch needs a ticket
if [ "$in_git" -eq 1 ] && [ "$current_branch" != "main" ] && [ "$current_branch" != "HEAD" ]; then
    has_code="$(git log -1 --format=%h "main..$current_branch" -- . ':(exclude)docs' ':(exclude)*.md' ':(exclude).claude' ':(exclude).github' 2>/dev/null || true)"
    if [ -n "$has_code" ] || [ "$STATUS_MODE" -eq 0 ]; then
        if [ "$tickets_for_current" -eq 0 ]; then
            problem "no in-progress ticket names the current branch '$current_branch' — create one in docs/open_tickets/, move it to docs/in_progress/ and set **Branch:** (docs/TICKETS.md rules 1–2)"
        elif [ "$tickets_for_current" -gt 1 ]; then
            problem "$tickets_for_current in-progress tickets name '$current_branch'; one ticket per branch"
        fi
    fi
fi

if [ "$problems" -gt 0 ]; then
    echo "check-tickets.sh: $problems problem(s) — see docs/TICKETS.md"
    [ "$STATUS_MODE" -eq 1 ] && exit 0
    exit 1
fi
echo "check-tickets.sh: ok"
