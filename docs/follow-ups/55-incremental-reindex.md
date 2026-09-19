# T55 — Re-index only what a commit touched

**Follow-up from T41 (deliverable 5, performance) · any time; no device needed**

## Model recommendation

**Difficulty:** Medium–hard · **Recommended model:** Opus

The change itself is contained, but the invariant it risks is the one everything else stands on:
*the snapshot is what the files say*. An index that trusts the ops it just applied is an index
that can drift from disk — and a drifted index writes wrong files. This is measurable, testable
work with a very unforgiving failure mode.

## The gap

T41 measured the remaining cost of a command, on Linux in a debug build (`scripts/benchmark.sh`):

| Vault | one `setStatus`, end to end | of which the re-index |
| --- | --- | --- |
| 1 000 notes | 276 ms | ~235 ms |
| 3 000 notes | 749 ms | ~688 ms |

Nearly all of it is `FileVaultStore.commit` calling `refresh()`, which **re-lists the whole vault
and re-assembles the whole snapshot** although it already knows the one file that changed. The
decode is not the problem — T41 proved the index re-reads exactly one file. The listing walk and
the snapshot assembly are, and they scale linearly with the vault while the change does not.

A debug build on a container is not a phone; treat these as an upper bound and re-measure before
and after. But the shape is wrong regardless of the constant.

## Owns

`GTDVault/VaultIndex.swift`, `GTDVault/VaultStore.swift`, `GTDVaultTests/`,
`GTDServicesTests/PerformanceTests.swift` (the numbers this task moves).

## Deliverables

1. **An index update that takes the ops.** After a successful commit, the store knows the exact
   `[VaultFileOp]` it applied: re-stat and re-decode only those paths, drop the moved-from ones,
   and rebuild the snapshot from the entries it already holds. The **watcher path stays a full
   refresh** — an external change is exactly the case where the app does not know what moved.
2. **Cache the assembled snapshot.** `VaultIndex.snapshot(today:)` rebuilds and re-sorts every
   collection on every call (~50 ms at 1 000 notes). Invalidate on any entry change and on a new
   `today`; a snapshot is a value, so caching it is safe as long as the key is honest.
3. **Prove they cannot drift.** The decisive test, not an optional one: after each of a few
   hundred random command sequences, the incrementally-updated snapshot must equal a snapshot
   built by a cold `VaultIndex` over the same directory — byte for byte, including `issues`,
   `modified` dates and `referenceFiles`. `GTDVaultTests/TransactionFuzzTests` is the model to
   copy. If a case cannot be made equal, the incremental path must fall back to a full refresh
   for it, and the test must name the case.
4. Re-run `scripts/benchmark.sh 1000` and `3000`; put the before/after table in the Result.

## Acceptance

- Cold-scan behaviour and every existing `GTDVaultTests`/`GTDServicesTests` unchanged.
- The equality fuzz above passes.
- One command on a 3 000-note vault is materially cheaper, with numbers in the Result.

## Result

_(fill in when done)_
