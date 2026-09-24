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
#  5. Versions: every "in progress" issue claims a version (**Version:** in its body) that is
#     above main's MARKETING_VERSION and that no other open issue claims; on the current branch,
#     App/Version.xcconfig's MARKETING_VERSION equals the version its issue claims. --status prints the
#     next free version, which is what a new issue claims. Only what concerns the current
#     branch's issue fails the gate; another branch's missing claim or collision is a NOTE, so
#     one session's omission never blocks another's push.
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

# One line per issue: number|state|branch|version|updated_epoch|url|title|shape_problems
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
    m = re.search(r"\*\*Version:\*\*\s*`?([^`·\n]*)`?", body)
    version = (m.group(1).strip() if m else "").strip("`").strip()
    if version in ("—", "-"): version = ""
    if state == "in progress":
        for h in ("State", "Remaining", "Handover"):
            if not re.search(r"^## %s\b" % h, body, re.M): problems.append("missing '## %s'" % h)
        if not branch: problems.append("**Branch:** is empty")
        if version and not re.fullmatch(r"\d+\.\d+", version): problems.append("**Version:** '%s' is not <major>.<minor>" % version)
    updated = int(datetime.datetime.fromisoformat(i["updatedAt"].replace("Z", "+00:00")).timestamp())
    print("|".join([str(i["number"]), state, branch, version, str(updated), i["url"], i["title"].replace("|", "/"), "; ".join(problems)]))
PY
)"

problems=0
problem() { echo "  PROBLEM: $*"; problems=$((problems + 1)); }

echo "in progress"
found=0; tickets_for_current=0
while IFS='|' read -r number state branch version updated url title shape; do
    [ "$state" = "in progress" ] || continue
    found=1
    echo "  #$number — $title"
    echo "      branch: ${branch:-—} · version: ${version:-—} · $url"
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
while IFS='|' read -r number state branch version updated url title shape; do
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

# 5. Versions — the board is the registry: main's App/Version.xcconfig is what shipped, every "in progress"
#    issue's **Version:** is a claim, and the next free one is one minor above the highest of both.
main_version=""
if [ "$in_git" -eq 1 ]; then
    main_version="$(git show main:App/Version.xcconfig 2>/dev/null | sed -n 's/^ *MARKETING_VERSION *= *\([0-9][0-9.]*\).*/\1/p' | head -1)"
    # Before 0.17 the number lived in project.yml.
    [ -n "$main_version" ] || main_version="$(git show main:project.yml 2>/dev/null | sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9][0-9.]*\)"\{0,1\}.*/\1/p' | head -1)"
fi
here_version="$(sed -n 's/^ *MARKETING_VERSION *= *\([0-9][0-9.]*\).*/\1/p' App/Version.xcconfig 2>/dev/null | head -1)"
version_report="$(python3 - "$main_version" "$here_version" "$current_branch" "$rows" <<'PY2'
import sys
main_v, here_v, current, rows = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
def parse(v):
    try:
        major, minor = v.split("."); return (int(major), int(minor))
    except Exception:
        return None
claims = {}   # version -> [issue numbers]
mine = set()  # issues whose branch is the current one: these fail the gate, the rest are notes
highest = parse(main_v) or (0, 0)
findings = []  # (concerns_current, text)
for line in rows.splitlines():
    if not line.strip(): continue
    number, state, branch, version, *_ = line.split("|")
    if state != "in progress": continue
    own = branch == current
    if own: mine.add(number)
    if not version:
        findings.append((own, "#%s claims no version — put the next free one in **Version:** and App/Version.xcconfig (docs/TICKETS.md rule 2)" % number))
        continue
    v = parse(version)
    if v is None: continue
    claims.setdefault(version, []).append(number)
    if v > highest: highest = v
    if main_v and parse(main_v) and v <= parse(main_v):
        findings.append((own, "#%s claims version %s, but main already is %s — claim the next free one" % (number, version, main_v)))
    if own and here_v and here_v != version:
        findings.append((True, "#%s claims version %s, but App/Version.xcconfig on '%s' says MARKETING_VERSION %s — set it to %s" % (number, version, current, here_v, version)))
for version, numbers in sorted(claims.items()):
    if len(numbers) > 1:
        findings.append((bool(mine & set(numbers)), "version %s is claimed by #%s — one version per issue; the later claim takes the next free version" % (version, " and #".join(numbers))))
print("NEXT %d.%d" % (highest[0], highest[1] + 1))
for own, text in findings: print(("PROBLEM " if own else "NOTE ") + text)
PY2
)"
echo "versions"
echo "  main: ${main_version:-?} · next free: $(echo "$version_report" | sed -n 's/^NEXT //p') (claim it in a new issue's **Version:** and in App/Version.xcconfig)"
while IFS= read -r line; do
    case "$line" in
        PROBLEM\ *) problem "${line#PROBLEM }" ;;
        NOTE\ *) echo "  NOTE: ${line#NOTE }" ;;
    esac
done <<<"$version_report"

if [ "$problems" -gt 0 ]; then
    echo "check-tickets.sh: $problems problem(s) — see docs/TICKETS.md"
    [ "$STATUS_MODE" -eq 1 ] && exit 0
    exit 1
fi
echo "check-tickets.sh: ok"
