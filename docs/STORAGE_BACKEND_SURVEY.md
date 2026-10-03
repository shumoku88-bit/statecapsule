# MirageOS storage backend survey

Date: 2026-10-04

This note applies the storage contract derived in
`CRASH_RECOVERY_MODEL.md` and the negative control in
`SPLIT_COMMIT_COUNTEREXAMPLE.md` to concrete MirageOS storage surfaces.

The goal is not to select a general database. The goal is to find the
smallest storage boundary that can preserve one authoritative capsule snapshot:

```text
snapshot = {
  capsule state,
  request receipts
}
```

State and receipts must not become independently authoritative.

## Current platform facts

StateCapsule already builds and boots as a Solo5 `hvt` unikernel.

Current MirageOS exposes raw block devices through `Mirage_block.S`, and
`block_of_file` maps a named Solo5 block device to a host-backed image. The
MirageOS configuration API also exposes Chamelon, a read/write key-value store
implemented using the littlefs design on top of a block device.

Relevant upstream surfaces:

- MirageOS block and Chamelon configuration:
  https://github.com/mirage/mirage/blob/main/lib/mirage.mli
- Mirage block signature:
  https://github.com/mirage/mirage-block/blob/main/src/mirage_block.mli
- Solo5 Mirage block driver:
  https://github.com/mirage/mirage-block-solo5/blob/main/src/block.ml
- Solo5 hvt block tender:
  https://github.com/Solo5/solo5/blob/main/tenders/hvt/hvt_module_blk.c
- Mirage key/value signature:
  https://github.com/mirage/mirage-kv/blob/main/src/mirage_kv.mli
- littlefs design:
  https://github.com/littlefs-project/littlefs
- Irmin:
  https://github.com/mirage/irmin

At the time of this survey, MirageOS 4.11.2 and Solo5 0.12.0 are the current
released lines relevant to this project.

## Important durability boundary

`Mirage_block.S` exposes:

- `read`
- `write`
- `get_info`
- `disconnect`

It does not expose an explicit flush or durability-barrier operation.

For the Solo5 hvt backend, Mirage block writes call `solo5_block_write`; the
hvt tender currently services that hypercall with host `pwrite()`. There is no
`fsync()` or equivalent host persistence barrier in that path.

That distinction changes what StateCapsule may honestly claim.

A successful block write can be used to investigate:

- persistence across unikernel restart,
- persistence across tender/process restart,
- recovery from a guest crash.

It is not, by itself, evidence that the write survives:

- host-kernel crash,
- host power loss,
- storage-controller cache loss.

StateCapsule must therefore keep these claims separate.

The first concrete persistence milestone should target **guest/tender crash and
reboot continuity**. Host-power-loss durability remains out of scope until an
actual persistence barrier or equivalent backend contract is identified and
tested.

## Candidate A: Chamelon with one snapshot key

MirageOS exposes `chamelon` as a `Mirage_kv.RW` implementation on a block
device. It is a pure-OCaml implementation of the littlefs design.

The `Mirage_kv.RW` contract says that `set` guarantees durability and that
`set` causes the underlying storage layer to flush. littlefs is designed for
power-loss recovery using copy-on-write metadata and recovery of the last known
good state.

For StateCapsule, the important move is to store the whole authoritative pair as
**one value**, not as two keys:

```text
/capsule

{
  format_version,
  generation,
  state,
  receipts,
  checksum
}
```

A successful mutation becomes conceptually:

```text
load current snapshot
evaluate request
build next snapshot in memory
KV.set /capsule next_snapshot
publish response
```

This maps closely to the TLA+ commit point. There is no application-level
state-write followed by receipt-write.

### Advantages

- already integrated into MirageOS configuration,
- works over a Solo5 named block device,
- no new database service,
- one storage value matches the atomic-pair model,
- keeps HTTP unaware of persistence semantics,
- avoids implementing a filesystem or general database,
- allows the serialized snapshot format to stay StateCapsule-specific.

### Limits

- the Mirage/Solo5 block path still lacks an explicit host flush barrier,
- the actual crash claim must be tested rather than inherited from littlefs
  documentation,
