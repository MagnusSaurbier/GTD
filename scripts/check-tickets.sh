#!/usr/bin/env bash
# Enforces docs/TICKETS.md — tickets are GitHub issues — the parts a script can see:
#
#   scripts/check-tickets.sh            gate mode: exits 1 on any problem (called by check.sh)
#   scripts/check-tickets.sh --status   board mode: prints the board and problems, always exits 0
#                                       (run at session start by .claude/settings.json)
#
# Checks (all against the open issues of the GitHub repo `origin` points at):
#  1. Every issue labelled "in progress" names a branch and has the State/Remaining/Handover
#     sections of the template.
#  2. On a branch other than main that has code commits (anything outside docs/*.md/.claude/
#     .github) since main, exactly one "in progress" issue names that branch — no code without
#     a ticket.
#  3. An "in progress" issue is not stale: no code commit on its branch is newer than the
#     issue's last edit (GitHub's updatedAt).
#  4. An "in progress" issue whose branch is already merged into main must be closed with its
#     Outcome filled in — reported so that whoever sees it does it.
# Without gh, without auth or without network the script prints SKIPPED and exits 0: the rule
# still applies, it just cannot be checked here.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

STATUS_MODE=0
[ "${1:-}" = "--status" ] && STATUS_MODE=1

if ! command -v gh >/dev/null 2>&1; then
    echo "SKIPPED: gh not installed — cannot check the issue board (docs/TICKETS.md still applies)"; exit 0
fi
if ! issues_json="$(gh issue list --state open --limit 200 --json number,title,labels,body,updatedAt,url 2>&1)"; then
    echo "SKIPPED: gh could not list issues (${issues_json%%$'\n'*}) — docs/TICKETS.md still applies"; exit 0
fi

current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
code_excludes=(-- . ':(exclude)docs' ':(exclude)*.md' ':(exclude).claude' ':(exclude).github')
in_git=1; git rev-parse --verify main >/dev/null 2>&1 || in_git=0

# One line per issue: number|state|branch|updated_epoch|url|title|shape_problems
rows="$(python3 - "$issues_json" <<'PY'
import json, re, sys, datetime
issues = json.loads(sys.argv[1])
for i in sorted(issues, key=lambda i: i["number"]):
    labels = {l["name"] for l in i["labels"]}
    state = "in progress" if "in progress" in labels else "open"
    body = i["body"] or ""
    m = re.search(r"\*\*Branch:\*\*\s*`?([^`·\n]*)`?", body)
    branch = (m.group(1).strip() if m else "").strip("`").strip()
    if branch in ("", "—", "-"): branch = ""
    problems = []
    if state == "in progress":
        for h in ("State", "Remaining", "Handover"):
            if not re.search(r"^## %s\b" % h, body, re.M): problems.append("missing '## %s'" % h)
        if not branch: problems.append("**Branch:** is empty")
    updated = int(datetime.datetime.fromisoformat(i["updatedAt"].replace("Z", "+00:00")).timestamp())
    print("|".join([str(i["number"]), state, branch, str(updated), i["url"], i["title"].replace("|", "/"), "; ".join(problems)]))
PY
)"

problems=0
problem() { echo "  PROBLEM: $*"; problems=$((problems + 1)); }

echo "in progress"
found=0; tickets_for_current=0
while IFS='|' read -r number state branch updated url title shape; do
    [ "$state" = "in progress" ] || continue
    found=1
    echo "  #$number — $title"
    echo "      branch: ${branch:-—} · $url"
    [ -n "$shape" ] && problem "#$number: $shape"
    [ -n "$branch" ] || continue
    [ "$branch" = "$current_branch" ] && tickets_for_current=$((tickets_for_current + 1))
    [ "$in_git" -eq 1 ] || continue
    if git rev-parse --verify --quiet "$branch" >/dev/null; then
        if [ "$branch" != "main" ] && git merge-base --is-ancestor "$branch" main 2>/dev/null \
           && [ "$(git rev-parse "$branch")" != "$(git rev-parse main)" ]; then
            problem "#$number: branch '$branch' is merged into main — fill in ## Outcome and close the issue (docs/TICKETS.md rule 4)"
            continue
        fi
        last_code="$(git log -1 --format=%ct "main..$branch" "${code_excludes[@]}" 2>/dev/null || true)"
        if [ -n "$last_code" ] && [ "$last_code" -gt "$updated" ]; then
            problem "#$number: stale — '$branch' has code commits newer than the issue's last edit ($(git log -1 --format='%h %cs' "main..$branch" "${code_excludes[@]}")). Update ## State / ## Remaining: gh issue edit $number --body-file …"
        fi
    elif [ "$branch" != "$current_branch" ]; then
        echo "      (branch '$branch' not in this checkout)"
    fi
done <<<"$rows"
[ "$found" -eq 0 ] && echo "  (none)"

echo "open, not started"
found=0
while IFS='|' read -r number state branch updated url title shape; do
    [ "$state" = "open" ] || continue
    found=1; echo "  #$number — $title"
done <<<"$rows"
[ "$found" -eq 0 ] && echo "  (none)"

if [ "$in_git" -eq 1 ] && [ "$current_branch" != "main" ] && [ "$current_branch" != "HEAD" ]; then
    has_code="$(git log -1 --format=%h "main..$current_branch" "${code_excludes[@]}" 2>/dev/null || true)"
    if [ -n "$has_code" ] || [ "$STATUS_MODE" -eq 0 ]; then
        if [ "$tickets_for_current" -eq 0 ]; then
            problem "no 'in progress' issue names the current branch '$current_branch' — open one (or label the existing one) and set **Branch:** (docs/TICKETS.md rules 1–2)"
        elif [ "$tickets_for_current" -gt 1 ]; then
            problem "$tickets_for_current 'in progress' issues name '$current_branch'; one issue per branch"
        fi
    fi
fi

if [ "$problems" -gt 0 ]; then
    echo "check-tickets.sh: $problems problem(s) — see docs/TICKETS.md"
    [ "$STATUS_MODE" -eq 1 ] && exit 0
    exit 1
fi
echo "check-tickets.sh: ok"
