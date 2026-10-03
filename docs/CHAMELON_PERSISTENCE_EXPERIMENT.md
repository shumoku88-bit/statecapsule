# Chamelon persistence experiment

This experiment is the first concrete implementation of the abstract storage
contract modeled in `CrashRecovery.tla`.

## Shape

The application persists one key, `/capsule`, through `Mirage_kv.RW`.
The value is produced and validated by `Request_machine.snapshot` and
`Request_machine.restore`.

The MirageOS layer never serializes individual state or receipt fields.

## Commit boundary

For a fresh request:

```text
pure Request_machine.submit
  -> complete next request machine in memory
  -> Store.set /capsule (snapshot next)
  -> update visible in-memory machine
  -> send HTTP response
```

This preserves the ordering required by the TLA+ model: response visibility does
not precede the successful storage call.

Mutating HTTP requests are serialized with a single Lwt mutex. This intentionally
matches the current single-in-flight mutation assumption of the formal model.

If a storage commit returns an error, the adapter marks itself blocked and stops
serving ordinary state or mutation responses. It does not guess whether the write
became durable.

## Recovery validation

The snapshot format has:

- a format marker,
- final state,
- ordered request receipts,
- an integrity checksum.

Restore starts from `Locked`, re-submits each stored request in original order,
and requires every generated outcome to match the stored outcome. The reconstructed
final state must equal the stored final state.

This rejects duplicate request ids, conflicts, impossible outcomes, state/receipt
mismatches, bad encodings, unsupported formats, and checksum failures.

## Evidence added by this experiment

Unix and Solo5 hvt smoke tests reuse the same Chamelon image across restarts and
verify durable state plus durable replay receipts at both `Armed` and `Used`.

They also replace `/capsule` with malformed data and require startup to fail
closed.

## Claim boundary

The experiment does not qualify host-power-loss durability. The lower Solo5 hvt
block path does not currently expose a persistence barrier that StateCapsule can
use as evidence for that stronger claim.
