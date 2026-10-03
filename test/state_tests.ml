open Statecapsule_core

let state =
  Alcotest.testable
    (fun ppf value -> Format.pp_print_string ppf (State.to_string value))
    ( = )

let refusal =
  Alcotest.testable
    (fun ppf value -> Format.pp_print_string ppf (State.refusal_to_string value))
    ( = )

let check_transition from command expected =
  match expected, State.apply from command with
  | Ok expected_state, Ok actual_state ->
      Alcotest.check state "accepted state" expected_state actual_state
  | Error expected_refusal, Error actual_refusal ->
      Alcotest.check refusal "refusal" expected_refusal actual_refusal
  | Ok expected_state, Error actual_refusal ->
      Alcotest.failf
        "expected %s but got refusal %s"
        (State.to_string expected_state)
        (State.refusal_to_string actual_refusal)
  | Error expected_refusal, Ok actual_state ->
      Alcotest.failf
        "expected refusal %s but reached %s"
        (State.refusal_to_string expected_refusal)
        (State.to_string actual_state)

let test_initial () =
  Alcotest.check state "initial state" State.Locked State.initial

let test_complete_transition_table () =
  [ State.Locked, State.Arm, Ok State.Armed
  ; State.Locked, State.Consume, Error State.Not_armed
  ; State.Armed, State.Arm, Error State.Already_armed
  ; State.Armed, State.Consume, Ok State.Used
  ; State.Used, State.Arm, Error State.Already_used
  ; State.Used, State.Consume, Error State.Already_used
  ]
  |> List.iter (fun (from, command, expected) ->
    check_transition from command expected)

let test_happy_path () =
  match State.apply State.initial State.Arm with
  | Error refusal ->
      Alcotest.failf "arm refused: %s" (State.refusal_to_string refusal)
  | Ok armed ->
      (match State.apply armed State.Consume with
       | Error refusal ->
           Alcotest.failf "consume refused: %s" (State.refusal_to_string refusal)
       | Ok used ->
           Alcotest.check state "terminal state" State.Used used)

let () =
  Alcotest.run
    "statecapsule"
    [ "state"
    , [ Alcotest.test_case "initial" `Quick test_initial
      ; Alcotest.test_case
          "complete transition table"
          `Quick
          test_complete_transition_table
      ; Alcotest.test_case "happy path" `Quick test_happy_path
      ]
    ]
