# MirageOS adapter

This directory exposes the existing StateCapsule core through a deliberately tiny
HTTP boundary.

Endpoints:

- `GET /state`
- `POST /arm`
- `POST /consume`

The adapter does not implement any new state-transition semantics. Successful and
refused transitions still come from `Statecapsule_core.State.apply`.

## Development target

The first qualified target is MirageOS Unix with host/socket networking:

```sh
opam install .
opam install mirage.4.11.2
cd mirage
mirage configure -t unix --net socket
make depends
dune build
./dist/statecapsule-http --port 8080
```

Then, from another terminal:

```sh
curl http://127.0.0.1:8080/state
curl -X POST http://127.0.0.1:8080/arm
curl -X POST http://127.0.0.1:8080/consume
```

## Important limits

This is **not** a remotely safe service.

There is currently:

- no TLS
- no authentication or authorization
- no request identity or replay protection
- no persistence
- no crash or reboot continuity
- no multi-replica semantics

The mutable reference in `unikernel.ml` belongs to the runtime adapter. It keeps
one process-local current state so that HTTP requests can drive the already pure
transition function.

Restarting the process resets the capsule to `Locked`.

Do not expose this HTTP service to the public Internet.
