# Persistence and crash atomicity model

StateCapsule does not choose a storage implementation yet. This model first asks
what a storage layer would have to guarantee before the HTTP capsule could make a
durable replay claim.

The model deliberately separates five things that are easy to accidentally
collapse into one:

- externally visible state,
- volatile working state and request receipts,
- durable committed state and request receipts,
- prepared durable data that has not crossed the commit point,
- the response observed by a caller.

## Request path

A fresh request follows this abstract path:

```text
accept request
  -> compute outcome
  -> update volatile state
  -> record volatile receipt
  -> prepare state
  -> prepare receipts
  -> COMMIT
  -> publish state and response
```

A crash may occur at every step.

Prepared data is not authoritative. Only the commit action promotes the state and
receipt set together to the durable pair. Publishing happens later. That separation
is intentional: an operation may be durable even when its HTTP response was never
observed.

After a readable crash, recovery discards incomplete volatile/prepared work and
reconstructs the running capsule only from the durable pair.

If recovery cannot determine a committed durable pair, the model enters
`blocked`. There is no transition from that state back into request service. The
model therefore does not guess whether an ambiguous operation succeeded or failed.

## Retry after a crash

Two cases matter most.

If a crash happens before commit, neither the state transition nor its request
receipt is authoritative. Recovery returns to the previous durable pair. Retrying
the request is fresh.

If a crash happens after commit but before publish/response, recovery restores the
new state and the stored receipt. Retrying the same id and command is a replay. The
command is not evaluated again.

For a successful consume this means:

```text
Armed
  -> Consume(id=x)
  -> durable commit: state=Used + receipt(x, Consume, Applied Used)
  -> crash before response
  -> recover Used + receipt
  -> retry id=x
  -> Replay Applied Used
```

There is no second consume.

## Invariants checked by TLC

The bounded model uses the existing two request ids and two commands. It checks:

- durable and volatile request ids remain uniquely bound,
- externally visible state never gets ahead of durable state,
- idle execution is reconstructed exactly from the durable pair,
- at most one successful consume is ever committed,
- once a successful consume is committed, durable state cannot roll back from
  `Used`,
- durable `Used` requires its successful consume receipt,
- a successful consume receipt requires durable `Used`,
- durable progress beyond `Locked` requires a successful arm receipt,
- a fresh response is emitted only for an outcome already present in durable
  receipts,
- replay echoes a durable stored outcome,
- id conflict corresponds to a payload mismatch against a durable receipt,
- ambiguous recovery is silent and fail-closed.

## Storage contract implied by the model

A future storage backend must provide an equivalent of these properties:

1. State and the receipt set become authoritative at one recoverable commit point,
   or a journal/protocol must make recovery observationally equivalent to that.
2. A success or refusal response must not be published before that commit is
   durable.
3. Recovery must distinguish committed data from uncommitted prepared data.
4. A committed state transition and the receipt that explains it must recover
   together.
5. Request-id lookup after recovery must happen before re-evaluating the command.
6. If recovery cannot establish which committed pair is authoritative, the capsule
   must refuse service rather than choose a success or failure.
7. Reads must not expose speculative state that has not crossed the durable commit
   point.

This is an abstract contract, not a claim that any MirageOS block store, filesystem,
database, or host volume already satisfies it.

## Deliberate omissions

The model assumes one capsule and one in-flight mutation. It does not yet cover:

- a concrete MirageOS storage API,
- concurrent mutation scheduling,
- torn-sector or filesystem-specific failure modes,
- retention or garbage collection of request ids,
- authentication, authorization, or TLS,
- replicas or distributed consensus.

Those should be added only when a concrete next decision requires them.
