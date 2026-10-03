# Formal model

The first StateCapsule has exactly three states and two accepted transitions:

    Locked --Arm--> Armed --Consume--> Used

StateCapsule.tla models only the accepted transition relation. Refused commands
remain outside Next; the OCaml core makes those refusals explicit.

The model currently covers only the pure state machine. It does not cover:

- networking or HTTP
- authentication or authorization
- persistence
- process crashes or reboot
- request identity or replay
- multiple replicas
- clocks or timeouts

The correspondence claim is intentionally small: the OCaml transition table and
the TLA+ Next relation should admit the same successful state changes.

Before a remote or durable capsule exists, extend the specification for request
identity, replay, persistence, and crash semantics instead of treating this model
as evidence for those properties.


## Model checking

CI runs TLC with the repository command:

```sh
bash tools/check-tla
```

The command pins the stable TLA+ Tools 1.7.2 release and verifies the upstream
published SHA-1 before execution. The current model intentionally permits the
terminal `Used` state, so TLC is invoked with deadlock checking disabled; reaching
that terminal state is expected behavior, not a model failure.

A successful run qualifies only this bounded three-state model and its configured
`TypeOK` invariant. It is not evidence for persistence, networking, replay,
authentication, or the OCaml implementation itself.
