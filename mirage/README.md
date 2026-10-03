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

## hvt artifact

The same adapter can also be cross-compiled as a Solo5 `hvt` unikernel:

```sh
bash tools/build-mirage-hvt
```

A successful build produces:

```text
mirage/dist/statecapsule-http.hvt
```

CI verifies that the file exists, records its SHA-256 digest, and asks
`solo5-elftool query-manifest` to inspect the embedded Solo5 application
manifest. The workflow also uploads the resulting `.hvt` file as a GitHub
Actions artifact.

This qualifies **artifact construction**, not boot. Running an `hvt` network
unikernel requires a suitable Solo5 tender plus a host network device such as a
TAP interface. That runtime boundary is intentionally separate from this build
check.

## hvt runtime check

The repository can also attempt to boot the generated hvt artifact on Linux and
drive the same HTTP state transition path through a private TAP network:

```sh
bash tools/check-mirage-hvt-runtime
```

The check creates a temporary host-only bridge and TAP device, boots the
unikernel with `solo5-hvt`, assigns the guest a private static IPv4 address,
and verifies:

```text
GET  /state      -> locked
POST /arm        -> armed
POST /consume    -> used
POST /consume    -> HTTP 409 / already_used
GET  /state      -> used
```

This check requires `/dev/kvm`. GitHub-hosted runners may expose nested
virtualization, but GitHub documents it as experimental and unsupported.
Therefore a green CI run is evidence for the concrete runner used by that run,
not a portability guarantee for all hosted runners.

The TAP network is private to the CI host and does not expose the service to the
public Internet.

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
