# Solo5 hvt crash-boundary experiment

This experiment connects the abstract commit boundary in
`formal/CrashRecovery.tla` to the concrete Chamelon-backed Solo5 hvt runtime.

It deliberately tests the two sides of the most important boundary:

```text
before Store.set /capsule
------------------------- commit boundary -------------------------
after Store.set returned Ok, before visible state / HTTP response
```

## Mechanism

The unikernel exposes a test-only runtime argument:

```text
--failure-point none
--failure-point before-commit
--failure-point after-commit-before-publish
```

The default is `none`.

A failure point does not simulate a crash internally. It logs a marker and waits
forever. The CI harness observes that marker and kills the external `solo5-hvt`
tender. The same backing image is then attached to a fresh guest.

There is no HTTP administration endpoint and ordinary execution is unchanged
when the argument is left at its default.

## Case 1: crash before commit

Starting from `Locked`:

```text
Arm(id=crash-before)
  -> pure next machine exists in guest memory
  -> pause before Store.set
  -> tender killed
  -> reboot same image
  -> Locked
  -> retry Arm(id=crash-before)
  -> Fresh Applied Armed
```

The uncommitted candidate state and receipt disappear with the guest.

## Case 2: crash after commit but before publish

Starting from `Locked`:

```text
Arm(id=crash-after)
  -> Store.set /capsule returns Ok
  -> pause before current := next and before HTTP response
  -> tender killed
  -> reboot same image
  -> Armed with receipt(crash-after)
  -> retry Arm(id=crash-after)
  -> Replay Applied Armed
```

The caller did not need to observe a response for the committed request identity
to survive recovery.

## Correspondence claim

These runtime cases exercise the same observable distinction used by the bounded
TLA+ crash-recovery model:

- crash before commit recovers the previous durable pair and retry is fresh,
- crash after commit but before publish recovers the new durable pair and retry
  is replay.

This is runtime correspondence at the application/KV commit boundary. It is not
a proof that every internal Chamelon or block-device write maps one-to-one to a
TLA+ step.

## Durability limit

Here, "commit" means that `Mirage_kv.RW.set` returned `Ok ()` and that the
same backing image recovered the value after the hvt tender was killed.

This experiment still does not establish host-power-loss durability. It does not
simulate loss of the host kernel, host page cache, controller cache, or physical
media power.
