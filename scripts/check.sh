#!/usr/bin/env bash
# The gate every task must pass before reporting done (CLAUDE.md rule 8).
#
#   scripts/check.sh          package build + tests, docs check, iOS-simulator build
#   scripts/check.sh --app    additionally regenerate the Xcode project and build the app
#
# Steps that need Xcode are skipped with a clear SKIPPED line when the tool is missing, so the
# script is usable both on a Mac and in the Linux containers the build-out agents run in.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$REPO_ROOT/Packages/GTDKit"
SCHEME="GTDKit"
APP_SCHEME="GTD"

WITH_APP=0
for arg in "$@"; do
    case "$arg" in
        --app) WITH_APP=1 ;;
        -h|--help) sed -n '2,8p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

step() { printf '\n=== %s\n' "$1"; }
skip() { printf 'SKIPPED: %s\n' "$1"; }

step "swift build (Packages/GTDKit)"
(cd "$PACKAGE_DIR" && swift build)

step "swift test (Packages/GTDKit)"
(cd "$PACKAGE_DIR" && swift test)

step "docs check"
"$REPO_ROOT/scripts/check-docs.sh"

step "xcodebuild — package for the iOS Simulator"
if command -v xcodebuild >/dev/null 2>&1; then
    (cd "$PACKAGE_DIR" && xcodebuild build \
        -scheme "$SCHEME" \
        -destination 'generic/platform=iOS Simulator' \
        -skipMacroValidation \
        | tail -20)
else
    skip "xcodebuild not available (Linux). Asset and string catalogs are compiled by Xcode's build system only — verify this step on a Mac."
fi

if [ "$WITH_APP" -eq 1 ]; then
    step "xcodegen — regenerate GTD.xcodeproj"
    if command -v xcodegen >/dev/null 2>&1; then
        (cd "$REPO_ROOT" && xcodegen generate)
    else
        skip "xcodegen not available (Linux). Install with: brew install xcodegen"
    fi

    step "xcodebuild — GTD app for macOS"
    if command -v xcodebuild >/dev/null 2>&1 && [ -d "$REPO_ROOT/GTD.xcodeproj" ]; then
        (cd "$REPO_ROOT" && xcodebuild build \
            -project GTD.xcodeproj \
            -scheme "$APP_SCHEME" \
            -destination 'platform=macOS' \
            -skipMacroValidation \
            CODE_SIGNING_ALLOWED=NO \
            | tail -20)
    else
        skip "xcodebuild not available or GTD.xcodeproj not generated (Linux)."
    fi
fi

printf '\n=== check.sh finished\n'
