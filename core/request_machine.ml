type request_id = string

type outcome =
  | Applied of State.t
  | Refused of State.refusal

type response =
  | Fresh of outcome
  | Replay of outcome
  | Id_conflict

type receipt =
  { command : State.command
  ; outcome : outcome
  }

type t =
  { state : State.t
  ; seen : (request_id * receipt) list
  }

let initial =
  { state = State.initial
  ; seen = []
  }

let state t = t.state
let seen_count t = List.length t.seen

let command_equal a b =
  match a, b with
  | State.Arm, State.Arm
  | State.Consume, State.Consume -> true
  | _ -> false

let find_receipt request_id seen =
  seen
  |> List.find_map (fun (candidate_id, receipt) ->
    if String.equal candidate_id request_id then Some receipt else None)

let apply_once state command =
  match State.apply state command with
  | Ok next -> next, Applied next
  | Error refusal -> state, Refused refusal

let submit t ~request_id command =
  match find_receipt request_id t.seen with
  | Some receipt when command_equal receipt.command command ->
      t, Replay receipt.outcome
  | Some _ ->
      t, Id_conflict
  | None ->
      let next_state, outcome = apply_once t.state command in
      let receipt = { command; outcome } in
      { state = next_state
      ; seen = (request_id, receipt) :: t.seen
      },
      Fresh outcome

let outcome_to_string = function
  | Applied state ->
      Printf.sprintf "applied:%s" (State.to_string state)
  | Refused refusal ->
      Printf.sprintf "refused:%s" (State.refusal_to_string refusal)

let response_to_string = function
  | Fresh outcome ->
      Printf.sprintf "fresh:%s" (outcome_to_string outcome)
  | Replay outcome ->
      Printf.sprintf "replay:%s" (outcome_to_string outcome)
  | Id_conflict ->
      "id_conflict"
