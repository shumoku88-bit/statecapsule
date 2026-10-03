open Cmdliner
open Lwt.Infix

let port =
  let doc = Arg.info ~doc:"Port of the StateCapsule HTTP service." [ "p"; "port" ] in
  Arg.(value & opt int 8080 doc)

let program_block_size =
  let doc =
    Arg.info
      ~doc:"Program block size used by the Chamelon persistent store."
      [ "program-block-size" ]
  in
  Arg.(value & opt int 16 doc)

type failure_point =
  | No_failure
  | Before_commit
  | After_commit_before_publish

let failure_point =
  let values =
    [ "none", No_failure
    ; "before-commit", Before_commit
    ; "after-commit-before-publish", After_commit_before_publish
    ]
  in
  let doc =
    "TEST ONLY. Pause a fresh mutation at a persistence boundary so an external      harness can kill the unikernel. Production/default value is none."
  in
  Arg.(value & opt (enum values) No_failure & info ~doc [ "failure-point" ])

module Make
    (HTTP_server : Paf_mirage.S with type ipaddr = Ipaddr.t)
    (Store : Mirage_kv.RW) =
struct
  module State = Statecapsule_core.State
  module Request = Statecapsule_core.Request_machine

  let capsule_key = Mirage_kv.Key.v "/capsule"
  let current = ref Request.initial
  let blocked = ref false
  let mutation_lock = Lwt_mutex.create ()

  let failure_point_to_string = function
    | No_failure -> "none"
    | Before_commit -> "before-commit"
    | After_commit_before_publish -> "after-commit-before-publish"

  let pause_at configured expected =
    if configured = expected then begin
      Logs.warn (fun log ->
        log "STATECAPSULE_FAILPOINT %s"
          (failure_point_to_string expected));
      let forever, _wake = Lwt.wait () in
      forever
    end else
      Lwt.return_unit

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

  let fail_storage reqd message =
    blocked := true;
    Logs.err (fun log -> log "%s" message);
    respond reqd `Internal_server_error (json_error "storage_unavailable")

  let commit store machine =
    Store.set store capsule_key (Request.snapshot machine)

  let submit store failure_point reqd request command =
    match H1.Headers.get request.H1.Request.headers "idempotency-key" with
    | None ->
        respond reqd `Bad_request (json_error "missing_idempotency_key")
    | Some raw_request_id ->
        let request_id = String.trim raw_request_id in
        if String.equal request_id "" then
          respond reqd `Bad_request (json_error "missing_idempotency_key")
        else
          Lwt.async (fun () ->
            Lwt_mutex.with_lock mutation_lock (fun () ->
              if !blocked then begin
                respond reqd `Internal_server_error
                  (json_error "storage_unavailable");
                Lwt.return_unit
              end else
                let next, response =
                  Request.submit !current ~request_id command
                in
                match response with
                | Request.Replay outcome ->
                    respond_outcome reqd "replay" outcome;
                    Lwt.return_unit
                | Request.Id_conflict ->
                    respond reqd `Conflict (json_error "id_conflict");
                    Lwt.return_unit
                | Request.Fresh outcome ->
                    pause_at failure_point Before_commit >>= fun () ->
                    commit store next >>= function
                    | Ok () ->
                        pause_at failure_point After_commit_before_publish
                        >>= fun () ->
                        current := next;
                        respond_outcome reqd "fresh" outcome;
                        Lwt.return_unit
                    | Error error ->
                        fail_storage reqd
                          (Fmt.str "persistent commit failed: %a"
                             Store.pp_write_error error);
                        Lwt.return_unit))

  let request_handler store failure_point _flow (_ipaddr, _port) reqd =
    let request = H1.Reqd.request reqd in
    H1.Body.Reader.close (H1.Reqd.request_body reqd);
    if !blocked then
      respond reqd `Internal_server_error (json_error "storage_unavailable")
    else
      match request.H1.Request.meth, request.H1.Request.target with
      | `GET, "/state" ->
          respond reqd `OK (json_state ())
      | `POST, "/arm" ->
          submit store failure_point reqd request State.Arm
      | `POST, "/consume" ->
          submit store failure_point reqd request State.Consume
      | _ ->
          respond reqd `Not_found {|{"error":"not_found"}
|}

  let error_handler (_ipaddr, _port) ?request:_ _error _send = ()

  let load store =
    Store.get store capsule_key >>= function
    | Ok payload ->
        (match Request.restore payload with
         | Ok machine ->
             Logs.info (fun log ->
               log "restored durable capsule state=%s receipts=%d"
                 (State.to_string (Request.state machine))
                 (Request.seen_count machine));
             Lwt.return machine
         | Error error ->
             let message =
               Printf.sprintf "invalid persisted capsule snapshot: %s" error
             in
             Logs.err (fun log -> log "%s" message);
             Lwt.fail_with message)
    | Error (`Not_found _) ->
        let machine = Request.initial in
        commit store machine >>= (function
          | Ok () ->
              Logs.info (fun log -> log "initialized fresh durable capsule");
              Lwt.return machine
          | Error error ->
              Lwt.fail_with
                (Fmt.str "initial persistent commit failed: %a"
                   Store.pp_write_error error))
    | Error error ->
        Lwt.fail_with
          (Fmt.str "persistent load failed: %a" Store.pp_error error)

  let start http_server store failure_point =
    load store >>= fun machine ->
    current := machine;
    let service =
      HTTP_server.http_service
        ~error_handler
        (request_handler store failure_point)
    in
    let (`Initialized thread) = Paf.serve service http_server in
    thread
end
