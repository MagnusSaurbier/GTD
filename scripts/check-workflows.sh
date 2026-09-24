#!/usr/bin/env bash
# Enforces .github/workflows/README.md on every workflow file (a text-level check; no YAML
# parser is assumed on the machine). Called by scripts/check.sh. Exits 1 on any problem.
#
#  1. A workflow with a push: or pull_request: trigger has paths-ignore listing '**.md',
#     'docs/**', '.claude/**' and '.github/**.md' — docs commits run nothing.
#  2. A push: trigger is restricted with branches: — never every branch.
#  3. A deploy/release/distribute workflow has no push: or pull_request: trigger at all;
#     it runs on workflow_dispatch: or tags: only.
#  4. Every non-deploy workflow declares concurrency: with cancel-in-progress: true.
#  5. No workflow runs on schedule:.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

problems=0
problem() { echo "  PROBLEM: $*"; problems=$((problems + 1)); }

shopt -s nullglob
files=(.github/workflows/*.yml .github/workflows/*.yaml)
if [ "${#files[@]}" -eq 0 ]; then
    echo "check-workflows.sh: no workflows (nothing to spend Actions minutes on) — ok"
    exit 0
fi

for f in "${files[@]}"; do
    echo "checking $f"
    # strip comments so a commented-out trigger does not count
    body="$(sed 's/[[:space:]]#.*$//; /^[[:space:]]*#/d' "$f")"
    has_push=0;  grep -Eq '^[[:space:]]*push:' <<<"$body" && has_push=1
    has_pr=0;    grep -Eq '^[[:space:]]*pull_request(_target)?:' <<<"$body" && has_pr=1
    grep -Eq '^[[:space:]]*on:[[:space:]]*\[.*\b(push|pull_request)\b' <<<"$body" && { has_push=1; has_pr=1; }
    grep -Eq '^[[:space:]]*on:[[:space:]]*(push|pull_request)[[:space:]]*$' <<<"$body" && { has_push=1; has_pr=1; }

    case "$(basename "$f")" in
        *deploy*|*release*|*distribute*|*testflight*)
            # rule 4: tags or workflow_dispatch only
            [ "$has_pr" -eq 1 ] && problem "$f: a deployment workflow may not run on pull_request: (README rule 4)"
            if [ "$has_push" -eq 1 ]; then
                grep -Eq '^[[:space:]]*tags:' <<<"$body" || problem "$f: a deployment workflow's push: trigger must be tags: only (README rule 4)"
                grep -Eq '^[[:space:]]*branches:' <<<"$body" && problem "$f: a deployment workflow may not run on branch pushes (README rule 4)"
            fi
            grep -Eq '^[[:space:]]*(workflow_dispatch|tags):' <<<"$body" || problem "$f: a deployment workflow needs workflow_dispatch: or tags: (README rule 4)"
            ;;
        *)
            if [ "$has_push" -eq 1 ] || [ "$has_pr" -eq 1 ]; then
                grep -Eq '^[[:space:]]*paths-ignore:' <<<"$body" || problem "$f: push/pull_request trigger without paths-ignore (README rule 1)"
                for pat in '\*\*\.md' 'docs/\*\*' '\.claude/\*\*' '\.github/\*\*\.md'; do
                    grep -Eq -- "$pat" <<<"$body" || problem "$f: paths-ignore must include the pattern matching /$pat/ (README rule 1)"
                done
            fi
            if [ "$has_push" -eq 1 ] && ! grep -Eq '^[[:space:]]*branches:' <<<"$body"; then
                problem "$f: push: without branches: — would run on every branch push (README rule 3)"
            fi
            grep -Eq '^[[:space:]]*concurrency:' <<<"$body" && grep -Eq 'cancel-in-progress:[[:space:]]*true' <<<"$body" \
                || problem "$f: needs concurrency: … cancel-in-progress: true (README rule 5)"
            ;;
    esac
    grep -Eq '^[[:space:]]*schedule:' <<<"$body" && problem "$f: schedule: triggers are not allowed (README rule 6)"
done

if [ "$problems" -gt 0 ]; then
    echo "check-workflows.sh: $problems problem(s) — see .github/workflows/README.md"
    exit 1
fi
echo "check-workflows.sh: ok"
