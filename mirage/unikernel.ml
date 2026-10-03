open Cmdliner

let port =
  let doc = Arg.info ~doc:"Port of the StateCapsule HTTP service." [ "p"; "port" ] in
  Arg.(value & opt int 8080 doc)

module Make (HTTP_server : Paf_mirage.S with type ipaddr = Ipaddr.t) = struct
  module State = Statecapsule_core.State
  module Request = Statecapsule_core.Request_machine

  let current = ref Request.initial

  let current_state_string () =
    State.to_string (Request.state !current)

  let json_state () =
    Printf.sprintf {|{"state":"%s"}
|} (current_state_string ())

  let json_outcome = function
    | Request.Applied state ->
        Printf.sprintf
          {|{"kind":"applied","state":"%s"}|}
          (State.to_string state)
    | Request.Refused refusal ->
        Printf.sprintf
          {|{"kind":"refused","error":"%s"}|}
          (State.refusal_to_string refusal)

  let json_request kind outcome =
    Printf.sprintf
      {|{"request":"%s","outcome":%s,"current_state":"%s"}
|}
      kind
      (json_outcome outcome)
      (current_state_string ())

  let json_error error =
    Printf.sprintf
      {|{"error":"%s","current_state":"%s"}
|}
      error
      (current_state_string ())

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

  let respond_outcome reqd kind outcome =
    let status =
      match outcome with
      | Request.Applied _ -> `OK
      | Request.Refused _ -> `Conflict
    in
    respond reqd status (json_request kind outcome)

  let submit reqd request command =
    match H1.Headers.get request.H1.Request.headers "idempotency-key" with
    | None ->
        respond reqd `Bad_request (json_error "missing_idempotency_key")
    | Some raw_request_id ->
        let request_id = String.trim raw_request_id in
        if String.equal request_id "" then
          respond reqd `Bad_request (json_error "missing_idempotency_key")
        else
          let next, response =
            Request.submit !current ~request_id command
          in
          current := next;
          match response with
          | Request.Fresh outcome ->
              respond_outcome reqd "fresh" outcome
          | Request.Replay outcome ->
              respond_outcome reqd "replay" outcome
          | Request.Id_conflict ->
              respond reqd `Conflict (json_error "id_conflict")

  let request_handler _flow (_ipaddr, _port) reqd =
    let request = H1.Reqd.request reqd in
    H1.Body.Reader.close (H1.Reqd.request_body reqd);
    match request.H1.Request.meth, request.H1.Request.target with
    | `GET, "/state" ->
        respond reqd `OK (json_state ())
    | `POST, "/arm" ->
        submit reqd request State.Arm
    | `POST, "/consume" ->
        submit reqd request State.Consume
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
