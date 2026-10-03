# StateCapsule

StateCapsule is an experiment in building tiny, inspectable, single-purpose
computers from small state machines.

The first capsule is deliberately narrow:

```text
Locked --Arm--> Armed --Consume--> Used
```

That small machine is now carried all the way from a pure OCaml transition
function, through bounded TLA+ models, request replay semantics, a MirageOS HTTP
boundary, and a persistent Solo5 `hvt` unikernel.

## What is established

StateCapsule currently has executable evidence for:

- the three-state transition relation,
- OCaml/TLA+ correspondence for successful transitions,
- request identity and replay semantics,
- replay of refused outcomes as well as successful outcomes,
- bounded crash-recovery invariants,
- counterexamples showing why state and request receipts must not be persisted
  as independent writes,
- MirageOS Unix and Solo5 `hvt` HTTP execution,
- persistence of the complete request machine through one Chamelon
  `/capsule` snapshot,
- recovery of state and request receipts after process/guest restart,
- replay after restart instead of re-execution,
- fail-closed startup when the persisted snapshot is corrupt or semantically
  inconsistent.

The important persistence unit is not merely the current state. It is the state
together with the request receipts that explain how that state was reached.

For a fresh request, the intended boundary is:

```text
evaluate request
      |
      v
build complete next snapshot
      |
      v
persist /capsule
      |
      v
publish state and HTTP response
```

A response is not published before the persistent commit succeeds.

## Why the project stays small

StateCapsule is not intended to become a general application server or database.

Its purpose is to make a small computer understandable enough that its important
claims can be connected to concrete evidence:

```text
semantics
  -> formal model
  -> counterexample
  -> storage contract
  -> implementation
  -> runtime evidence
```

The project prefers a narrow claim that can be inspected over a broad claim that
cannot.

## Current boundary

The persistence evidence currently qualifies restart continuity for the tested
process, guest, tender, and backing-image path.

It does **not** yet establish survival of:

- host power loss,
- host kernel failure,
- volatile host page-cache loss,
- storage-controller cache loss,
- arbitrary torn host writes.

The current Solo5 `hvt` block path does not expose a host persistence barrier
that StateCapsule can point to as evidence for those stronger claims.

The HTTP service also has no TLS, authentication, authorization, or
multi-replica semantics. It must not be exposed to the public Internet.

## Repository map

- `core/` — pure state and request-machine semantics
- `formal/` — TLA+ models and negative controls
- `mirage/` — MirageOS HTTP and persistent Chamelon adapter
- `test/` — OCaml tests
- `tools/` — correspondence, model-checking, build, boot, reboot, and runtime
  evidence scripts
- `docs/` — design decisions, crash model, counterexamples, and storage
  boundary notes

The current persistence milestone is documented in
`docs/CHAMELON_PERSISTENCE_EXPERIMENT.md`.
