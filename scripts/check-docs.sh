#!/usr/bin/env bash
# Keeps the docs honest (CLAUDE.md "Keeping this file current"):
#
#  1. Every backticked repo path in the instruction docs — CLAUDE.md, README.md,
#     docs/ARCHITECTURE.md, the guides agents are sent to, App/README.md and every module
#     README — must exist. A path may be written relative to the repo root, to the file that
#     mentions it, to Packages/GTDKit, to Sources/ or Tests/, or to a module folder (a module
#     README says `Resources/…` and means its own). A bare file name must exist somewhere.
#  2. Every `scripts/*.sh` a doc names must exist and be executable.
#  3. No live document points into the archived task board (`agent_task/` is gone; its files
#     are `docs/history/build-out/` and the unstarted briefs are `docs/follow-ups/`).
#  4. The `<!-- PHASE: build-out -->` marker and the `agent_task/` folder must agree: either both
#     are present (build-out) or neither is (maintenance). The archive must still be there.
#
# Not path-checked: docs/REQUIREMENTS.md and docs/STYLEGUIDE.md (snapshots of the user's vault
# notes), docs/history/ (frozen), and the three prose test scripts — TEST-INSTRUCTIONS.md,
# docs/MANUAL_TEST.md, docs/TRACEABILITY.md — whose backticks mostly hold test-suite and type
# names rather than paths. Rule 3 covers all of them.
#
# Called by scripts/check.sh. Exits non-zero with a list of problems.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

FILES=(
    "CLAUDE.md"
    "README.md"
    "App/README.md"
    "docs/ARCHITECTURE.md"
    "docs/CONTRIBUTING-AGENTS.md"
    "docs/KNOWN_ISSUES.md"
    "docs/follow-ups/README.md"
    "docs/TICKETS.md"
    "docs/open_tickets/README.md"
    "docs/in_progress/README.md"
    "docs/history/README.md"
    ".github/workflows/README.md"
)
while IFS= read -r module_readme; do
    FILES+=("$module_readme")
done < <(ls Packages/GTDKit/Sources/*/README.md 2>/dev/null)

# Where a backticked path may be rooted, besides the repo root and the mentioning file's folder.
BASES=("Packages/GTDKit" "Packages/GTDKit/Sources" "Packages/GTDKit/Tests")
for module in Packages/GTDKit/Sources/*/; do BASES+=("${module%/}"); done

# Paths that do not exist in a clean checkout on purpose, plus the folders of the user's Obsidian
# vault — those are paths in the vault, not in this repo.
ALLOWED_MISSING=(
    "*.xcodeproj" "GTD.xcodeproj" "App/Info.plist" "App/GTD.entitlements" ".build/" "DerivedData/"
    "Actions" "Actions/*" "Actions_legacy/*" "Archive/*" "Inbox" "Inbox/*" "Inbox.md"
    "Knowledge/*" "Projects/*" "GTD/*" "Lists" "Lists/*" "Done" "Done/"
    "migration-report.md" "projects.decisions.yaml"
)

problems=0

is_allowed() {
    local candidate="$1"
    for allowed in "${ALLOWED_MISSING[@]}"; do
        # shellcheck disable=SC2053
        [[ "$candidate" == $allowed ]] && return 0
    done
    return 1
}

# Every file name in the repo, so a doc may name a file without spelling out its folder.
# (`-print` + sed rather than GNU find's `-printf '%f\n'`, which BSD find on macOS does not have.)
BASENAMES="$(find . -path ./.git -prune -o -path ./.build -prune -o -type f -print 2>/dev/null | sed 's|.*/||' | sort -u)"

resolves() {
    local candidate="$1" dir="$2" base prefix
    for base in "" "$dir" "${BASES[@]}"; do
        prefix="${base:+$base/}"
        [ -e "$prefix$candidate" ] && return 0
        # A test suite is written `GTDModelTests/RulesTests`; the file carries the extension.
        [ -e "$prefix$candidate.swift" ] && return 0
    done
    case "$candidate" in
        */*) return 1 ;;
        *) grep -qxF "$candidate" <<<"$BASENAMES" && return 0 ;;
    esac
    return 1
}

echo "checking backticked paths in ${#FILES[@]} files"
for file in "${FILES[@]}"; do
    [ -f "$file" ] || { echo "  MISSING FILE: $file"; problems=$((problems + 1)); continue; }
    dir="$(dirname "$file")"
    # Backticked tokens that look like repo paths: plain ASCII, at least one letter, no spaces,
    # no shell metacharacters, no URL scheme, and either a "/" or a known file extension.
    while IFS= read -r token; do
        case "$token" in
            *://*|http*|/*|\~*) continue ;;
            *[!A-Za-z0-9._/+-]*) continue ;;
            *[A-Za-z]*) ;;
            *) continue ;;
        esac
        case "$token" in
            */*|*.md|*.sh|*.swift|*.yml|*.plist|*.py|*.xcassets|*.xcstrings) ;;
            *) continue ;;
        esac
        # `Symbols.moveUp/moveDown` is a member expression, not a path: no folder here has a dot.
        case "$token" in *.*/*) continue ;; esac
        case "$token" in
            scripts/*.sh)
                if [ ! -e "$token" ]; then
                    echo "  MISSING: $token   (referenced in $file)"
                    problems=$((problems + 1))
                elif [ ! -x "$token" ]; then
                    echo "  NOT EXECUTABLE: $token   (referenced in $file)"
                    problems=$((problems + 1))
                fi
                continue ;;
        esac
        candidate="${token%/}"
        resolves "$candidate" "$dir" && continue
        if is_allowed "$token" || is_allowed "$candidate"; then
            echo "  ok (allow-listed, not a file in this repo): $token"
            continue
        fi
        echo "  MISSING: $token   (referenced in $file)"
        problems=$((problems + 1))
    done < <(grep -o '`[^`]\+`' "$file" | tr -d '`' | sort -u)
done

echo "checking that no live document points at the archived task board"
while IFS= read -r hit; do
    echo "  STALE LINK: $hit"
    problems=$((problems + 1))
# `.claude/` holds agent scaffolding, including the git worktrees parallel subtasks run in —
# a second checkout of this repo, whose copy of this script would otherwise report itself.
done < <(grep -rIln 'agent_task/' \
    --exclude-dir=.git --exclude-dir=.build --exclude-dir=history --exclude-dir=.claude \
    . 2>/dev/null | sed 's|^\./||' | grep -v '^scripts/check-docs.sh$')

echo "checking the build-out phase marker"
marker_present=0
grep -q '<!-- PHASE: build-out -->' CLAUDE.md 2>/dev/null && marker_present=1
tasks_present=0
[ -d "agent_task" ] && tasks_present=1

if [ "$marker_present" -ne "$tasks_present" ]; then
    if [ "$marker_present" -eq 1 ]; then
        echo "  PROBLEM: CLAUDE.md still carries <!-- PHASE: build-out --> but agent_task/ is gone."
    else
        echo "  PROBLEM: agent_task/ exists but CLAUDE.md has no <!-- PHASE: build-out --> marker."
    fi
    problems=$((problems + 1))
elif [ "$marker_present" -eq 0 ] && [ ! -f "docs/history/build-out/README.md" ]; then
    echo "  PROBLEM: the build-out is over but its archive (docs/history/build-out/) is gone."
    problems=$((problems + 1))
else
    echo "  ok (marker and agent_task/ agree)"
fi

if [ "$problems" -gt 0 ]; then
    echo "check-docs.sh: $problems problem(s)"
    exit 1
fi
echo "check-docs.sh: ok"
