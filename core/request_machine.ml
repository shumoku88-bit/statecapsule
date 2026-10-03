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

let outcome_equal left right =
  match left, right with
  | Applied a, Applied b -> a = b
  | Refused a, Refused b -> a = b
  | _ -> false

let hex_digit value =
  if value < 10 then Char.chr (Char.code '0' + value)
  else Char.chr (Char.code 'a' + value - 10)

let hex_encode value =
  let encoded = Bytes.create (String.length value * 2) in
  String.iteri
    (fun index ch ->
      let byte = Char.code ch in
      Bytes.set encoded (index * 2) (hex_digit (byte lsr 4));
      Bytes.set encoded ((index * 2) + 1) (hex_digit (byte land 0x0f)))
    value;
  Bytes.unsafe_to_string encoded

let nibble = function
  | '0' .. '9' as ch -> Ok (Char.code ch - Char.code '0')
  | 'a' .. 'f' as ch -> Ok (Char.code ch - Char.code 'a' + 10)
  | 'A' .. 'F' as ch -> Ok (Char.code ch - Char.code 'A' + 10)
  | _ -> Error "invalid hexadecimal request id"

let hex_decode value =
  let length = String.length value in
  if length mod 2 <> 0 then Error "invalid hexadecimal request id"
  else
    let decoded = Bytes.create (length / 2) in
    let rec loop index =
      if index = length then Ok (Bytes.unsafe_to_string decoded)
      else
        match nibble value.[index], nibble value.[index + 1] with
        | Ok high, Ok low ->
            Bytes.set decoded (index / 2) (Char.chr ((high lsl 4) lor low));
            loop (index + 2)
        | Error error, _
        | _, Error error ->
            Error error
    in
    loop 0

let state_of_string = function
  | "locked" -> Ok State.Locked
  | "armed" -> Ok State.Armed
  | "used" -> Ok State.Used
  | value -> Error (Printf.sprintf "unknown state %S" value)

let command_of_string = function
  | "arm" -> Ok State.Arm
  | "consume" -> Ok State.Consume
  | value -> Error (Printf.sprintf "unknown command %S" value)

let refusal_of_string = function
  | "already_armed" -> Ok State.Already_armed
  | "not_armed" -> Ok State.Not_armed
  | "already_used" -> Ok State.Already_used
  | value -> Error (Printf.sprintf "unknown refusal %S" value)

let encode_outcome = function
  | Applied state ->
      "applied|" ^ State.to_string state
  | Refused refusal ->
      "refused|" ^ State.refusal_to_string refusal

let decode_outcome kind value =
  match kind with
  | "applied" ->
      Result.map (fun state -> Applied state) (state_of_string value)
  | "refused" ->
      Result.map (fun refusal -> Refused refusal) (refusal_of_string value)
  | _ ->
      Error (Printf.sprintf "unknown outcome kind %S" kind)

let encode_receipt (request_id, receipt) =
  String.concat "|"
    [ "receipt=" ^ hex_encode request_id
    ; State.command_to_string receipt.command
    ; encode_outcome receipt.outcome
    ]

let snapshot_body t =
  let receipts =
    t.seen
    |> List.rev
    |> List.map encode_receipt
  in
  String.concat "\n"
    ("SC1" :: ("state=" ^ State.to_string t.state) :: receipts)

let snapshot t =
  let body = snapshot_body t in
  let checksum = Digest.to_hex (Digest.string body) in
  body ^ "\nchecksum=" ^ checksum

let decode_receipt line =
  match String.split_on_char '|' line with
  | [ id_field; command_text; outcome_kind; outcome_value ] ->
      let prefix = "receipt=" in
      let prefix_length = String.length prefix in
      if String.length id_field < prefix_length
         || not (String.equal
                   (String.sub id_field 0 prefix_length)
                   prefix)
      then
        Error "invalid receipt prefix"
      else
        let id_hex =
          String.sub id_field prefix_length
            (String.length id_field - prefix_length)
        in
        (match hex_decode id_hex with
         | Error error -> Error error
         | Ok request_id ->
             (match command_of_string command_text with
              | Error error -> Error error
              | Ok command ->
                  Result.map
                    (fun outcome -> request_id, command, outcome)
                    (decode_outcome outcome_kind outcome_value)))
  | _ ->
      Error "invalid receipt shape"

let split_last values =
  let rec loop reversed = function
    | [] -> Error "snapshot is empty"
    | [ last ] -> Ok (List.rev reversed, last)
    | head :: tail -> loop (head :: reversed) tail
  in
  loop [] values

let restore payload =
  let lines = String.split_on_char '\n' payload in
  match split_last lines with
  | Error error -> Error error
  | Ok (body_lines, checksum_line) ->
      let checksum_prefix = "checksum=" in
      let checksum_prefix_length = String.length checksum_prefix in
      if String.length checksum_line <= checksum_prefix_length
         || not (String.equal
                   (String.sub checksum_line 0 checksum_prefix_length)
                   checksum_prefix)
      then
        Error "missing snapshot checksum"
      else
        let expected_checksum =
          String.sub checksum_line checksum_prefix_length
            (String.length checksum_line - checksum_prefix_length)
        in
        let body = String.concat "\n" body_lines in
        let actual_checksum = Digest.to_hex (Digest.string body) in
        if not (String.equal expected_checksum actual_checksum) then
          Error "snapshot checksum mismatch"
        else
          match body_lines with
          | "SC1" :: state_line :: receipt_lines ->
              let state_prefix = "state=" in
              let state_prefix_length = String.length state_prefix in
              if String.length state_line <= state_prefix_length
                 || not (String.equal
                           (String.sub state_line 0 state_prefix_length)
                           state_prefix)
              then
                Error "missing snapshot state"
              else
                let state_text =
                  String.sub state_line state_prefix_length
                    (String.length state_line - state_prefix_length)
                in
                (match state_of_string state_text with
                 | Error error -> Error error
                 | Ok expected_state ->
                     let rec rebuild machine = function
                       | [] ->
                           if state machine = expected_state then Ok machine
                           else Error "snapshot final state disagrees with receipts"
                       | line :: rest ->
                           (match decode_receipt line with
                            | Error error -> Error error
                            | Ok (request_id, command, expected_outcome) ->
                                let next, response =
                                  submit machine ~request_id command
                                in
                                (match response with
                                 | Fresh actual_outcome
                                   when outcome_equal actual_outcome expected_outcome ->
                                     rebuild next rest
                                 | Fresh _ ->
                                     Error "stored receipt outcome disagrees with state machine"
                                 | Replay _ ->
                                     Error "duplicate request id in snapshot"
                                 | Id_conflict ->
                                     Error "conflicting request id in snapshot"))
                     in
                     rebuild initial receipt_lines)
          | _ ->
              Error "unsupported snapshot format"

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
