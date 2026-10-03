(* mirage >= 4.11.0 & < 4.12.0 *)
open Mirage

let port = Runtime_arg.create ~pos:__POS__ "Unikernel.port"

let main =
  main "Unikernel.Make"
    ~packages:[ package "statecapsule" ~sublibs:[ "core" ] ]
    (http_server @-> job)

let stackv4v6 = generic_stackv4v6 default_network
let tcpv4v6 = tcpv4v6_of_stackv4v6 stackv4v6
let http_server = paf_server ~port tcpv4v6

let () =
  register "statecapsule-http"
    [ main $ http_server ]
