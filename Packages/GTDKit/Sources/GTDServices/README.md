# GTDServices

Turns a `Reduction` into a file transaction: reduce → diff → encode → `VaultStore.commit` → push the inverse ops onto the undo journal. Public types: `VaultBackend`, `SnapshotDiff`, `UndoJournal`, `ServiceError`.

**Owned by T16** — T00 created only the public signatures listed in `docs/ARCHITECTURE.md` §4
so that dependants compile. The bodies throw `notImplemented` or return empty values.

## Platform guards (ARCHITECTURE §5)

Foundation-only. The diff and the journal are pure and must be testable on Linux against `SampleVault.copyToTemporaryDirectory()`. **Remember the extraOps rule** (ARCHITECTURE §4): a path named in `Reduction.extraOps` is owned by `extraOps` — the diff emits nothing for it. T16 adds the `GTDAppCore.GTDBackend` conformance here (that import direction is allowed; Feature → GTDServices is not).

## Testing

`cd Packages/GTDKit && swift test --filter GTDServicesTests`
