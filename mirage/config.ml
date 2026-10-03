(* mirage >= 4.11.0 & < 4.12.0 *)
open Mirage

let port = Runtime_arg.create ~pos:__POS__ "Unikernel.port"
let program_block_size =
  Runtime_arg.create ~pos:__POS__ "Unikernel.program_block_size"
let failure_point =
  Runtime_arg.create ~pos:__POS__ "Unikernel.failure_point"

let main =
  main "Unikernel.Make"
    ~packages:[ package "statecapsule" ~sublibs:[ "core" ] ]
    ~runtime_args:[ Runtime_arg.v failure_point ]
    (http_server @-> kv_rw @-> job)

let stackv4v6 = generic_stackv4v6 default_network
let tcpv4v6 = tcpv4v6_of_stackv4v6 stackv4v6
let http_server = paf_server ~port tcpv4v6

let block = block_of_file "capsule"
let store = chamelon ~program_block_size block

let () =
  register "statecapsule-http"
    [ main $ http_server $ store ]