- a single-key `set` must be exercised under forced guest/tender crashes,
- corrupt or undecodable snapshots must fail closed.

### Assessment

**Best first implementation experiment.**

The experiment should claim only what it directly demonstrates: reboot continuity
and request replay across a guest/tender crash using the same backing image.

## Candidate B: custom two-slot journal over Mirage_block

A smaller semantic stack is possible by using raw sectors directly.

One possible layout is:

```text
slot A: generation + snapshot + checksum
slot B: generation + snapshot + checksum
```

A mutation writes the inactive slot, verifies it, and finally makes the new
generation authoritative according to a precisely modeled rule. Recovery chooses
the newest valid complete slot; if authority cannot be determined, boot fails
closed.

### Advantages

- storage semantics are completely visible to StateCapsule,
- very small on-disk format,
- easy to mirror directly in TLA+,
- no filesystem-level concepts,
- excellent fit for the project's "small inspectable computer" direction.

### Costs

- StateCapsule would own journal design, checksums, generations, torn-write
  handling, migration, and recovery forever,
- the existing Mirage block surface still provides no host flush barrier,
- correctness work would be substantially larger than the capsule state machine,
- implementing it before testing an existing crash-resilient backend would be
  premature.

### Assessment

**Keep as the fallback and possible later distillation target.**

If Chamelon cannot satisfy the bounded crash tests, a two-slot journal becomes the
next serious candidate.

## Candidate C: tar_kv_rw

MirageOS also exposes a read/write tar store over a block device. It is explicitly
append-only and has restrictions around mutation and rename.

An append-only log is attractive for receipts, but StateCapsule still needs one
authoritative capsule snapshot and a clear recovery/commit rule. The tar surface
does not remove that design problem.

### Assessment

**Do not use for the first persistence implementation.**

It provides little advantage over a purpose-built journal while introducing a
format whose crash semantics are not the contract StateCapsule needs to establish.

## Candidate D: Irmin

Irmin provides structured, Git-like persistent storage, atomic updates, history,
branches, synchronization, and distributed-storage machinery.

Those are useful properties for a much larger system, but they are not current
StateCapsule requirements.

### Assessment

**Reject for now.**

It would enlarge the semantic and dependency surface while solving problems the
capsule intentionally does not have: branching, replication, synchronization, and
distributed coordination.

## Decision

The next implementation experiment should use:

```text
Solo5 hvt
  -> named block image
  -> Chamelon / Mirage_kv.RW
  -> one /capsule snapshot key
  -> pure StateCapsule persistence adapter
  -> existing request machine
  -> HTTP adapter
```

The snapshot should contain state and receipts together.

The storage adapter must expose a narrow interface such as:

```text
load : unit -> snapshot load_result
commit : snapshot -> commit_result
```

It should not expose generic KV operations to the core or HTTP layer.

## Required evidence before widening the claim

The first implementation PR should not claim generic crash atomicity merely
because Chamelon or littlefs is crash-oriented.

It should add executable evidence for this exact stack:

1. boot with a fresh image and observe `Locked`,
2. persist a refusal receipt,
3. persist `Armed`,
4. stop/kill the unikernel or tender,
5. boot again with the same image,
6. observe `Armed`,
7. retry the old refusal and receive the original replayed refusal,
8. persist successful `Consume`,
9. stop/kill before a response is considered observed if the test harness can
   force that boundary,
10. reboot and observe `Used`,
11. retry the same consume id and receive replay rather than re-execution,
12. present malformed or ambiguous persistent data and require fail-closed boot.

Only properties demonstrated by those tests should be added to the project
claims.

## Explicitly not established

Even after that experiment passes, StateCapsule must not yet claim survival of:

- host power failure,
- host kernel panic,
- volatile host page-cache loss,
- disk-controller cache loss,
- arbitrary torn host writes,

because the current Solo5 hvt block path does not expose a host persistence
barrier that StateCapsule can point to as evidence.

That is a separate storage-contract problem, not something to blur into the guest
crash model.
