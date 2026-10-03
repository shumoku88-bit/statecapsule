(** Request identity and replay semantics layered over the pure State machine.

    The first use of a request id binds that id to both its command and its
    resulting outcome. Reusing the same id with the same command replays the
    stored outcome without reapplying the command. Reusing the same id with a
    different command is refused as an id conflict.

    Refused commands are recorded too. A retry therefore cannot become
    successful merely because the capsule state changed after the first
    attempt. *)

type request_id = string

type outcome =
  | Applied of State.t
  | Refused of State.refusal

type response =
  | Fresh of outcome
  | Replay of outcome
  | Id_conflict

type t

val initial : t
val state : t -> State.t
val seen_count : t -> int

val submit :
  t ->
  request_id:request_id ->
  State.command ->
  t * response

(** [snapshot t] serializes the complete request machine, including the
    request receipts needed for replay after recovery. The format contains a
    version marker and an integrity checksum. The checksum detects accidental
    corruption; it is not an authentication mechanism. *)
val snapshot : t -> string

(** [restore payload] validates and reconstructs a snapshot. Validation
    replays every stored receipt from the initial state and requires the stored
    final state and every stored outcome to agree with the pure state machine.
    Invalid, duplicate, corrupt, or semantically inconsistent data is rejected. *)
val restore : string -> (t, string) result

val outcome_to_string : outcome -> string
val response_to_string : response -> string
