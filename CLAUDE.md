# Instructions for agents working in this repo

1. Read `docs/ARCHITECTURE.md` fully and the sections of `docs/REQUIREMENTS.md` your task names.
2. If you were given a task number, your brief is `agent_task/NN-*.md`; the shared rules are in `agent_task/README.md`.
3. Edit only the paths your task owns. `Packages/GTDKit/Package.swift` and the contracts in
   ARCHITECTURE §4 are frozen — follow the "Contract changes" procedure if you must deviate.
4. **Never read from or write to the real Obsidian vault** under
   `~/Library/Mobile Documents/iCloud~md~obsidian/`. Use `GTDFixtures` / temp directories.
5. The app never hard-deletes vault files and only `GTDVault` touches the file system.
6. Gate before reporting done: `scripts/check.sh`. Report failures verbatim.
7. Product principles that apply to every screen: few inputs, chips not dropdowns, **no lying
   defaults** (undecided = empty; suggestions look different from confirmed values).
8. Out of scope: everything in REQUIREMENTS §12.
