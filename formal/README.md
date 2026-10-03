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
