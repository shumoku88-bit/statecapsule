# MirageOS adapter

This directory exposes the existing StateCapsule core through a deliberately tiny
HTTP boundary and persists one authoritative request-machine snapshot through a
Chamelon `Mirage_kv.RW` store.

Endpoints:

- `GET /state`
- `POST /arm`
- `POST /consume`

The adapter does not implement transition or replay semantics. Those remain in
`Statecapsule_core`.

## Persistent snapshot

The MirageOS adapter stores exactly one key:

```text
/capsule
```

The value contains the state plus the complete request receipt history as one
versioned, checksummed core snapshot. A fresh mutation is evaluated in memory,
then the complete next snapshot is committed with one `Store.set`. Only after
that call succeeds does the adapter publish the new in-memory state and HTTP
response.

Replays and id conflicts do not write storage because they do not change the
request machine.

On restore, the core checks the checksum and replays every receipt from
`Locked` to verify that all recorded outcomes and the final state agree with the
pure state machine. Invalid persistent data causes startup to fail closed.

The checksum detects accidental corruption; it is not authentication or a
security boundary.

## Development target

Create a fresh Chamelon image, configure MirageOS Unix, and run the service:

```sh
opam install .
opam install mirage.4.11.2 chamelon-unix
bash tools/create-capsule-image capsule

cd mirage
mirage configure -t unix --net socket
make depends
dune build
cd ..

./mirage/dist/statecapsule-http --port 8080
```

The Unix block adapter opens `capsule` from the process working directory.

## Qualified reboot behavior

`tools/check-mirage-unix` and `tools/check-mirage-hvt-runtime` use the same
backing image across process/guest restarts and verify:

```text
fresh image
  -> Locked

Consume id=too-early
  -> fresh Refused(not_armed)

Arm id=arm-1
  -> fresh Applied(Armed)

restart with same image
  -> Armed
  -> too-early replays Refused(not_armed)
  -> arm-1 replays Applied(Armed)

Consume id=consume-1
  -> fresh Applied(Used)

restart with same image
  -> Used
  -> consume-1 replays Applied(Used)
```

The checks then overwrite `/capsule` with malformed content and require the
next boot to terminate rather than silently reset to `Locked`.

## hvt artifact

The adapter can be cross-compiled as a Solo5 `hvt` unikernel:

```sh
bash tools/build-mirage-hvt
```

The embedded Solo5 manifest now includes both the network interface and the
named `capsule` block device. At runtime the tender must attach a formatted
image:

```sh
solo5-hvt \
  --net:service=<tap> \
  --block:capsule=<image> \
  -- mirage/dist/statecapsule-http.hvt ...
```

## What the runtime evidence establishes

A green Unix or hvt runtime check is evidence, for that concrete runner and
backing image, that:

- state survives a process/guest restart,
- refusal receipts survive and replay,
- successful transition receipts survive and replay,
- a successful consume is not re-evaluated after restart,
- malformed snapshot content fails closed.

## Important durability limit

This does **not** yet establish host-power-loss durability.

The current Solo5 hvt block path ultimately services writes with host
`pwrite()`, and the exposed `Mirage_block.S` interface does not provide an
explicit host flush/barrier operation that StateCapsule can point to.

Therefore this milestone qualifies guest/tender/process restart continuity only.
It does not claim survival of host-kernel crash, host power loss, host page-cache
loss, or storage-controller cache loss.

There is still no:

- TLS,
- authentication or authorization,
- multi-replica semantics,
- public-Internet safety.

Do not expose this HTTP service to the public Internet.
