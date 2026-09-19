# GTD

A personal Getting-Things-Done app for macOS and iOS. Native SwiftUI, fully offline; the data
store is the markdown notes in my Obsidian vault (synced via iCloud). Nothing is hidden in a
database — every action, project, routine and weekly review is a note I can still read and edit
in Obsidian.

## Status

**Feature-complete on paper, unverified on a device.** Every module of `Packages/GTDKit` is
implemented and tested — 851 tests — and the app shell wires them together: the vault backend
behind onboarding, the iPhone tabs and the Mac window, deep links, notifications and background
refresh. The whole app was written on Linux with no Xcode, so every SwiftUI file and all of
`App/` have **never been compiled**. The tests cover the models, the codec, the vault, the
reducer and the rules; they cover no view at all.

So the next step is not a feature. It is `TEST-INSTRUCTIONS.md`: the script for the first machine
with Xcode — build the package, build and launch the app on fixtures, then check that a
security-scoped bookmark into the Obsidian folder really survives a relaunch.

- `docs/TRACEABILITY.md` — where every requirement stands, per requirement, with its tests.
- `docs/KNOWN_ISSUES.md` — what is missing, what is deliberate, what is only assumed.
- `docs/follow-ups/` — six briefs for the gaps that are worth closing, none of them started.

## What it does

Capture in under three seconds from anywhere (Shortcut or App Intent, app need not be running) →
process the inbox one card at a time, LIFO, no skipping → a hard cap of 15 Next actions → areas
and projects as folders, with outcome, steps and a log → waiting-for with a follow-up date that
chases you → defer and due dates with local notifications → morning and bedtime routines run
step by step and logged per day per device → and a weekly review that sweeps the inbox, walks the
deck down to 15, shows the week's real numbers and saves a `KW xx.md` note.

`docs/REQUIREMENTS.md` is the full version; `docs/STYLEGUIDE.md` is how it should look and feel.

## Setup

```bash
brew install xcodegen      # macOS only; generates the (git-ignored) Xcode project
```

Nothing else: the only third-party dependency is Yams, pinned in
`Packages/GTDKit/Package.swift` and resolved by SwiftPM. The migration script's tests want
`pytest`; `scripts/check.sh` skips them with a message when it is not installed.

## Build and test

```bash
scripts/check.sh          # swift build + swift test + docs check + migration tests (+ iOS simulator build)
scripts/check.sh --app    # additionally: xcodegen generate, then build the macOS app
scripts/benchmark.sh      # scan, one command, queries, codec — against a generated vault
```

`scripts/check.sh` is the gate for every change. On a machine without Xcode the `xcodebuild` and
`xcodegen` steps print `SKIPPED` and the script still exits 0 — so asset catalogs, string
catalogs and the app target are only ever validated on a Mac. The Swift commands behind it, and
how to run a single test, are in `CLAUDE.md` under "Commands".

## Run it

```bash
scripts/check.sh --app    # generates GTD.xcodeproj
open GTD.xcodeproj        # run the GTD scheme on "My Mac" or an iPhone simulator; ⌘U for the tests
```

On first launch the app asks for the Obsidian folder that holds the `Actions` notes and remembers
it as a security-scoped bookmark. The launch argument `-useFixtures` (Product → Scheme → Edit
Scheme → Arguments) runs it on the sample snapshot instead, touching no files at all — that is
what the UI tests use, and what to use while the app is still unproven. Signing is yours: set
`DEVELOPMENT_TEAM` in `project.yml` before building for a device; macOS and the simulator build
unsigned.

**Against real notes:** `docs/MANUAL_TEST.md` §0–§8 run on a *copy* of the vault; its §9 is the
first-real-use checklist for the day the app is pointed at the actual one, migration included.

## Where everything is

```
App/                  the app shell (@main); the Xcode project is generated from project.yml
AppTests/ AppUITests/ the shell's unit tests, and launch-and-navigate smoke tests (always -useFixtures)
Packages/GTDKit/      all the code, in 18 small targets — see docs/ARCHITECTURE.md §2
Tools/migrate/        the one-time Python migration from the old vault layout
Shortcuts/            capture Shortcut recipes
scripts/              check.sh (the gate), check-docs.sh, benchmark.sh
docs/                 requirements, style guide, architecture, traceability, known issues,
                      manual test script, contributing guide, follow-ups/, history/
```

Agent instructions live in `CLAUDE.md`; `docs/CONTRIBUTING-AGENTS.md` has the route through the
code for a typical change, and `CLAUDE.md`'s "Keeping this file current" says which document to
fix when your change makes one untrue.
