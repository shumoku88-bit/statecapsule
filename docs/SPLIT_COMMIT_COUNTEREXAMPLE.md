# Split-commit counterexample

This is a negative control for the crash-recovery model.

The safe model in `CrashRecovery.tla` makes the capsule state and the request
receipt set authoritative at one abstract recoverable commit point. This file asks
whether that requirement is actually necessary.

The deliberately unsafe model starts from an already durable `Armed` state and a
fresh successful `Consume`. It then persists the two pieces separately.

## State first

```text
durable state = Armed
durable receipts = {}

write state = Used
crash
recover
```

Recovery observes `Used` but has no request receipt proving which request caused
the consume. TLC must violate `RecoveredUsedHasReceipt`.

The retry consequence is important: because the request id was forgotten, the
same request can no longer be replayed with its original successful outcome. A
system that guesses from current state would silently rewrite the meaning of the
request.

## Receipt first

```text
durable state = Armed
durable receipts = {}

write receipt(id=x, Consume, Applied Used)
crash
recover
```

Recovery observes a successful consume receipt while the durable state is still
`Armed`. TLC must violate `RecoveredAppliedReceiptRequiresUsed`.

A retry could now replay success even though the recovered state says the consume
has not happened. A different request could still consume the `Armed` capsule,
which is exactly the sort of contradiction the atomic pair is meant to exclude.

## CI meaning

`tools/check-split-commit-counterexample` intentionally expects TLC to fail both
unsafe configurations for the named invariants. CI succeeds only when both
counterexamples are found.

That makes this a negative control:

- `CrashRecovery.tla` should have no counterexample under the abstract atomic
  commit contract.
- `SplitCommitCounterexample.tla` should have counterexamples when state and
  receipt durability are split by a crash.

This does not prove that a particular filesystem, block device, database, journal,
or MirageOS storage layer implements the safe contract. It only demonstrates, in
the bounded model, why an unqualified "write state, then write receipt" or the
reverse ordering is insufficient.
