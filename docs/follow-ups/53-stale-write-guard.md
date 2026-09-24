# T53 — Refuse a write built on a snapshot the vault has moved past

**Follow-up from T41 (traceability gap: N3) · any time; no device needed**

## Model recommendation

**Difficulty:** Hard (judgment-heavy) · **Recommended model:** Opus

This is a data-safety rule, and the failure mode of getting it wrong is the one the whole design
exists to prevent: refusing too much makes the app unusable offline; refusing too little loses an
edit. It is also entirely testable on Linux, so the difficulty is all in the decision, not the
typing.

## The gap

`N3` says the app is sync-safe by design, and undo already enforces it: an undo journal entry
carries a content hash per file and is refused as `ServiceError.undoStale` when any of them
changed (T16). **An ordinary command has no such check.**

`GTDServicesTests/SyncScenarioTests.aDeviceWritingFromABeforeTheRenameSnapshotDuplicatesRatherThanLoses`
pins what happens today: device A renames `Actions/Call the bank.md`; device B, whose snapshot
predates the rename, saves an edit and writes the **old** path. Both files then exist. Nothing is
lost — that is why this is a follow-up and not a T41 bug fix — but the user is left with a
duplicate they have to reconcile by hand, and the same shape of race can overwrite a field edited
elsewhere.

## Owns

`GTDServices/VaultBackend.swift`, `GTDServices/UndoJournal.swift` (the hash helper is there),
`GTDModel` only if a new error case is needed, `GTDServicesTests/`.

## Deliverables

1. **Decide the rule and write it down first**, in `docs/ARCHITECTURE.md` §6 as a dated decision,
   before writing code. The question is narrow: *before committing, does the backend verify that
   the files it is about to write still hold what its snapshot was built from?* Consider at least:
   - hashing only the paths the command touches (cheap: T41 measured one command as three
     constant-size reads, and `hashes(touchedBy:)` already does exactly this for undo),
   - what happens offline and on a slow sync, where a stale snapshot is normal and refusing every
     command would make the app useless,
   - a command that *creates* a file (there is nothing to compare),
   - `logRoutineStep`, which is per-device by construction and must never be refused.
2. **Implement it as a refusal, never as a merge.** The app does not resolve conflicts (N3 §7.5);
   it reports them. The error must carry the path and reach `AppModel.lastError`, with copy that
   says what the person should do ("this note changed elsewhere — reopen it").
3. **Re-scan first, refuse second.** A refusal the user can fix by waiting three seconds is worse
   than a re-read: ask the store for a fresh snapshot before deciding.
4. Tests: turn the pinned duplication test above into the refusal case, and add the offline case
   (a long-stale snapshot whose files did *not* change must still commit).

## Acceptance

- The rename race produces one note and one clear refusal, not two notes.
- No test asserts that a stale-but-unchanged vault refuses a write.
- `scripts/check.sh` green; `docs/TRACEABILITY.md`'s N3 row updated.

## Result

Done 2026-09-24 (issue #7). Rule: ARCHITECTURE §6, 2026-09-24. `VaultBackend.refuseIfStale` reads
every path a command would put, delete or move away from and compares it with the base
snapshot's entity encoded (`SnapshotDiff.expectedContents`) — absent for a note the snapshot does
not have; a mismatch is `ServiceError.staleWrite(path:)`, which `abandonQueue` handles like any
refused write (re-scan, publish, report with "reopen the note and make the change again").
`perform` pulls the store's newest snapshot before reducing (re-scan first). Exempt: the routine
log, `.moveFolder`, move destinations. Tests: `SyncScenarioTests` (rename race → one note and one
refusal; field edited elsewhere; long-stale snapshot with unchanged files commits twice; create
collision; routine log never refused), `QueuedWriteTests` (refusal on `writeFailures()`, snapshot
reverts to the other writer's text), `SnapshotDiffTests` (the expectation list).
