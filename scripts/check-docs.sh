#!/usr/bin/env bash
# Keeps the docs honest (CLAUDE.md "Keeping this file current"):
#
#  1. Every backticked repo-relative path in CLAUDE.md and README.md must exist.
#     Paths that are intentionally generated or git-ignored are allow-listed below.
#  2. The `<!-- PHASE: build-out -->` marker and the `agent_task/` folder must agree:
#     either both are present (build-out) or neither is (maintenance, after T42).
#
# Called by scripts/check.sh. Exits non-zero with a list of problems.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

FILES=("CLAUDE.md" "README.md")

# Paths that do not exist in a clean checkout on purpose.
ALLOWED_MISSING=(
    "*.xcodeproj"
    "GTD.xcodeproj"
    "App/Info.plist"
    "App/GTD.entitlements"
    ".build/"
    "DerivedData/"
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

echo "checking backticked paths in ${FILES[*]}"
for file in "${FILES[@]}"; do
    [ -f "$file" ] || continue
    # Backticked tokens that look like repo paths: they contain a "/" or end in a known
    # file extension, and carry no spaces, shell metacharacters or URL scheme.
    while IFS= read -r token; do
        case "$token" in
            *" "*|*'$'*|*'|'*|*'*'*|*"'"*|http*|\~*|/*|*'<'*|*'>'*) continue ;;
        esac
        case "$token" in
            */*|*.md|*.sh|*.swift|*.yml|*.plist|*.xcassets|*.xcstrings) ;;
            *) continue ;;
        esac
        candidate="${token%/}"
        [ -e "$candidate" ] && continue
        if is_allowed "$token" || is_allowed "$candidate"; then
            echo "  ok (allow-listed, not in a clean checkout): $token"
            continue
        fi
        # A path with a <Placeholder> segment is a pattern, not a file.
        case "$token" in *"<"*) continue ;; esac
        echo "  MISSING: $token   (referenced in $file)"
        problems=$((problems + 1))
    done < <(grep -o '`[^`]\+`' "$file" | tr -d '`' | sort -u)
done

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
else
    echo "  ok (marker and agent_task/ agree)"
fi

if [ "$problems" -gt 0 ]; then
    echo "check-docs.sh: $problems problem(s)"
    exit 1
fi
echo "check-docs.sh: ok"
