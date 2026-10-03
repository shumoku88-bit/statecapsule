open Statecapsule_core

module Request = Request_machine

let state =
  Alcotest.testable
    (fun ppf value -> Format.pp_print_string ppf (State.to_string value))
    ( = )

let response =
  Alcotest.testable
    (fun ppf value ->
      Format.pp_print_string ppf (Request.response_to_string value))
    ( = )

let check_state expected machine =
  Alcotest.check state "state" expected (Request.state machine)

let check_seen expected machine =
  Alcotest.check Alcotest.int "seen requests" expected (Request.seen_count machine)

let test_fresh_success_is_recorded () =
  let machine, actual =
    Request.submit Request.initial ~request_id:"r1" State.Arm
  in
  Alcotest.check
    response
    "fresh response"
    (Request.Fresh (Request.Applied State.Armed))
    actual;
  check_state State.Armed machine;
  check_seen 1 machine

let test_same_id_same_command_replays_without_reapply () =
  let machine, _ =
    Request.submit Request.initial ~request_id:"r1" State.Arm
  in
  let replayed, actual =
    Request.submit machine ~request_id:"r1" State.Arm
  in
  Alcotest.check
    response
    "replay response"
    (Request.Replay (Request.Applied State.Armed))
    actual;
  check_state State.Armed replayed;
  check_seen 1 replayed

let test_same_id_different_command_conflicts () =
  let machine, _ =
    Request.submit Request.initial ~request_id:"r1" State.Arm
  in
  let conflicted, actual =
    Request.submit machine ~request_id:"r1" State.Consume
  in
  Alcotest.check response "id conflict" Request.Id_conflict actual;
  check_state State.Armed conflicted;
  check_seen 1 conflicted

let test_refusal_is_replayed_after_state_changes () =
  let machine, first =
    Request.submit Request.initial ~request_id:"too-early" State.Consume
  in
  Alcotest.check
    response
    "initial refusal"
    (Request.Fresh (Request.Refused State.Not_armed))
    first;
  check_state State.Locked machine;

  let machine, armed =
    Request.submit machine ~request_id:"arm-now" State.Arm
  in
  Alcotest.check
    response
    "arm"
    (Request.Fresh (Request.Applied State.Armed))
    armed;
  check_state State.Armed machine;

  let replayed, retry =
    Request.submit machine ~request_id:"too-early" State.Consume
  in
  Alcotest.check
    response
    "old refusal stays old"
    (Request.Replay (Request.Refused State.Not_armed))
    retry;
  check_state State.Armed replayed;
  check_seen 2 replayed

let test_successful_consume_replays_at_terminal_state () =
  let machine, _ =
    Request.submit Request.initial ~request_id:"arm" State.Arm
  in
  let machine, first =
    Request.submit machine ~request_id:"consume" State.Consume
  in
  Alcotest.check
    response
    "first consume"
    (Request.Fresh (Request.Applied State.Used))
    first;
  check_state State.Used machine;

  let replayed, retry =
    Request.submit machine ~request_id:"consume" State.Consume
  in
  Alcotest.check
    response
    "consume replay"
    (Request.Replay (Request.Applied State.Used))
    retry;
  check_state State.Used replayed;
  check_seen 2 replayed

let test_new_id_observes_current_state () =
  let machine, _ =
    Request.submit Request.initial ~request_id:"arm-1" State.Arm
  in
  let machine, actual =
    Request.submit machine ~request_id:"arm-2" State.Arm
  in
  Alcotest.check
    response
    "new id gets a fresh current-state result"
    (Request.Fresh (Request.Refused State.Already_armed))
    actual;
  check_state State.Armed machine;
  check_seen 2 machine

let test_snapshot_restores_state_and_replay_history () =
  let machine, _ =
    Request.submit Request.initial ~request_id:"too-early" State.Consume
  in
  let machine, _ =
    Request.submit machine ~request_id:"arm-1" State.Arm
  in
  let payload = Request.snapshot machine in
  match Request.restore payload with
  | Error error ->
      Alcotest.failf "snapshot restore failed: %s" error
  | Ok restored ->
      check_state State.Armed restored;
      check_seen 2 restored;
      let restored, early =
        Request.submit restored ~request_id:"too-early" State.Consume
      in
      Alcotest.check
        response
        "restored refusal replays"
        (Request.Replay (Request.Refused State.Not_armed))
        early;
      let restored, arm =
        Request.submit restored ~request_id:"arm-1" State.Arm
      in
      Alcotest.check
        response
        "restored success replays"
        (Request.Replay (Request.Applied State.Armed))
        arm;
      check_state State.Armed restored;
      check_seen 2 restored

let test_snapshot_checksum_rejects_corruption () =
  let machine, _ =
    Request.submit Request.initial ~request_id:"arm-1" State.Arm
  in
  let payload = Request.snapshot machine in
  let corrupted =
    if String.length payload = 0 then payload
    else
      let bytes = Bytes.of_string payload in
      Bytes.set bytes 0 'X';
      Bytes.unsafe_to_string bytes
  in
  match Request.restore corrupted with
  | Ok _ -> Alcotest.fail "corrupt snapshot unexpectedly restored"
  | Error _ -> ()

let with_recomputed_checksum body =
  body ^ "\nchecksum=" ^ Digest.to_hex (Digest.string body)

let test_snapshot_semantics_reject_inconsistent_final_state () =
  let machine, _ =
    Request.submit Request.initial ~request_id:"arm-1" State.Arm
  in
  let payload = Request.snapshot machine in
  let lines = String.split_on_char '\n' payload in
  let body_lines =
    match List.rev lines with
    | _checksum :: reversed_body -> List.rev reversed_body
    | [] -> []
  in
  let inconsistent_body =
    body_lines
    |> List.mapi (fun index line ->
      if index = 1 then "state=used" else line)
    |> String.concat "\n"
  in
  let inconsistent = with_recomputed_checksum inconsistent_body in
  match Request.restore inconsistent with
  | Ok _ -> Alcotest.fail "semantically inconsistent snapshot restored"
  | Error _ -> ()

let () =
  Alcotest.run
    "request-machine"
    [ "identity"
    , [ Alcotest.test_case
          "fresh success is recorded"
          `Quick
          test_fresh_success_is_recorded
      ; Alcotest.test_case
          "same id and command replays"
          `Quick
          test_same_id_same_command_replays_without_reapply
      ; Alcotest.test_case
          "same id different command conflicts"
          `Quick
          test_same_id_different_command_conflicts
      ; Alcotest.test_case
          "refusal is replayed after state changes"
          `Quick
          test_refusal_is_replayed_after_state_changes
      ; Alcotest.test_case
          "successful consume replays at terminal state"
          `Quick
          test_successful_consume_replays_at_terminal_state
      ; Alcotest.test_case
          "new id observes current state"
          `Quick
          test_new_id_observes_current_state
      ]
    ; "snapshot"
    , [ Alcotest.test_case
          "restores state and replay history"
          `Quick
          test_snapshot_restores_state_and_replay_history
      ; Alcotest.test_case
          "checksum rejects corruption"
          `Quick
          test_snapshot_checksum_rejects_corruption
      ; Alcotest.test_case
          "semantic validation rejects inconsistent state"
          `Quick
          test_snapshot_semantics_reject_inconsistent_final_state
      ]
    ]
