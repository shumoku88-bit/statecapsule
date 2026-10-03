# Request identity and replay semantics

StateCapsule treats a request id as an exact, process-lifetime identity binding.

For a request `(id, command)`:

1. If `id` has never been seen, the command is evaluated exactly once against the
   current capsule state. The resulting success or refusal is stored with that id.
2. If the same `id` is later submitted with the same command, the stored outcome
   is replayed. The command is not evaluated again.
3. If the same `id` is later submitted with a different command, the request is
   refused as an id conflict. The original binding is not replaced.

Refusals are durable **within the process lifetime** too. For example:

```text
state = Locked

id=a, Consume
  -> fresh refusal: not_armed

id=b, Arm
  -> fresh success: Armed

id=a, Consume
  -> replay refusal: not_armed
  -> state remains Armed
```

That rule prevents an ambiguous retry from changing meaning merely because some
other request changed the state in between.

## What this establishes

The OCaml `Request_machine` now owns request identity, replay, and conflicting
payload behavior independently of HTTP.

The bounded TLA+ model uses two request ids and both commands to check:

- one id cannot become bound to two different payloads,
- a replay echoes the stored outcome,
- a conflicting payload is detected,
- replay/conflict do not create another successful consume,
- reaching `Used` requires exactly one successful consume.

## What this does not establish

There is still no persistence. Restarting the process forgets all request ids and
resets the capsule to `Locked`.

The MirageOS HTTP boundary now maps this contract to the `Idempotency-Key`
request header for mutating POST endpoints:

```text
POST /arm
Idempotency-Key: arm-1

POST /consume
Idempotency-Key: consume-1
```

Missing or empty keys are rejected before command evaluation. HTTP responses
distinguish the stored request outcome from the capsule's current state, which is
important when replaying an old refusal after later state changes.

There is still no:

- authentication or authorization,
- distributed or multi-replica coordination,
- retention or garbage-collection policy for request ids,
- crash atomicity between state change and request-id recording.

Those boundaries must be specified before this mechanism is used as a durable
network idempotency guarantee.
