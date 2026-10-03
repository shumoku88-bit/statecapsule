open Cmdliner

let port =
  let doc = Arg.info ~doc:"Port of the StateCapsule HTTP service." [ "p"; "port" ] in
  Arg.(value & opt int 8080 doc)

module Make (HTTP_server : Paf_mirage.S with type ipaddr = Ipaddr.t) = struct
  module State = Statecapsule_core.State

  let current = ref State.initial

  let json_state () =
    Printf.sprintf {|{"state":"%s"}
|} (State.to_string !current)

  let json_refusal refusal =
    Printf.sprintf
      {|{"error":"%s","state":"%s"}
|}
      (State.refusal_to_string refusal)
      (State.to_string !current)

  let respond reqd status body =
    let headers =
      H1.Headers.of_list
        [ ("content-length", string_of_int (String.length body))
        ; ("content-type", "application/json")
        ; ("connection", "close")
        ]
    in
    let response = H1.Response.create ~headers status in
    H1.Reqd.respond_with_string reqd response body

  let apply reqd command =
    match State.apply !current command with
    | Ok next ->
        current := next;
        respond reqd `OK (json_state ())
    | Error refusal ->
        respond reqd `Conflict (json_refusal refusal)

  let request_handler _flow (_ipaddr, _port) reqd =
    let request = H1.Reqd.request reqd in
    H1.Body.Reader.close (H1.Reqd.request_body reqd);
    match request.H1.Request.meth, request.H1.Request.target with
    | `GET, "/state" ->
        respond reqd `OK (json_state ())
    | `POST, "/arm" ->
        apply reqd State.Arm
    | `POST, "/consume" ->
        apply reqd State.Consume
    | _ ->
        respond reqd `Not_found {|{"error":"not_found"}
|}

  let error_handler (_ipaddr, _port) ?request:_ _error _send = ()

  let start http_server =
    let service =
      HTTP_server.http_service ~error_handler request_handler
    in
    let (`Initialized thread) = Paf.serve service http_server in
    thread
end
