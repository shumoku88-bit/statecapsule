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

val outcome_to_string : outcome -> string
val response_to_string : response -> string
