#!/usr/bin/env bash
# The performance floor (T41 deliverable 5). Runs `GTDServicesTests.PerformanceTests` against a
# generated vault and prints the timings it measured.
#
#   scripts/benchmark.sh              1 000 action notes (the figure in REQUIREMENTS)
#   scripts/benchmark.sh 5000         5 000 of them
#
# The suite is part of `scripts/check.sh` as well, where it acts as a regression guard: its
# assertions are structural ("the refresh re-read one file, not 1 000"), never wall-clock, so it
# cannot fail because the machine was busy. This script is for the numbers.
#
# What it cannot measure: cold launch, typing latency, scroll smoothness. Those need a device and
# are in `docs/MANUAL_TEST.md` §7.
#
# Note the numbers come out of a **debug** build (`swift test` never optimises). Treat them as an
# upper bound and as something to compare against a later run, not as what the app will feel like.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTES="${1:-1000}"

printf 'benchmark: %s action notes (debug build, %s)\n' "$NOTES" "$(uname -s)"

cd "$REPO_ROOT/Packages/GTDKit"
GTD_BENCH_NOTES="$NOTES" swift test --filter PerformanceTests 2>&1 \
    | grep -E '^\[bench\]|✘|error:' \
    | sed 's/^\[bench\]//'

printf '\nbenchmark: done\n'
